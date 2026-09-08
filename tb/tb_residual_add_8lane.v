`timescale 1ns/1ps

//=============================================================================
// residual_add_8lane 单元测试
// 覆盖：普通加法、正/负饱和、byte strobe，以及输出端反压时数据保持。
//=============================================================================
module tb_residual_add_8lane;

reg clk;
reg rst_n;
reg in_valid;
wire in_ready;
reg [31:0] in_addr;
reg [31:0] output_base;
reg [63:0] in_data;
reg [7:0] in_strb;
wire scratch_rd_valid;
reg scratch_rd_ready;
wire [9:0] scratch_rd_addr;
reg scratch_rsp_valid;
reg [63:0] scratch_rsp_data;
wire out_valid;
reg out_ready;
wire [31:0] out_addr;
wire [63:0] out_data;
wire [7:0] out_strb;
wire error;

integer errors;
reg [63:0] scratch_memory [0:3];
reg response_pending;
reg [9:0] pending_addr;

residual_add_8lane u_dut (
    .clk(clk), .rst_n(rst_n),
    .in_valid(in_valid), .in_ready(in_ready),
    .in_addr(in_addr), .output_base(output_base),
    .in_data(in_data), .in_strb(in_strb),
    .scratch_rd_valid(scratch_rd_valid),
    .scratch_rd_ready(scratch_rd_ready),
    .scratch_rd_addr(scratch_rd_addr),
    .scratch_rsp_valid(scratch_rsp_valid),
    .scratch_rsp_data(scratch_rsp_data),
    .out_valid(out_valid), .out_ready(out_ready),
    .out_addr(out_addr), .out_data(out_data), .out_strb(out_strb),
    .error(error)
);

always #5 clk = ~clk;

// 模拟同步 SRAM：请求握手后的下一拍返回数据。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        response_pending <= 1'b0;
        pending_addr      <= 10'd0;
        scratch_rsp_valid <= 1'b0;
        scratch_rsp_data  <= 64'd0;
    end else begin
        scratch_rsp_valid <= response_pending;
        if (response_pending)
            scratch_rsp_data <= scratch_memory[pending_addr];
        response_pending <= scratch_rd_valid && scratch_rd_ready;
        if (scratch_rd_valid && scratch_rd_ready)
            pending_addr <= scratch_rd_addr;
    end
end

task send_and_check;
    input [31:0] address;
    input [63:0] branch_data;
    input [7:0] byte_strobe;
    input [63:0] expected_data;
    input hold_backpressure;
    reg [63:0] held_data;
    begin
        while (!in_ready) @(posedge clk);
        in_addr  = address;
        in_data  = branch_data;
        in_strb  = byte_strobe;
        in_valid = 1'b1;
        @(posedge clk);
        in_valid = 1'b0;

        while (!out_valid) @(posedge clk);
        if (hold_backpressure) begin
            out_ready = 1'b0;
            held_data = out_data;
            repeat (3) begin
                @(posedge clk);
                if (!out_valid || (out_data !== held_data)) begin
                    $display("[ERROR] output changed during backpressure");
                    errors = errors + 1;
                end
            end
        end

        if ((out_addr !== address) ||
            (out_data !== expected_data) ||
            (out_strb !== byte_strobe)) begin
            $display("[ERROR] addr=%h expected=%h actual=%h strb=%h",
                     address, expected_data, out_data, out_strb);
            errors = errors + 1;
        end else begin
            $display("[TRACE] residual addr=%h data=%h strb=%h PASS",
                     address, out_data, out_strb);
        end
        out_ready = 1'b1;
        @(posedge clk);
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    in_valid = 1'b0;
    in_addr = 32'd0;
    output_base = 32'h0000_3000;
    in_data = 64'd0;
    in_strb = 8'd0;
    scratch_rd_ready = 1'b1;
    scratch_rsp_valid = 1'b0;
    scratch_rsp_data = 64'd0;
    out_ready = 1'b1;
    errors = 0;

    // lane0 位于最低 8 bit。
    scratch_memory[0] = {8'd8,8'd7,8'd6,8'd5,8'd4,8'd3,8'd2,8'd1};
    scratch_memory[1] = {8'h80,8'h7f,8'd100,8'h9c,8'hff,8'd1,8'hec,8'd20};
    scratch_memory[2] = 64'h0101_0101_0101_0101;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    send_and_check(32'h0000_3000,
                   {8'd8,8'd7,8'd6,8'd5,8'd4,8'd3,8'd2,8'd1},
                   8'hff,
                   {8'd16,8'd14,8'd12,8'd10,8'd8,8'd6,8'd4,8'd2},
                   1'b0);

    // lane0..7：正饱和、负饱和、正饱和、负饱和、-50、50、127、-128。
    send_and_check(32'h0000_3008,
                   {8'hff,8'd0,8'hce,8'd50,8'h80,8'h7f,8'h88,8'd120},
                   8'hff,
                   {8'h80,8'h7f,8'd50,8'hce,8'h80,8'h7f,8'h80,8'h7f},
                   1'b1);

    // 仅低四个 byte 有效；无效 lane 输出清零，写 strobe 保持为 0。
    send_and_check(32'h0000_3010,
                   64'h0807_0605_0403_0201,
                   8'h0f,
                   64'h0000_0000_0504_0302,
                   1'b0);

    if (error) begin
        $display("[ERROR] DUT error unexpectedly asserted");
        errors = errors + 1;
    end

    if (errors == 0)
        $display("[TB_PASS] residual add normal/saturation/strobe/backpressure correct");
    else
        $display("[TB_FAIL] errors=%0d", errors);
    $finish;
end

endmodule
