`timescale 1ns/1ps

//=============================================================================
// 16-bit DDR接收流到256-bit Weight块组包器。
//
// PHY每个系统周期交付两个连续字节：in_data[7:0]为低地址字节，
// in_data[15:8]为下一字节。连续16拍组成一个256-bit SRAM写入块。
// valid/ready允许DMA在256-bit边界处向上游施加反压。
//=============================================================================

// [中文注释-自动补充]
// 模块作用：16-bit到256-bit权重打包器。
// 关键变量/接口：连续收集16个16-bit beat组成一个权重块；last与error随最后一块传递。
// 握手约定：valid与ready在同一上升沿同时为1才完成一次传输；反压期间数据必须保持。
// 位宽约定：地址通常按Byte计，Weight块为256 bit，Activation/Weight基本元素为signed INT8。
// -----------------------------------------------------------------------------
module octal_ddr_16to256_packer (
    input                                       clk,
    input                                       rst_n,
    input                                       clear,
    input                                       in_valid,
    output                                      in_ready,
    input              [15:0]                   in_data,
    input                                       in_last,
    input                                       in_error,
    output reg                                  out_valid,
    input                                       out_ready,
    output reg         [255:0]                  out_data,
    output reg                                  out_last,
    output reg                                  out_error
);

reg [239:0] lower_words;
reg [3:0]   word_index;

// 仅在上一块已被接受或输出寄存器为空时接收新数据。
// 连续赋值：组合生成in_ready及其相邻接口信号，表达握手、选择或地址关系。
assign in_ready = !out_valid || out_ready;

// 时序逻辑：在时钟沿更新lower_words、word_index、out_valid、out_data、out_last、out_error；复位分支负责恢复确定的空闲状态。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lower_words <= 240'd0;
        word_index  <= 4'd0;
        out_valid   <= 1'b0;
        out_data    <= 256'd0;
        out_last    <= 1'b0;
        out_error   <= 1'b0;
    end else if (clear) begin
        lower_words <= 240'd0;
        word_index  <= 4'd0;
        out_valid   <= 1'b0;
        out_last    <= 1'b0;
        out_error   <= 1'b0;
    end else begin
        if (out_valid && out_ready)
            out_valid <= 1'b0;
        if (in_valid && in_ready) begin
            if (word_index == 4'd15) begin
                out_data  <= {in_data, lower_words};
                out_valid <= 1'b1;
                out_last  <= in_last;
                out_error <= in_error;
                word_index <= 4'd0;
            end else begin
                lower_words[word_index*16 +: 16] <= in_data;
                word_index <= word_index + 1'b1;

                // 权重命令长度固定为32 Byte整数倍；提前last属于协议错误。
                if (in_last) begin
                    out_error <= 1'b1;
                    out_last  <= 1'b1;
                end
                if (in_error)
                    out_error <= 1'b1;
            end
        end
    end
end

endmodule
