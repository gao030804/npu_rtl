`timescale 1ns/1ps

//=============================================================================
// 完整帧数值回归专用的快速Weight Cache模型。
//
// 它保留NPU读请求、A/B bank配置和地址范围检查，但跳过位级SPI传输。
// 真实SPI时序由tb_weight_cache_ab单独验证；完整帧testbench根据block数量
// 换算25 MHz单线SPI的理论周期，并与实际卷积周期比较。
//=============================================================================
module weight_cache_ab_fast_model #(
    parameter MEMORY_BYTES = 934016
) (
    input clk, input rst_n,
    input req_valid, output req_ready, input [31:0] req_addr,
    output reg rsp_valid, input rsp_ready, output reg [255:0] rsp_data,
    input prefetch_valid, output prefetch_ready,
    input [23:0] prefetch_flash_base,
    input [15:0] prefetch_block_count,
    input prefetch_target_bank,
    output reg prefetch_done,
    input activate_valid, output activate_ready,
    input activate_first_layer, input activate_bank,
    output reg active_first_layer, output reg active_bank,
    output active_bank_valid, output first_layer_ready,
    output cache_busy, output reg cache_error,
    output flash_csn, output flash_sclk, output flash_mosi,
    input flash_miso
);

reg [7:0] memory [0:MEMORY_BYTES-1];
reg [255:0] first_sram [0:3];
reg [255:0] bank_a_sram [0:4095];
reg [255:0] bank_b_sram [0:4095];
reg [23:0] bank_base_a, bank_base_b;
reg [15:0] bank_blocks_a, bank_blocks_b;
reg bank_valid_a, bank_valid_b;
reg read_pending;
reg [31:0] read_addr_q;
reg prefetch_pending;
integer byte_index;
integer block_index;

initial begin
    $readmemh("tb/data/full_encoder/weights.mem", memory);
    // 第一层128 Byte权重直接预装到常驻SRAM。
    for (block_index=0; block_index<4; block_index=block_index+1)
        for (byte_index=0; byte_index<32; byte_index=byte_index+1)
            first_sram[block_index][8*byte_index +: 8] =
                memory[block_index*32+byte_index];
end

wire selected_valid = active_first_layer ? 1'b1 :
                      (active_bank ? bank_valid_b : bank_valid_a);
wire [23:0] selected_base = active_first_layer ? 24'h000000 :
                            (active_bank ? bank_base_b : bank_base_a);
wire [15:0] selected_blocks = active_first_layer ? 16'd4 :
                              (active_bank ? bank_blocks_b : bank_blocks_a);
wire [31:0] selected_end = {8'd0,selected_base} +
                           ({16'd0,selected_blocks} << 5);
wire request_in_range = (req_addr >= {8'd0,selected_base}) &&
                        ((req_addr + 31) < selected_end) &&
                        (req_addr[4:0] == 5'd0) &&
                        ((req_addr + 31) < MEMORY_BYTES);

assign req_ready = selected_valid && !read_pending && !rsp_valid;
assign prefetch_ready = !prefetch_pending &&
                        (active_first_layer ||
                         (prefetch_target_bank != active_bank));
assign activate_ready = activate_first_layer ? 1'b1 :
                        (activate_bank ? bank_valid_b : bank_valid_a);
assign active_bank_valid = selected_valid;
assign first_layer_ready = 1'b1;
assign cache_busy = prefetch_pending;
assign flash_csn = 1'b1;
assign flash_sclk = 1'b0;
assign flash_mosi = 1'b0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rsp_valid <= 1'b0;
        rsp_data <= 256'd0;
        read_pending <= 1'b0;
        read_addr_q <= 32'd0;
        prefetch_pending <= 1'b0;
        prefetch_done <= 1'b0;
        active_first_layer <= 1'b1;
        active_bank <= 1'b0;
        bank_base_a <= 24'd0;
        bank_base_b <= 24'd0;
        bank_blocks_a <= 16'd0;
        bank_blocks_b <= 16'd0;
        bank_valid_a <= 1'b0;
        bank_valid_b <= 1'b0;
        cache_error <= 1'b0;
    end else begin
        prefetch_done <= 1'b0;

        if (rsp_valid && rsp_ready)
            rsp_valid <= 1'b0;
        if (req_valid && req_ready) begin
            if (!request_in_range) begin
                cache_error <= 1'b1;
            end else begin
                read_addr_q <= req_addr;
                read_pending <= 1'b1;
            end
        end
        if (read_pending) begin
            if (active_first_layer)
                rsp_data <= first_sram[(read_addr_q-{8'd0,selected_base}) >> 5];
            else if (active_bank)
                rsp_data <= bank_b_sram[(read_addr_q-{8'd0,selected_base}) >> 5];
            else
                rsp_data <= bank_a_sram[(read_addr_q-{8'd0,selected_base}) >> 5];
            rsp_valid <= 1'b1;
            read_pending <= 1'b0;
        end

        if (prefetch_valid && prefetch_ready) begin
            if ((prefetch_block_count == 0) ||
                (prefetch_block_count > 4096) ||
                (({8'd0,prefetch_flash_base} +
                  ({16'd0,prefetch_block_count} << 5)) > MEMORY_BYTES)) begin
                cache_error <= 1'b1;
            end else begin
                if (prefetch_target_bank) begin
                    // testbench直接把该层权重预装进SRAM B，不消耗外部搬运周期。
                    for (block_index=0; block_index<prefetch_block_count;
                         block_index=block_index+1)
                        for (byte_index=0; byte_index<32; byte_index=byte_index+1)
                            bank_b_sram[block_index][8*byte_index +: 8] =
                                memory[prefetch_flash_base+block_index*32+byte_index];
                    bank_base_b <= prefetch_flash_base;
                    bank_blocks_b <= prefetch_block_count;
                    bank_valid_b <= 1'b1;
                end else begin
                    // testbench直接把该层权重预装进SRAM A。
                    for (block_index=0; block_index<prefetch_block_count;
                         block_index=block_index+1)
                        for (byte_index=0; byte_index<32; byte_index=byte_index+1)
                            bank_a_sram[block_index][8*byte_index +: 8] =
                                memory[prefetch_flash_base+block_index*32+byte_index];
                    bank_base_a <= prefetch_flash_base;
                    bank_blocks_a <= prefetch_block_count;
                    bank_valid_a <= 1'b1;
                end
                prefetch_pending <= 1'b1;
            end
        end else if (prefetch_pending) begin
            prefetch_pending <= 1'b0;
            prefetch_done <= 1'b1;
        end

        if (activate_valid && activate_ready) begin
            active_first_layer <= activate_first_layer;
            if (!activate_first_layer)
                active_bank <= activate_bank;
        end
    end
end

endmodule
