`timescale 1ns/1ns

//=============================================================================
// flash_weight_reader模块级测试：
//   Flash地址0x000100预置00～1f，共32字节；
//   检查256-bit输出的字节顺序，并检查rsp_ready反压期间数据保持。
//=============================================================================
module tb_flash_weight_reader;

reg clk;
reg rst_n;
reg req_valid;
wire req_ready;
reg [31:0] req_addr;
wire rsp_valid;
reg rsp_ready;
wire [255:0] rsp_data;
wire flash_csn;
wire flash_sclk;
wire flash_mosi;
wire flash_miso;
wire busy;
wire error;

tri1 flash_wpn;
tri1 flash_holdn;

integer timeout_count;
integer byte_index;
integer error_count;
reg [255:0] held_data;

flash_weight_reader #(
    .SPI_DIVIDER    (16'd1),
    .TIMEOUT_CYCLES (32'd200000)
) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .req_valid  (req_valid),
    .req_ready  (req_ready),
    .req_addr   (req_addr),
    .rsp_valid  (rsp_valid),
    .rsp_ready  (rsp_ready),
    .rsp_data   (rsp_data),
    .flash_csn  (flash_csn),
    .flash_sclk (flash_sclk),
    .flash_mosi (flash_mosi),
    .flash_miso (flash_miso),
    .busy       (busy),
    .error      (error)
);

W25Q128JVxIM u_flash (
    .CSn   (flash_csn),
    .CLK   (flash_sclk),
    .DIO   (flash_mosi),
    .DO    (flash_miso),
    .WPn   (flash_wpn),
    .HOLDn (flash_holdn)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    rst_n       = 1'b0;
    req_valid   = 1'b0;
    req_addr    = 32'd0;
    rsp_ready   = 1'b0;
    error_count = 0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    timeout_count = 0;
    while (!req_ready && timeout_count < 1000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!req_ready) begin
        $display("[ERROR] reader initialization timeout");
        $finish;
    end

    // 请求Flash byte address 0x000100处的一个32-Byte权重块。
    @(negedge clk);
    req_addr  = 32'h0000_0100;
    req_valid = 1'b1;
    while (!req_ready)
        @(negedge clk);
    @(posedge clk);
    @(negedge clk);
    req_valid = 1'b0;

    timeout_count = 0;
    while (!rsp_valid && timeout_count < 200000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end

    if (!rsp_valid) begin
        $display("[ERROR] Flash weight response timeout");
        error_count = error_count + 1;
    end else begin
        held_data = rsp_data;

        // 人为施加5周期反压，valid和data都必须保持不变。
        repeat (5) begin
            @(posedge clk);
            if (!rsp_valid || rsp_data !== held_data) begin
                $display("[ERROR] response changed under backpressure");
                error_count = error_count + 1;
            end
        end

        for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
            if (rsp_data[8*byte_index +: 8] !== byte_index[7:0]) begin
                $display(
                    "[ERROR] byte=%0d expected=%02h actual=%02h",
                    byte_index,
                    byte_index[7:0],
                    rsp_data[8*byte_index +: 8]
                );
                error_count = error_count + 1;
            end
        end

        @(negedge clk);
        rsp_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready = 1'b0;
    end

    if (error)
        error_count = error_count + 1;

    if (error_count == 0)
        $display("[TB_PASS] Flash 32-byte weight read and backpressure correct");
    else
        $display("[TB_FAIL] errors=%0d", error_count);

    $finish;
end

endmodule

