// ============================================================================
// 中文阅读导引（当前实现）
// 计算8维残差与已对齐码字的平方距离。减法必须保留符号扩展后的宽度。
// 8维结果尚不是完整64维距离，核心继续累加8组后才执行最小距离比较。
// ============================================================================
`timescale 1ns/1ps

//=============================================================================
// 模块：rvq_distance_8lane
// 功能：计算8维平方欧氏距离的部分和。
//
//   group_distance = sum((residual[i] - codeword[i])^2), i=0..7
//
// 注意：INT16-INT16理论上需要17位，因此差值先扩展到signed 17 bit；
// 平方结果为34 bit，8项相加输出35 bit。RVQ Core再将总距离饱和为UINT32。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 每拍计算8维(residual-codebook)^2之和；差值先扩展到INT17，再平方并累加。
// - rvq_core把8个dimension-group的结果累计成一个64维码字的UINT32距离。
// -------------------------------------------------------------------------
module rvq_distance_8lane (
    input              [127:0]                  residual_data,
    input              [127:0]                  codeword_data,
    output reg         [34:0]                   group_distance
);

integer lane;
reg signed [16:0] residual_ext;
reg signed [16:0] codeword_ext;
reg signed [16:0] difference;
reg signed [33:0] square_signed;
reg        [33:0] square_value;

// 纯组合距离单元：输入变化后重新计算8维部分距离，不保存跨拍状态。
// 64维完整距离由rvq_core在8个dimension group之间继续累加。
always @(*) begin
    group_distance = 35'd0;
    residual_ext = 17'sd0;
    codeword_ext = 17'sd0;
    difference = 17'sd0;
    square_signed = 34'sd0;
    square_value = 34'd0;
    for (lane = 0; lane < 8; lane = lane + 1) begin
        // 每个lane从128-bit总线中取一个signed INT16残差和码本值。
        residual_ext = $signed({residual_data[16*lane+15],
            residual_data[16*lane +: 16]});
        codeword_ext = $signed({codeword_data[16*lane+15],
            codeword_data[16*lane +: 16]});
        // INT16-INT16的范围需要17-bit；平方结果最大需要34-bit。
        difference = residual_ext - codeword_ext;
        square_signed = difference * difference;
        square_value = square_signed[33:0];
        group_distance = group_distance + {1'b0,square_value};
    end
end

endmodule
