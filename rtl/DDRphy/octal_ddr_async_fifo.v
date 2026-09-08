`timescale 1ns/1ps

//=============================================================================
// 双时钟异步FIFO：用于Octal PHY时钟域到NPU系统时钟域的CDC。
// 数据通常为{error,last,data[15:0]}共18 bit。
//
// 指针采用Gray码跨时钟同步。ASIC/FPGA正式实现时可以用等价的双时钟
// SRAM/FIFO宏替换本模块，但valid/ready接口保持不变。
//=============================================================================

module octal_ddr_async_fifo #(
    parameter DATA_WIDTH = 18,
    parameter ADDR_WIDTH = 5
) (
    input                                       wr_clk,
    input                                       wr_rst_n,
    input                                       wr_valid,
    output                                      wr_ready,
    input              [DATA_WIDTH-1:0]         wr_data,
    input                                       rd_clk,
    input                                       rd_rst_n,
    output                                      rd_valid,
    input                                       rd_ready,
    output             [DATA_WIDTH-1:0]         rd_data
);

localparam DEPTH = (1 << ADDR_WIDTH);
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
reg [ADDR_WIDTH:0] wr_bin,wr_gray;
reg [ADDR_WIDTH:0] rd_bin,rd_gray;
reg [ADDR_WIDTH:0] rd_gray_sync1,rd_gray_sync2;
reg [ADDR_WIDTH:0] wr_gray_sync1,wr_gray_sync2;
wire wr_fire = wr_valid && wr_ready;
wire rd_fire = rd_valid && rd_ready;
wire [ADDR_WIDTH:0] wr_bin_next  = wr_bin + wr_fire;
wire [ADDR_WIDTH:0] rd_bin_next  = rd_bin + rd_fire;
wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
wire [ADDR_WIDTH:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
wire fifo_full = (wr_gray_next ==
    {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
    rd_gray_sync2[ADDR_WIDTH-2:0]});
wire fifo_empty = (rd_gray == wr_gray_sync2);
assign wr_ready = !fifo_full;
assign rd_valid = !fifo_empty;
assign rd_data  = mem[rd_bin[ADDR_WIDTH-1:0]];

always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_bin  <= 0;
        wr_gray <= 0;
    end else begin
        if (wr_fire)
            mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        wr_bin  <= wr_bin_next;
        wr_gray <= wr_gray_next;
    end
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_bin  <= 0;
        rd_gray <= 0;
    end else begin
        rd_bin  <= rd_bin_next;
        rd_gray <= rd_gray_next;
    end
end

// Gray指针各经过两级同步器进入对方时钟域。

always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        rd_gray_sync1 <= 0;
        rd_gray_sync2 <= 0;
    end else begin
        rd_gray_sync1 <= rd_gray;
        rd_gray_sync2 <= rd_gray_sync1;
    end
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        wr_gray_sync1 <= 0;
        wr_gray_sync2 <= 0;
    end else begin
        wr_gray_sync1 <= wr_gray;
        wr_gray_sync2 <= wr_gray_sync1;
    end
end

endmodule
