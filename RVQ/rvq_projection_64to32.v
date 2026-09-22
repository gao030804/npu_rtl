`timescale 1ns/1ps
// 每20 ms执行一次的64D->32D无bias线性投影，等价于1x1 Conv1d。
// 权重为32x64 signed INT8，按(output_channel,input_group)写入，每字8个输入权重。
module rvq_projection_64to32(
 input clk,input rst_n,
 input weight_wr_valid,output weight_wr_ready,input [7:0] weight_wr_addr,input [63:0] weight_wr_data,
 input signed [31:0] requant_multiplier,input [5:0] requant_shift,
 input in_valid,output in_ready,input [63:0] in_data,input in_last,
 output reg out_valid,input out_ready,output reg [63:0] out_data,output reg out_last,
 output busy,output reg error);
localparam S_LOAD=0,S_CALC=1,S_SEND=2;
reg [1:0] state; reg signed [7:0] weights[0:2047]; reg signed [7:0] x[0:63];
reg signed [7:0] y[0:31]; reg [2:0] in_group; reg [5:0] out_channel; reg [2:0] send_group;
reg signed [31:0] acc; reg signed [63:0] scaled; integer i,wi;
assign weight_wr_ready=(state==S_LOAD)&&(in_group==0);
assign in_ready=(state==S_LOAD);
assign busy=(state!=S_LOAD)||(in_group!=0);
always @(*) begin
 acc=0; for(i=0;i<64;i=i+1) acc=acc+$signed(x[i])*$signed(weights[out_channel*64+i]);
 scaled=$signed(acc)*$signed(requant_multiplier);
end
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin state<=S_LOAD;in_group<=0;out_channel<=0;send_group<=0;out_valid<=0;out_data<=0;out_last<=0;error<=0;end
 else begin
  if(weight_wr_valid&&weight_wr_ready)
   for(wi=0;wi<8;wi=wi+1) weights[{weight_wr_addr,3'b000}+wi]<=weight_wr_data[8*wi+:8];
  case(state)
   S_LOAD:if(in_valid&&in_ready) begin
    for(i=0;i<8;i=i+1) x[{in_group,3'b000}+i]<=in_data[8*i+:8];
    if(in_last!=(in_group==7)) error<=1;
    if(in_group==7) begin in_group<=0;out_channel<=0;state<=S_CALC;end else in_group<=in_group+1'b1;
   end
   S_CALC:begin
    if(($signed(scaled)>>>requant_shift)>127) y[out_channel]<=127;
    else if(($signed(scaled)>>>requant_shift)<-128) y[out_channel]<=-128;
    else y[out_channel]<=($signed(scaled)>>>requant_shift);
    if(out_channel==31) begin send_group<=0;state<=S_SEND;end else out_channel<=out_channel+1'b1;
   end
   S_SEND:begin
    if(!out_valid) begin
     for(i=0;i<8;i=i+1) out_data[8*i+:8]<=y[{send_group,3'b000}+i];
     out_last<=(send_group==3);out_valid<=1;
    end else if(out_ready) begin
     out_valid<=0;
     if(send_group==3) begin out_last<=0;state<=S_LOAD;end else send_group<=send_group+1'b1;
    end
   end
   default:begin state<=S_LOAD;error<=1;end
  endcase
 end
end
endmodule
