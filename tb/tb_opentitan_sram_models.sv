`timescale 1ns/1ps
module tb_opentitan_sram_models;

logic clk;
logic rst_n;
logic sp_req,sp_write;
logic [3:0] sp_addr;
logic [31:0] sp_wdata,sp_rdata;
logic [3:0] sp_wmask;
logic sp_rvalid;
logic rw_wr_req,rw_rd_req;
logic [3:0] rw_wr_addr,rw_rd_addr;
logic [31:0] rw_wr_data,rw_rd_data;
logic [3:0] rw_wr_mask;
logic rw_rd_valid;
integer errors;

opentitan_sram_1p_adapter #(.WIDTH(32),.DEPTH(16),.DATA_BITS_PER_MASK(8)) u_1p (
    .clk_i(clk),.rst_ni(rst_n),.req_i(sp_req),.write_i(sp_write),
    .addr_i(sp_addr),.wdata_i(sp_wdata),.wmask_i(sp_wmask),
    .rdata_o(sp_rdata),.rvalid_o(sp_rvalid)
);

opentitan_sram_1r1w_adapter #(.WIDTH(32),.DEPTH(16),.DATA_BITS_PER_MASK(8)) u_1r1w (
    .clk_i(clk),.rst_ni(rst_n),
    .wr_req_i(rw_wr_req),.wr_addr_i(rw_wr_addr),.wr_data_i(rw_wr_data),.wr_mask_i(rw_wr_mask),
    .rd_req_i(rw_rd_req),.rd_addr_i(rw_rd_addr),.rd_data_o(rw_rd_data),.rd_valid_o(rw_rd_valid)
);

initial clk = 1'b0;
always #5 clk = ~clk;

task sp_write_word(input [3:0] addr,input [31:0] data,input [3:0] mask);
    @(negedge clk); sp_req=1;sp_write=1;sp_addr=addr;sp_wdata=data;sp_wmask=mask;
    @(posedge clk); @(negedge clk); sp_req=0;sp_write=0;
endtask

task sp_check_word(input [3:0] addr,input [31:0] expected);
    @(negedge clk); sp_req=1;sp_write=0;sp_addr=addr;
    @(posedge clk); @(negedge clk); sp_req=0;
    if(!sp_rvalid || sp_rdata !== expected) begin
        $display("[FAIL][1P] addr=%0d expected=%08h actual=%08h valid=%0b",addr,expected,sp_rdata,sp_rvalid);
        errors=errors+1;
    end
endtask

initial begin
    rst_n=0;errors=0;
    sp_req=0;sp_write=0;sp_addr=0;sp_wdata=0;sp_wmask=0;
    rw_wr_req=0;rw_rd_req=0;rw_wr_addr=0;rw_rd_addr=0;rw_wr_data=0;rw_wr_mask=0;
    repeat(3) @(posedge clk); @(negedge clk); rst_n=1;

    sp_write_word(4'd3,32'haabb_ccdd,4'b1111);
    sp_check_word(4'd3,32'haabb_ccdd);
    sp_write_word(4'd3,32'h0000_1100,4'b0010);
    sp_check_word(4'd3,32'haabb_11dd);

    @(negedge clk); rw_wr_req=1;rw_wr_addr=4'd5;rw_wr_data=32'h1234_5678;rw_wr_mask=4'b1111;
    @(posedge clk); @(negedge clk); rw_wr_req=0;rw_rd_req=1;rw_rd_addr=4'd5;
    @(posedge clk); @(negedge clk); rw_rd_req=0;
    if(!rw_rd_valid || rw_rd_data !== 32'h1234_5678) begin
        $display("[FAIL][1R1W] expected=12345678 actual=%08h valid=%0b",rw_rd_data,rw_rd_valid);
        errors=errors+1;
    end

    if(errors==0) $display("[TB_PASS] OpenTitan SRAM standalone models");
    else $display("[TB_FAIL] OpenTitan SRAM errors=%0d",errors);
    $finish;
end
endmodule
