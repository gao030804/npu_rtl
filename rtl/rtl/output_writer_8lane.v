// ============================================================================
// 中文阅读导引（当前实现）
// 将8个量化输出映射到时间位置m及输出通道组对应的Byte地址。
// 写数据64 bit，字节使能8 bit；尾组不足8通道时禁止写入无效通道。
// 只有out_wr_valid和out_wr_ready共同有效时，外部存储才接受本次写入。
// ============================================================================
//=============================================================================
// 模块：output_writer_8lane
// 功能：在后处理与 Output SRAM 之间加入一个弹性写寄存器。
//
// 当 out_wr_valid=1、out_wr_ready=0 时，地址、数据和 byte strobe 必须
// 保持不变。若旧数据本周期被 SRAM 接受，可以同周期装入下一笔新数据。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 将地址、64-bit数据和8-bit字节使能注册后送往Activation SRAM写端口。
// - out_wr_valid等待out_wr_ready期间保持，只有真实握手后才能接收下一组结果。
// -------------------------------------------------------------------------
module output_writer_8lane #(
    parameter ADDR_WIDTH = 32
) (
    input                                       clk,
    input                                       rst_n,
    input                                       in_valid,
    output                                      in_ready,
    input              [ADDR_WIDTH-1:0]         in_addr,
    input              [63:0]                   in_data,
    input              [7:0]                    in_strb,
    output reg                                  out_wr_valid,
    input                                       out_wr_ready,
    output reg         [ADDR_WIDTH-1:0]         out_wr_addr,
    output reg         [63:0]                   out_wr_data,
    output reg         [7:0]                    out_wr_strb
);

assign in_ready = !out_wr_valid || out_wr_ready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_wr_valid <= 1'b0;
        out_wr_addr  <= {ADDR_WIDTH{1'b0}};
        out_wr_data  <= 64'd0;
        out_wr_strb  <= 8'd0;
    end else if (in_ready) begin

        // 只有寄存器为空或旧事务握手完成时，才允许更新输出寄存器。
        out_wr_valid <= in_valid;
        if (in_valid) begin
            out_wr_addr <= in_addr;
            out_wr_data <= in_data;
            out_wr_strb <= in_strb;
        end
    end
end

endmodule
