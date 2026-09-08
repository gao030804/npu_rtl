`timescale 1ns/1ps

//=============================================================================
// Systolic_Array及其错拍/对齐包装器的定向测试。
//=============================================================================
module tb_Systolic_Array;

reg clk;
reg rst_n;
reg ce;
reg weight_load;
reg [255:0] weight_data;
reg act_valid;
reg [31:0] act_data;
reg [8:0] act_m_tag;
wire psum_valid;
wire [159:0] psum_data;
wire [8:0] psum_m_tag;

integer n;
integer expected;
integer actual;
integer error_count;
integer timeout_count;

mesh_core_4x8_systolic dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .ce          (ce),
    .weight_load (weight_load),
    .weight_data (weight_data),
    .act_valid   (act_valid),
    .act_data    (act_data),
    .act_m_tag   (act_m_tag),
    .psum_valid  (psum_valid),
    .psum_data   (psum_data),
    .psum_m_tag  (psum_m_tag)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    rst_n       = 1'b0;
    ce          = 1'b1;
    weight_load = 1'b0;
    weight_data = 256'd0;
    act_valid   = 1'b0;
    act_data    = 32'd0;
    act_m_tag   = 9'd0;
    error_count = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // 第n列权重设置为{n+1,n+2,n+3,n+4}。
    for (n = 0; n < 8; n = n + 1) begin
        weight_data[8*(0*8+n) +: 8] = n + 1;
        weight_data[8*(1*8+n) +: 8] = n + 2;
        weight_data[8*(2*8+n) +: 8] = n + 3;
        weight_data[8*(3*8+n) +: 8] = n + 4;
    end

    weight_load = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_load = 1'b0;

    // 激活向量{1,-2,3,-4}，tag=9。
    act_data  = {-8'sd4, 8'sd3, -8'sd2, 8'sd1};
    act_m_tag = 9'd9;
    act_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    act_valid = 1'b0;
    act_data  = 32'd0;

    timeout_count = 0;
    while (!psum_valid && timeout_count < 100) begin
        @(negedge clk);
        timeout_count = timeout_count + 1;
    end

    if (!psum_valid) begin
        $display("[ERROR] Systolic_Array timeout");
        error_count = error_count + 1;
    end else begin
        if (psum_m_tag !== 9'd9) begin
            $display("[ERROR] tag expected=9 actual=%0d", psum_m_tag);
            error_count = error_count + 1;
        end

        for (n = 0; n < 8; n = n + 1) begin
            expected = 1*(n+1) + (-2)*(n+2)
                     + 3*(n+3) + (-4)*(n+4);
            actual = $signed(psum_data[20*n +: 20]);
            if (actual !== expected) begin
                $display(
                    "[ERROR] lane=%0d expected=%0d actual=%0d",
                    n, expected, actual
                );
                error_count = error_count + 1;
            end
        end
    end

    if (error_count == 0)
        $display("[TB_PASS] tb_Systolic_Array");
    else
        $display("[TB_FAIL] tb_Systolic_Array errors=%0d", error_count);

    $finish;
end

endmodule
