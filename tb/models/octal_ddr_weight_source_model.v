`timescale 1ns/1ps

//=============================================================================
// OPI控制器侧16-bit数据流行为模型。
//
// 注意：本模块不是S28HS512T引脚模型。它模拟“真正OPI控制器 + PHY + CDC”
// 已经完成之后的流接口，用于先验证DMA、组包器和A/B SRAM路径。
// 每个时钟传输16 bit，对应100 MHz × 8-bit DDR的200 MB/s原始数据率。
//=============================================================================
module octal_ddr_weight_source_model #(
    parameter MEM_BYTES = 1048576,
    parameter MEM_FILE  = "tb/data/full_encoder/weights.mem"
) (
    input             cmd_clk,
    input             phy_clk,
    input             rst_n,

    input             cmd_valid,
    output            cmd_ready,
    input      [23:0] cmd_flash_base,
    input      [23:0] cmd_byte_count,

    output reg        rx_valid,
    input             rx_ready,
    output reg [15:0] rx_data,
    output reg        rx_last,
    output reg        rx_error
);

reg [7:0] memory [0:MEM_BYTES-1];
reg [23:0] address_q;
reg [23:0] bytes_left_q;
reg        active_q;
reg [23:0] cmd_base_hold;
reg [23:0] cmd_count_hold;
reg        cmd_toggle;
reg        ack_toggle;
reg        ack_sync1,ack_sync2;
reg        cmd_sync1,cmd_sync2;

assign cmd_ready = (cmd_toggle == ack_sync2);

initial begin
    $readmemh(MEM_FILE, memory);
end

// 系统命令域：payload在对端ack之前保持稳定，toggle作为事件标志。
always @(posedge cmd_clk or negedge rst_n) begin
    if (!rst_n) begin
        cmd_base_hold  <= 24'd0;
        cmd_count_hold <= 24'd0;
        cmd_toggle     <= 1'b0;
        ack_sync1      <= 1'b0;
        ack_sync2      <= 1'b0;
    end else begin
        ack_sync1 <= ack_toggle;
        ack_sync2 <= ack_sync1;
        if (cmd_valid && cmd_ready) begin
            cmd_base_hold  <= cmd_flash_base;
            cmd_count_hold <= cmd_byte_count;
            cmd_toggle     <= ~cmd_toggle;
        end
    end
end

// PHY域：同步命令toggle并产生每周期一个16-bit的DDR聚合数据流。
always @(posedge phy_clk or negedge rst_n) begin
    if (!rst_n) begin
        address_q    <= 24'd0;
        bytes_left_q <= 24'd0;
        active_q     <= 1'b0;
        rx_valid     <= 1'b0;
        rx_data      <= 16'd0;
        rx_last      <= 1'b0;
        rx_error     <= 1'b0;
        ack_toggle   <= 1'b0;
        cmd_sync1    <= 1'b0;
        cmd_sync2    <= 1'b0;
    end else begin
        cmd_sync1 <= cmd_toggle;
        cmd_sync2 <= cmd_sync1;

        if (!active_q && (cmd_sync2 != ack_toggle)) begin
            address_q    <= cmd_base_hold;
            bytes_left_q <= cmd_count_hold;
            active_q     <= 1'b1;
            rx_valid     <= 1'b0;
            rx_last      <= 1'b0;
            rx_error     <= (cmd_count_hold == 0) || cmd_count_hold[0] ||
                            ({1'b0,cmd_base_hold} + cmd_count_hold > MEM_BYTES);
            ack_toggle   <= cmd_sync2;
        end else if (active_q) begin
            if (!rx_valid && (bytes_left_q >= 2)) begin
                rx_data  <= {memory[address_q+1],memory[address_q]};
                rx_valid <= 1'b1;
                rx_last  <= (bytes_left_q == 2);
            end else if (rx_valid && rx_ready && !rx_last) begin
                // 当前word被接受时，直接把下一word装入输出寄存器，
                // 因而正常情况下可做到每周期一个16-bit数据。
                rx_data      <= {memory[address_q+3],memory[address_q+2]};
                rx_last      <= (bytes_left_q == 4);
                address_q    <= address_q + 2'd2;
                bytes_left_q <= bytes_left_q - 2'd2;
            end else if (rx_valid && rx_ready && rx_last) begin
                rx_valid     <= 1'b0;
                rx_last      <= 1'b0;
                active_q     <= 1'b0;
                bytes_left_q <= 24'd0;
            end
        end
    end
end

endmodule
