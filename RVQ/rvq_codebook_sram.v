// ============================================================================
// 中文阅读导引（当前实现）
// 码本存储16384×64 bit=128 KiB，word包含8个INT8。写入端口由外部配置/DMA提供。
// 模型采用同步读，rd_rsp_valid标记返回数据；没有响应ready，核心必须按固定返回节拍消费。
// ============================================================================
`timescale 1ns/1ps

//=============================================================================
// 模块：rvq_codebook_sram
// 功能：RVQ码本存储器的可综合行为级描述。
//
// 默认组织：
//   8级 × 256个码字 × (64维 / 每字8维) = 16384 × 64 bit = 128 KiB
//
// 地址格式：
//   addr[13:11] = RVQ stage
//   addr[10:3]  = codeword index
//   addr[2:0]   = 8维分组编号
//
// 说明：
//   - 写端口用于上电/DMA装载INT8码本；
//   - 读端口为同步读，固定1周期响应；
//   - 综合时可映射为FPGA Block RAM或替换为ASIC SRAM Macro。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 码本组织为8 stage x 256 codeword x 8 dimension-group，每个word保存8个INT8维度。
// - 14-bit地址映射为{stage[2:0],index[7:0],dimension_group[2:0]}，总容量128 KiB。
// - 写口用于启动前加载码本，读口为同步读并用rd_rsp_valid标记返回拍。
// -------------------------------------------------------------------------
module rvq_codebook_sram #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 16384
) (
    input                                       clk,
    input                                       rst_n,
    input                                       wr_valid,
    output                                      wr_ready,
    input              [ADDR_WIDTH-1:0]         wr_addr,
    input              [DATA_WIDTH-1:0]         wr_data,
    input                                       rd_valid,
    output                                      rd_ready,
    input              [ADDR_WIDTH-1:0]         rd_addr,
    output reg                                  rd_rsp_valid,
    output reg         [DATA_WIDTH-1:0]         rd_rsp_data
);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// 1R1W模型每周期可接收一次写和一次读。
assign wr_ready = 1'b1;
assign rd_ready = 1'b1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_rsp_valid <= 1'b0;
        rd_rsp_data  <= {DATA_WIDTH{1'b0}};
    end else begin
        rd_rsp_valid <= rd_valid && rd_ready;
        if (wr_valid && wr_ready)
            mem[wr_addr] <= wr_data;
        if (rd_valid && rd_ready)
            rd_rsp_data <= mem[rd_addr];
    end
end

endmodule
