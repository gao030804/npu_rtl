// ============================================================================
// 中文阅读导引（当前实现）
// 码本存储5120×64 bit=40 KiB，word包含8个INT8。写入端口由外部配置/DMA提供。
// 模型采用同步读，rd_rsp_valid标记返回数据；没有响应ready，核心必须按固定返回节拍消费。
// ============================================================================
`timescale 1ns/1ps

//=============================================================================
// 模块：rvq_codebook_sram
// 功能：RVQ码本存储器的可综合行为级描述。
//
// 默认组织：
//   q0:256×4 words；q1~q8:128×4 words，共5120×64 bit=40 KiB。
//
// 地址格式：
//   q0 base=0；qN base=1024+(N-1)*512；addr=base+index*4+dimension_group。
//
// 说明：
//   - 写端口用于上电/DMA装载INT8码本；
//   - 读端口为同步读，固定1周期响应；
//   - 综合时可映射为FPGA Block RAM或替换为ASIC SRAM Macro。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 码本组织为9 stage、32D；q0=K256，q1~q8=K128，每word保存8个INT8维度。
// - 14-bit外部地址保留不变，内部只使用0~5119紧凑空间。
// - 写口用于启动前加载码本，读口为同步读并用rd_rsp_valid标记返回拍。
// -------------------------------------------------------------------------
// [中文注释-自动补充]
// 模块作用：RVQ码本SRAM。
// 关键变量/接口：组织为K256+8xK128、4 group，每word含8个INT8维度，共40KiB。
// 握手约定：valid与ready在同一上升沿同时为1才完成一次传输；反压期间数据必须保持。
// 位宽约定：地址通常按Byte计，Weight块为256 bit，Activation/Weight基本元素为signed INT8。
// -----------------------------------------------------------------------------
module rvq_codebook_sram #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 5120
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
// 连续赋值：组合生成wr_ready及其相邻接口信号，表达握手、选择或地址关系。
assign wr_ready = 1'b1;
assign rd_ready = 1'b1;

// 时序逻辑：在时钟沿更新rd_rsp_valid、rd_rsp_data；复位分支负责恢复确定的空闲状态。
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
