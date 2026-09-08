`timescale 1ns/1ps
//=============================================================================
// PCM16 -> INT8 量化器单元测试
//=============================================================================
module tb_pcm16_to_int8_quantizer;

reg clk;
reg rst_n;
reg in_valid;
wire in_ready;
reg signed [15:0] in_pcm;
reg in_last;
reg signed [31:0] cfg_multiplier;
reg [5:0] cfg_shift;
reg signed [7:0] cfg_zero_point;
wire out_valid;
reg out_ready;
wire signed [7:0] out_data;
wire out_last;
integer errors;
integer held_value;

pcm16_to_int8_quantizer dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .in_valid       (in_valid),
    .in_ready       (in_ready),
    .in_pcm         (in_pcm),
    .in_last        (in_last),
    .cfg_multiplier (cfg_multiplier),
    .cfg_shift      (cfg_shift),
    .cfg_zero_point (cfg_zero_point),
    .out_valid      (out_valid),
    .out_ready      (out_ready),
    .out_data       (out_data),
    .out_last       (out_last)
);

initial clk = 1'b0;
always #5 clk = ~clk;

task check_sample;
    input integer pcm_value;
    input integer expected_value;
    begin
        @(negedge clk);
        in_pcm   = pcm_value;
        in_valid = 1'b1;
        while (!in_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        in_valid = 1'b0;

        if (!out_valid || ($signed(out_data) !== expected_value)) begin
            $display(
                "[FAIL] pcm=%0d mult=%0d shift=%0d zp=%0d expected=%0d actual=%0d valid=%0b",
                pcm_value,cfg_multiplier,cfg_shift,cfg_zero_point,
                expected_value,$signed(out_data),out_valid
            );
            errors = errors + 1;
        end else begin
            $display(
                "[PASS] pcm=%0d mult=%0d shift=%0d zp=%0d result=%0d",
                pcm_value,cfg_multiplier,cfg_shift,cfg_zero_point,
                $signed(out_data)
            );
        end
        @(posedge clk);
    end
endtask

initial begin
    rst_n           = 1'b0;
    in_valid        = 1'b0;
    in_pcm          = 16'sd0;
    in_last         = 1'b0;
    out_ready       = 1'b1;
    cfg_multiplier  = 32'sd1;
    cfg_shift       = 6'd8;
    cfg_zero_point  = 8'sd0;
    errors          = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // 满幅映射、正负半步舍入以及饱和边界。
    check_sample(-32768,-128);
    check_sample(-32767,-128);
    check_sample(-257,-1);
    check_sample(-256,-1);
    check_sample(-255,-1);
    check_sample(-128,-1);
    check_sample(-127,0);
    check_sample(0,0);
    check_sample(127,0);
    check_sample(128,1);
    check_sample(255,1);
    check_sample(256,1);
    check_sample(32512,127);
    check_sample(32767,127);

    // 检查可配置 multiplier 和 zero point。
    cfg_multiplier = 32'sd2;
    cfg_shift      = 6'd8;
    cfg_zero_point = 8'sd5;
    check_sample(256,7);

    // 反压：out_ready=0 时 valid/data/last 必须保持。
    cfg_multiplier = 32'sd1;
    cfg_shift      = 6'd8;
    cfg_zero_point = 8'sd0;
    out_ready      = 1'b0;
    in_last        = 1'b1;
    @(negedge clk);
    in_pcm          = 16'sd1024;
    in_valid        = 1'b1;
    @(posedge clk);
    @(negedge clk);
    in_valid        = 1'b0;
    held_value      = $signed(out_data);
    repeat (3) begin
        @(posedge clk);
        @(negedge clk);
        if (!out_valid || ($signed(out_data) !== held_value) || !out_last) begin
            $display("[FAIL] output changed under backpressure");
            errors = errors + 1;
        end
    end
    if (held_value !== 4) begin
        $display("[FAIL] backpressure sample expected=4 actual=%0d",held_value);
        errors = errors + 1;
    end
    out_ready = 1'b1;
    @(posedge clk);

    if (errors == 0)
        $display("[TB_PASS] PCM16 to INT8 quantizer");
    else
        $display("[TB_FAIL] PCM16 to INT8 quantizer errors=%0d",errors);
    $finish;
end

endmodule
