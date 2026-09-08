`timescale 1ns/1ps

// P25Q32H + QSPI控制器联合测试：验证50 MHz时钟、连续CS和字节顺序。
module tb_qspi_weight_boot_loader;

reg clk;
reg rst_n;
reg cmd_valid;
wire cmd_ready;
wire block_valid;
reg block_ready;
wire [15:0] block_index;
wire [255:0] block_data;
wire done;
wire busy;
wire error;
wire flash_csn;
wire flash_sclk;
tri [3:0] flash_dq;

integer errors;
integer received_blocks;
integer cs_fall_count;
integer i;
reg [255:0] expected;

qspi_weight_boot_loader #(
    .QSPI_HALF_DIV       (16'd1),
    .POWER_UP_CYCLES     (32'd20),
    .QSPI_DUMMY_CYCLES   (8),
    .CS_HIGH_CYCLES      (3),
    .TIMEOUT_CYCLES      (32'd100000)
) dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .cmd_valid           (cmd_valid),
    .cmd_ready           (cmd_ready),
    .cmd_flash_base      (24'h000000),
    .cmd_block_count     (16'd2),
    .block_valid         (block_valid),
    .block_ready         (block_ready),
    .block_index         (block_index),
    .block_data          (block_data),
    .done                (done),
    .busy                (busy),
    .error               (error),
    .flash_csn           (flash_csn),
    .flash_sclk          (flash_sclk),
    .flash_dq            (flash_dq)
);

P25Q32H #(
    .Init_File           ("tb/data/flash/MEM.TXT")
) u_flash (
    .SCLK                (flash_sclk),
    .CSb                 (flash_csn),
    .SI                  (flash_dq[0]),
    .SO                  (flash_dq[1]),
    .WPb                 (flash_dq[2]),
    .SIO3                (flash_dq[3])
);

initial clk = 1'b0;
always #5 clk = ~clk;

always @(negedge flash_csn)
    cs_fall_count = cs_fall_count + 1;

always @(posedge clk) begin
    if (block_valid && block_ready) begin
        expected = 256'd0;
        for (i = 0; i < 32; i = i + 1)
            expected[8*i +: 8] = block_index * 32 + i;
        if (block_data !== expected) begin
            $display("[ERROR] block=%0d expected=%064h actual=%064h",
                     block_index, expected, block_data);
            errors = errors + 1;
        end
        received_blocks = received_blocks + 1;
    end
end

initial begin
    rst_n           = 1'b0;
    cmd_valid       = 1'b0;
    block_ready     = 1'b1;
    errors          = 0;
    received_blocks = 0;
    cs_fall_count   = 0;
    #100;
    rst_n = 1'b1;
    wait (cmd_ready);
    @(negedge clk);
    cmd_valid = 1'b1;
    @(negedge clk);
    cmd_valid = 1'b0;
    wait (done || error);
    repeat (4) @(posedge clk);
    if (error) begin
        $display("[ERROR] DUT timeout/protocol error");
        errors = errors + 1;
    end
    if (received_blocks != 2) begin
        $display("[ERROR] expected 2 blocks, received %0d", received_blocks);
        errors = errors + 1;
    end
    // 50h、31h和一次6Bh burst，共三个CS下降沿；数据块之间CS不能抬高。
    if (cs_fall_count != 3) begin
        $display("[ERROR] expected CS transaction count=3 actual=%0d", cs_fall_count);
        errors = errors + 1;
    end
    if (errors == 0)
        $display("[TB_PASS] P25Q32H QSPI 50MHz continuous burst passed");
    else
        $display("[TB_FAIL] errors=%0d", errors);
    $finish;
end

initial begin
    #500000;
    $display("[TB_FAIL] global timeout");
    $finish;
end

endmodule
