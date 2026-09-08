// ============================================================================
// 中文阅读导引（当前实现）
// 权重地址单位为Byte，一个4×8 INT8块占32 Byte。
// 地址按输出通道组和规约组定位，通道尾部与K尾部需要由打包或消费端掩码处理。
// ============================================================================
//=============================================================================
// 模块名称：conv1d_weight_agu
// 功能：为当前output_group和k_group生成32 Byte权重块的字节地址。
//
// 权重块排列：
//   [output_group][k_group][4个K lane][8个输出lane]
//
// 每块大小：4 × 8 × INT8 = 32 Byte，因此：
//   addr = weight_base + (output_group*k_groups+k_group)*32
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 权重Byte地址为weight_base+(output_group*k_groups+k_group)*32。
// - 每个地址对应一个4x8 INT8块；输出通道尾组和reduction尾组由上层mask处理。
// -------------------------------------------------------------------------
module conv1d_weight_agu #(
    parameter ADDR_WIDTH = 32
) (
    input              [ADDR_WIDTH-1:0]         weight_base,
    input              [5:0]                    output_group,
    input              [9:0]                    k_group,
    input              [9:0]                    k_groups,
    output             [ADDR_WIDTH-1:0]         weight_addr
);

// 先把不同宽度的计数器零扩展到32-bit，避免表达式宽度被左操作数截断。
wire [31:0] output_group_ext = {{26{1'b0}}, output_group};
wire [31:0] k_group_ext      = {{22{1'b0}}, k_group};
wire [31:0] k_groups_ext     = {{22{1'b0}}, k_groups};
// 线性块编号：先排列一个output group的全部k_group，再进入下一个output group。
wire [31:0] block_index      = output_group_ext * k_groups_ext
    + k_group_ext;

// 左移5位等价于乘32，将256-bit块编号转换成Byte地址。
assign weight_addr = weight_base + (block_index << 5);
endmodule
