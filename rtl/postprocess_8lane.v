// ============================================================================
// 中文阅读导引（当前实现）
// 逐输出通道使用独立Bias、Multiplier、Shift和Zero Point。
// 运算顺序：INT32累加值加Bias并饱和 → INT64乘法 → 舍入/右移 → 加Zero Point → INT8饱和。
// in_ready=!post_valid||post_ready允许旧输出取走时同拍接收新输入。
// 当前算术主要在组合逻辑内完成，输出寄存器可连续接收，但不等同于乘法器内部多级流水。
// ============================================================================
//=============================================================================
// 模块：postprocess_8lane
// 功能：对 8 路 INT32 卷积累加值进行逐输出通道重新量化。
//
// 每一路的数据路径：
//   INT32 accumulator + INT32 bias（带饱和）
//   -> INT32 × INT32 = INT64
//   -> 对称舍入并算术右移
//   -> 加 signed INT8 zero_point
//   -> 显式饱和到 signed INT8
//
// valid/ready 规则：post_valid=1 且 post_ready=0 时，输出保持不变。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 每个输出lane独立使用bias、multiplier、shift和zero_point，支持per-Cout量化参数。
// - 计算链为INT32加Bias、INT64乘法、half-away-from-zero舍入、右移和INT8饱和。
// - post_valid被反压时post_data保持不变；不能在ready=0时覆盖正在等待的数据。
// -------------------------------------------------------------------------
module postprocess_8lane (
    input                                       clk,
    input                                       rst_n,
    input                                       in_valid,
    output                                      in_ready,
    input              [255:0]                  acc_data,
    input              [255:0]                  bias_data,
    input              [255:0]                  mult_data,
    input              [47:0]                   shift_data,
    input              [63:0]                   zero_point_data,
    output reg                                  post_valid,
    input                                       post_ready,
    output reg         [63:0]                   post_data
);

integer n;
reg signed [31:0] av;
reg signed [31:0] bv;
reg signed [31:0] mv;
reg signed [7:0]  zv;
reg        [5:0]  sv;
reg signed [31:0] biased;
reg signed [63:0] bias_sum;
reg signed [63:0] biased_ext;
reg signed [63:0] mult_ext;
reg signed [63:0] scaled;
reg signed [63:0] rounded;
reg signed [63:0] magnitude;
reg signed [63:0] shifted;
reg signed [63:0] requantized;
reg signed [7:0]  sat;
reg        [63:0] calc;
assign in_ready = !post_valid || post_ready;

always @(*) begin
    calc        = 64'd0;
    av          = 32'sd0;
    bv          = 32'sd0;
    mv          = 32'sd0;
    zv          = 8'sd0;
    sv          = 6'd0;
    biased      = 32'sd0;
    bias_sum    = 64'sd0;
    biased_ext  = 64'sd0;
    mult_ext    = 64'sd0;
    scaled      = 64'sd0;
    rounded     = 64'sd0;
    magnitude   = 64'sd0;
    shifted     = 64'sd0;
    requantized = 64'sd0;
    sat         = 8'sd0;
    for (n = 0; n < 8; n = n + 1) begin

        // lane n 对应一个输出通道，四种量化参数均按 lane 独立配置。
        av = acc_data[32*n +: 32];
        bv = bias_data[32*n +: 32];
        mv = mult_data[32*n +: 32];
        sv = shift_data[6*n +: 6];
        zv = zero_point_data[8*n +: 8];

        // 在 64 bit 中先做加法，再饱和回 INT32，避免 acc+bias 回绕。
        bias_sum = {{32{av[31]}}, av} + {{32{bv[31]}}, bv};
        if (bias_sum > 64'sd2147483647) begin
            biased = 32'sh7fff_ffff;
        end else if (bias_sum < -64'sd2147483648) begin
            biased = 32'sh8000_0000;
        end else begin
            biased = bias_sum[31:0];
        end
        biased_ext = {{32{biased[31]}}, biased};
        mult_ext   = {{32{mv[31]}}, mv};
        scaled     = $signed(biased_ext) * $signed(mult_ext);

        // 对负数也从绝对值方向舍入。
        // 例如 -4/2 必须仍为 -2，旧式 (scaled-half)>>>shift 会得到 -3。
        if (sv == 0) begin
            shifted = scaled;
        end else if (scaled >= 0) begin
            rounded = scaled + (64'sd1 << (sv - 1'b1));
            shifted = rounded >>> sv;
        end else begin
            magnitude = -scaled;
            rounded   = magnitude + (64'sd1 << (sv - 1'b1));
            shifted   = -(rounded >>> sv);
        end

        // 对称量化时 zero_point 配置为 0；非对称量化可逐通道配置。
        requantized = shifted + {{56{zv[7]}}, zv};
        if (requantized > 64'sd127) begin
            sat = 8'sd127;
        end else if (requantized < -64'sd128) begin
            sat = -8'sd128;
        end else begin
            sat = requantized[7:0];
        end
        calc[8*n +: 8] = sat;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        post_valid <= 1'b0;
        post_data  <= 64'd0;
    end else if (in_ready) begin
        post_valid <= in_valid;
        if (in_valid) begin
            post_data <= calc;
        end
    end
end

endmodule
