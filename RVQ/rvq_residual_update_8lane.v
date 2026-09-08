// ============================================================================
// 中文阅读导引（当前实现）
// 对选中的码字执行8路INT16残差减法并饱和。
// 每级更新全部8组后进入下一级搜索，不能在同一级搜索中提前修改Residual。
// ============================================================================
`timescale 1ns/1ps

//=============================================================================
// 模块：rvq_residual_update_8lane
// 功能：用选中码字更新8维Residual，并对结果执行INT16饱和。
//
//   residual_next = sat16(residual - selected_codeword_aligned)
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 执行8路INT16 residual-codebook差值，再根据Residual量化规则饱和回signed INT8。
// - 每次更新一个dimension-group，8次握手后完成当前stage全部64维Residual更新。
// -------------------------------------------------------------------------
module rvq_residual_update_8lane (
    input              [127:0]                  residual_data,
    input              [127:0]                  codeword_data,
    output reg         [127:0]                  residual_next,
    output reg                                  overflow
);

integer lane;
reg signed [16:0] residual_ext;
reg signed [16:0] codeword_ext;
reg signed [16:0] subtract_result;

always @(*) begin
    residual_next = 128'd0;
    overflow = 1'b0;
    residual_ext = 17'sd0;
    codeword_ext = 17'sd0;
    subtract_result = 17'sd0;
    for (lane = 0; lane < 8; lane = lane + 1) begin
        residual_ext = $signed({residual_data[16*lane+15],
            residual_data[16*lane +: 16]});
        codeword_ext = $signed({codeword_data[16*lane+15],
            codeword_data[16*lane +: 16]});
        subtract_result = residual_ext - codeword_ext;
        if (subtract_result > 17'sd32767) begin
            residual_next[16*lane +: 16] = 16'h7fff;
            overflow = 1'b1;
        end else if (subtract_result < -17'sd32768) begin
            residual_next[16*lane +: 16] = 16'h8000;
            overflow = 1'b1;
        end else begin
            residual_next[16*lane +: 16] = subtract_result[15:0];
        end
    end
end

endmodule
