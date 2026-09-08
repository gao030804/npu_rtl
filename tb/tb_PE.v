`timescale 1ns/1ps

//=============================================================================
// Testbench：PE
//
// 验证内容：
//   1. 低有效异步复位会清零 XOUT 和 PEOUT；
//   2. 每个时钟上升沿执行：XOUT <= XIN；
//   3. 每个时钟上升沿执行：PEOUT <= PEIN + XIN * W；
//   4. 正数和负数均按照二进制补码有符号数计算。
//=============================================================================
module tb_PE;

localparam DATA_WIDTH = 8;

reg                              CLK;
reg                              RSTn;
reg                              CE;
reg  signed [DATA_WIDTH-1:0]     W;
reg  signed [DATA_WIDTH-1:0]     XIN;
reg  signed [2*DATA_WIDTH-1:0]   PEIN;
wire signed [DATA_WIDTH-1:0]     XOUT;
wire signed [2*DATA_WIDTH-1:0]   PEOUT;

integer error_count;

PE #(
    .DATA_WIDTH (DATA_WIDTH),
    .ACC_WIDTH  (2*DATA_WIDTH)
) dut (
    .CLK   (CLK),
    .RSTn  (RSTn),
    .CE    (CE),
    .W     (W),
    .XIN   (XIN),
    .PEIN  (PEIN),
    .XOUT  (XOUT),
    .PEOUT (PEOUT)
);

// 100 MHz时钟：周期10 ns。
initial CLK = 1'b0;
always #5 CLK = ~CLK;

// 在时钟下降沿改变输入，保证下一个上升沿前输入已经稳定。
task apply_and_check;
    input integer x_value;
    input integer w_value;
    input integer pein_value;
    integer expected_sum;
    begin
        @(negedge CLK);
        XIN = x_value;
        W    = w_value;
        PEIN = pein_value;
        expected_sum = pein_value + x_value * w_value;

        @(posedge CLK);
        #1;

        if ($signed(XOUT) != x_value) begin
            $display("[ERROR] XOUT: expected=%0d, actual=%0d",
                     x_value, $signed(XOUT));
            error_count = error_count + 1;
        end

        if ($signed(PEOUT) != expected_sum) begin
            $display("[ERROR] PEOUT: %0d + %0d * %0d = %0d, actual=%0d",
                     pein_value, x_value, w_value, expected_sum,
                     $signed(PEOUT));
            error_count = error_count + 1;
        end else begin
            $display("[PASS ] PEIN=%0d, XIN=%0d, W=%0d -> PEOUT=%0d",
                     pein_value, x_value, w_value, $signed(PEOUT));
        end
    end
endtask

initial begin
`ifdef DUMP_VCD
    $dumpfile("tb_PE.vcd");
    $dumpvars(0, tb_PE);
`endif

    error_count = 0;
    RSTn = 1'b0;
    CE   = 1'b1;
    W    = 0;
    XIN  = 0;
    PEIN = 0;

    // 异步复位不需要等待时钟沿。
    #2;
    if ((XOUT !== 0) || (PEOUT !== 0)) begin
        $display("[ERROR] Reset failed: XOUT=%0d, PEOUT=%0d",
                 $signed(XOUT), $signed(PEOUT));
        error_count = error_count + 1;
    end

    // 在下降沿释放复位，避开时钟上升沿附近的竞争。
    @(negedge CLK);
    RSTn = 1'b1;

    apply_and_check(  3,  4,  5);  // 5 + 3*4   = 17
    apply_and_check( -4,  3,  7);  // 7 + (-4)*3 = -5
    apply_and_check(  5, -6,-10);  // -10 + 5*(-6) = -40
    apply_and_check( -7, -2,  1);  // 1 + (-7)*(-2) = 15

    // 再次验证运行过程中的异步复位。
    #2 RSTn = 1'b0;
    #1;
    if ((XOUT !== 0) || (PEOUT !== 0)) begin
        $display("[ERROR] Mid-run reset failed");
        error_count = error_count + 1;
    end

    if (error_count == 0)
        $display("[TB_PASS] tb_PE completed successfully.");
    else
        $display("[TB_FAIL] tb_PE found %0d error(s).", error_count);

    #10;
    $finish;
end

endmodule
