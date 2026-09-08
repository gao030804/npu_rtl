// ============================================================================
// 中文阅读导引（当前实现）
// 保存Residual identity数据，默认1024×64 bit=8 KiB。
// 地址是64-bit字索引，不是外部Activation Byte地址；转换由capture/add模块完成。
// ============================================================================
//=============================================================================
// 模块：residual_scratchpad
// 功能：8 KiB Residual Skip临时存储，64 bit × 1024 words。
// capture阶段写、residual-add阶段读，两阶段不会同时发生。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 保存一个Residual Unit的identity分支，默认1024x64-bit=8 KiB。
// - 提供独立写入和读取握手；地址以64-bit word为单位，而非Activation Byte地址。
// -------------------------------------------------------------------------
module residual_scratchpad #(
    parameter ADDR_WIDTH = 10,
    parameter DEPTH = 1024
) (
    input                                       clk,
    input                                       rst_n,
    input                                       wr_valid,
    output                                      wr_ready,
    input              [ADDR_WIDTH-1:0]         wr_addr,
    input              [63:0]                   wr_data,
    input              [7:0]                    wr_strb,
    input                                       rd_valid,
    output                                      rd_ready,
    input              [ADDR_WIDTH-1:0]         rd_addr,
    output                                      rsp_valid,
    output             [63:0]                   rsp_data,
    output reg                                  error
);

assign wr_ready = !rd_valid;
assign rd_ready = !wr_valid;
wire wr_fire = wr_valid && wr_ready;
wire rd_fire = rd_valid && rd_ready;
opentitan_sram_1p_adapter #(
    .WIDTH                       (64),
    .DEPTH                       (DEPTH),
    .DATA_BITS_PER_MASK          (8)
) u_residual_sram (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .req_i                       (wr_fire || rd_fire),
    .write_i                     (wr_fire),
    .addr_i                      (wr_fire ? wr_addr : rd_addr),
    .wdata_i                     (wr_data),
    .wmask_i                     (wr_strb),
    .rdata_o                     (rsp_data),
    .rvalid_o                    (rsp_valid)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        error <= 1'b0;
    else if (wr_valid && rd_valid)
        error <= 1'b1;
end

endmodule
