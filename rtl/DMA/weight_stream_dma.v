`timescale 1ns/1ps

//=============================================================================
// Weight Stream DMA
//
// 将“Flash byte地址 + 256-bit块数”命令转换为外部Octal控制器读命令，
// 接收控制器已经完成DDR采样/CDC后的16-bit数据流，组装为256-bit块。
// 本模块是当前NPU真正使用的轻量DMA；第三方axi_dma_rd保留在third_party，
// 但其AXI Memory-Mapped主口不能直接连接S28HS512T OPI引脚。
//=============================================================================

module weight_stream_dma #(
    parameter TIMEOUT_CYCLES = 32'd2000000
) (
    input                                       clk,
    input                                       rst_n,
    input                                       cmd_valid,
    output                                      cmd_ready,
    input              [23:0]                   cmd_flash_base,
    input              [15:0]                   cmd_block_count,

    // 发往真正S28 OPI控制器或行为级数据源的命令接口。
    output                                      ext_cmd_valid,
    input                                       ext_cmd_ready,
    output             [23:0]                   ext_cmd_flash_base,
    output             [23:0]                   ext_cmd_byte_count,

    // OPI PHY跨时钟后提供的16-bit接收流。
    input                                       rx_valid,
    output                                      rx_ready,
    input              [15:0]                   rx_data,
    input                                       rx_last,
    input                                       rx_error,
    output                                      block_valid,
    input                                       block_ready,
    output             [15:0]                   block_index,
    output             [255:0]                  block_data,
    output reg                                  done,
    output                                      busy,
    output reg                                  error
);

localparam [1:0] S_IDLE = 2'd0,
S_SEND = 2'd1,
S_RECV = 2'd2;
reg [1:0]  state;
reg [23:0] flash_base_q;
reg [15:0] block_count_q;
reg [15:0] block_index_q;
reg [31:0] timeout_q;
reg        packer_clear;
wire       packed_valid;
wire       packed_ready;
wire       packer_in_ready;
wire [255:0] packed_data;
wire       packed_last;
wire       packed_error;
wire       final_block = (block_index_q == block_count_q - 1'b1);
assign cmd_ready          = (state == S_IDLE);
assign ext_cmd_valid      = (state == S_SEND);
assign ext_cmd_flash_base = flash_base_q;
assign ext_cmd_byte_count = {block_count_q,5'b0};
assign busy               = (state != S_IDLE);
assign block_valid = packed_valid && (state == S_RECV);
assign packed_ready = block_ready && (state == S_RECV);
assign block_index = block_index_q;
assign block_data  = packed_data;
assign rx_ready    = (state == S_RECV) && packer_in_ready;
octal_ddr_16to256_packer u_packer (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .clear                       (packer_clear),
    .in_valid                    (rx_valid && (state == S_RECV)),
    .in_ready                    (packer_in_ready),
    .in_data                     (rx_data),
    .in_last                     (rx_last),
    .in_error                    (rx_error),
    .out_valid                   (packed_valid),
    .out_ready                   (packed_ready),
    .out_data                    (packed_data),
    .out_last                    (packed_last),
    .out_error                   (packed_error)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        flash_base_q   <= 24'd0;
        block_count_q  <= 16'd0;
        block_index_q  <= 16'd0;
        timeout_q      <= 32'd0;
        packer_clear   <= 1'b0;
        done           <= 1'b0;
        error          <= 1'b0;
    end else begin
        done         <= 1'b0;
        packer_clear <= 1'b0;
        if (state != S_IDLE) begin
            if (timeout_q >= TIMEOUT_CYCLES) begin
                error        <= 1'b1;
                done         <= 1'b1;
                state        <= S_IDLE;
                packer_clear <= 1'b1;
            end else begin
                timeout_q <= timeout_q + 1'b1;
            end
        end
        case (state)
            S_IDLE: begin
                timeout_q <= 32'd0;
                if (cmd_valid && cmd_ready) begin
                    if (cmd_block_count == 0) begin
                        error <= 1'b1;
                        done  <= 1'b1;
                    end else begin
                        flash_base_q  <= cmd_flash_base;
                        block_count_q <= cmd_block_count;
                        block_index_q <= 16'd0;
                        error         <= 1'b0;
                        packer_clear  <= 1'b1;
                        state         <= S_SEND;
                    end
                end
            end
            S_SEND: begin
                if (ext_cmd_valid && ext_cmd_ready) begin
                    timeout_q <= 32'd0;
                    state     <= S_RECV;
                end
            end
            S_RECV: begin
                if (packed_valid && packed_ready) begin
                    timeout_q <= 32'd0;
                    if (packed_error || (packed_last != final_block)) begin
                        error <= 1'b1;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else if (final_block) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        block_index_q <= block_index_q + 1'b1;
                    end
                end
            end
            default: begin
                error <= 1'b1;
                done  <= 1'b1;
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
