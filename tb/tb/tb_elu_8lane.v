`timescale 1ns/1ps

//=============================================================================
// elu_8lane简单自检Testbench
// 验证内容：
//   1. 通过配置接口加载128项负半轴LUT；
//   2. 穷举全部-1~-128输入；
//   3. 穷举全部0~127正数旁路；
//   4. 验证elu_enable=0时64-bit数据完全旁路；
//   5. 验证out_ready=0时valid和data保持稳定。
//
// 示例LUT使用Sin=Sout=1/32、zero_point=0、alpha=1。
//=============================================================================
module tb_elu_8lane;

reg         clk;
reg         rst_n;
reg         cfg_valid;
wire        cfg_ready;
reg  [6:0]  cfg_addr;
reg  [7:0]  cfg_wdata;
reg         elu_enable;
reg         in_valid;
wire        in_ready;
reg  [63:0] in_data;
wire        out_valid;
reg         out_ready;
wire [63:0] out_data;

reg [7:0] expected_lut [0:127];
reg [63:0] test_vector;
reg [63:0] held_data;
integer i;
integer lane;
integer error_count;
integer vector_count;

elu_8lane u_dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .cfg_valid  (cfg_valid),
    .cfg_ready  (cfg_ready),
    .cfg_addr   (cfg_addr),
    .cfg_wdata  (cfg_wdata),
    .elu_enable (elu_enable),
    .relu_enable(1'b0),
    .in_valid   (in_valid),
    .in_ready   (in_ready),
    .in_data    (in_data),
    .out_valid  (out_valid),
    .out_ready  (out_ready),
    .out_data   (out_data)
);

always #5 clk = ~clk;

// 使用与DUT相同的地址约定，但期望值来自独立hex文件。
function [63:0] expected_result;
    input [63:0] input_vector;
    input        enable;
    integer      n;
    reg [7:0]    x;
    reg [63:0]   result;
    begin
        result = 64'd0;
        for (n = 0; n < 8; n = n + 1) begin
            x = input_vector[8*n +: 8];
            if (!enable)
                result[8*n +: 8] = x;
            else if (x[7])
                result[8*n +: 8] = expected_lut[~x[6:0]];
            else
                result[8*n +: 8] = x;
        end
        expected_result = result;
    end
endfunction

task load_lut;
    integer address;
    begin
        @(negedge clk);
        cfg_valid = 1'b1;
        for (address = 0; address < 128; address = address + 1) begin
            while (!cfg_ready)
                @(negedge clk);
            cfg_addr  = address[6:0];
            cfg_wdata = expected_lut[address];
            @(negedge clk);
        end
        cfg_valid = 1'b0;
        cfg_addr  = 7'd0;
        cfg_wdata = 8'd0;
    end
endtask

task send_and_check;
    input [63:0] vector_value;
    input        enable_value;
    reg [63:0]   expected_value;
    begin
        expected_value = expected_result(vector_value,enable_value);
        while (!in_ready)
            @(negedge clk);

        in_data    = vector_value;
        elu_enable = enable_value;
        in_valid   = 1'b1;
        @(negedge clk);
        in_valid   = 1'b0;

        while (!out_valid)
            @(negedge clk);

        vector_count = vector_count + 1;
        if (out_data !== expected_value) begin
            error_count = error_count + 1;
            $display(
                "[FAIL] vector=%0d enable=%0d input=%016h expected=%016h actual=%016h",
                vector_count,enable_value,vector_value,expected_value,out_data
            );
        end else begin
            $display(
                "[PASS] vector=%0d enable=%0d input=%016h output=%016h",
                vector_count,enable_value,vector_value,out_data
            );
        end
    end
endtask

task check_backpressure;
    reg [63:0] expected_value;
    begin
        test_vector = 64'h7f_20_01_00_80_c0_e0_ff;
        expected_value = expected_result(test_vector,1'b1);

        // 先让前一个普通测试响应完成，再人为拉低ready制造反压。
        while (out_valid)
            @(negedge clk);
        out_ready = 1'b0;
        while (!in_ready)
            @(negedge clk);
        in_data    = test_vector;
        elu_enable = 1'b1;
        in_valid   = 1'b1;
        @(negedge clk);
        in_valid   = 1'b0;

        while (!out_valid)
            @(negedge clk);
        held_data = out_data;

        repeat (4) begin
            @(posedge clk);
            #1;
            if (!out_valid || (out_data !== held_data)) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL][BACKPRESSURE] valid=%0d held=%016h actual=%016h",
                    out_valid,held_data,out_data
                );
            end
        end

        if (held_data !== expected_value) begin
            error_count = error_count + 1;
            $display(
                "[FAIL][BACKPRESSURE_DATA] expected=%016h actual=%016h",
                expected_value,held_data
            );
        end else begin
            $display("[PASS][BACKPRESSURE] output held for 4 clocks");
        end

        @(negedge clk);
        out_ready = 1'b1;
        @(negedge clk);
    end
endtask

initial begin
    clk          = 1'b0;
    rst_n        = 1'b0;
    cfg_valid    = 1'b0;
    cfg_addr     = 7'd0;
    cfg_wdata    = 8'd0;
    elu_enable   = 1'b0;
    in_valid     = 1'b0;
    in_data      = 64'd0;
    out_ready    = 1'b1;
    error_count  = 0;
    vector_count = 0;
    test_vector  = 64'd0;
    held_data    = 64'd0;

    $readmemh("tb/data/elu_lut_s1_32.hex",expected_lut);

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    load_lut;
    $display("[INFO] 128-entry ELU LUT loaded into all 8 lanes");

    // elu_enable=0：包括负数在内的所有数据必须原样旁路。
    send_and_check(64'h80_ff_e0_00_01_20_40_7f,1'b0);

    // 每个向量包含8个连续负数，覆盖-1~-128。
    for (i = 0; i < 128; i = i + 8) begin
        test_vector = 64'd0;
        for (lane = 0; lane < 8; lane = lane + 1)
            test_vector[8*lane +: 8] = -(i+lane+1);
        send_and_check(test_vector,1'b1);
    end

    // 覆盖全部非负INT8输入0~127，验证正半轴旁路。
    for (i = 0; i < 128; i = i + 8) begin
        test_vector = 64'd0;
        for (lane = 0; lane < 8; lane = lane + 1)
            test_vector[8*lane +: 8] = i+lane;
        send_and_check(test_vector,1'b1);
    end

    check_backpressure;

    if (error_count == 0)
        $display("[TB_PASS] elu_8lane: %0d vectors correct; backpressure correct",vector_count);
    else
        $display("[TB_FAIL] elu_8lane: errors=%0d",error_count);

    $finish;
end

endmodule
