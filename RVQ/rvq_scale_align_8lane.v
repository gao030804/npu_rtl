// ============================================================================
// 中文阅读导引（当前实现）
// 将INT8码字乘以每级Multiplier并舍入右移，饱和为INT16，与共同Residual Scale对齐。
// Multiplier/Shift来自训练导出；缩放溢出通过overflow返回核心。
// ============================================================================
`timescale 1ns/1ps

//=============================================================================
// 模块：rvq_scale_align_8lane
// 功能：将8路INT8码本元素转换到统一的INT16 Residual数值域。
//
// 定点公式：
//   codeword_aligned = sat16(round_away_from_zero(
//                            codeword_int8 * multiplier / 2^shift))
//
// multiplier/2^shift近似该级 S_codebook / S_residual。
// 每个RVQ stage使用一组multiplier和shift，8个维度共享该级参数。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 对8个INT8码本值分别执行multiplier/shift定点缩放，使其与当前Residual Scale一致。
// - 使用64-bit乘法与对称舍入，输出INT16中间值，避免缩放后立即压回INT8造成额外误差。
// -------------------------------------------------------------------------
module rvq_scale_align_8lane (
    input              [63:0]                   codebook_data,
    input              [31:0]                   multiplier,
    input              [5:0]                    shift,
    output reg         [127:0]                  aligned_data,
    output reg                                  overflow
);

integer lane;
reg [16:0] lane_result;

// 返回值[16]为饱和标志，[15:0]为signed INT16结果。

function [16:0] align_one;
    input              [7:0]                    code_value;
    input              [31:0]                   mult_value;
    input              [5:0]                    shift_value;
    reg signed [7:0]  code_s;
    reg signed [32:0] mult_s;
    reg signed [40:0] product;
    reg signed [40:0] magnitude;
    reg signed [40:0] round_bias;
    reg signed [40:0] shifted;
    begin
        code_s = $signed(code_value);

        // 前补0，确保32-bit multiplier始终按非负数解释。
        mult_s = $signed({1'b0,mult_value});
        product = code_s * mult_s;
        magnitude = 41'sd0;
        round_bias = 41'sd0;
        shifted = 41'sd0;
        if (shift_value == 0) begin
            shifted = product;
        end else if (shift_value <= 40) begin
            round_bias = 41'sd1 <<< (shift_value - 1'b1);
            if (product < 0) begin
                magnitude = -product;
                shifted = -((magnitude + round_bias) >>> shift_value);
            end else begin
                shifted = (product + round_bias) >>> shift_value;
            end
        end else begin

            // 乘积只有41位，右移超过40位后按0处理。
            shifted = 41'sd0;
        end
        if (shifted > 41'sd32767)
            align_one = {1'b1,16'h7fff};
        else if (shifted < -41'sd32768)
            align_one = {1'b1,16'h8000};
        else
        align_one = {1'b0,shifted[15:0]};
    end
endfunction

always @(*) begin
    aligned_data = 128'd0;
    overflow = 1'b0;
    lane_result = 17'd0;
    for (lane = 0; lane < 8; lane = lane + 1) begin
        lane_result = align_one(
            codebook_data[8*lane +: 8],
            multiplier,
            shift
        );

        aligned_data[16*lane +: 16] = lane_result[15:0];
        overflow = overflow | lane_result[16];
    end
end

endmodule
