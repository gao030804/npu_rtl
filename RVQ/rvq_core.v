`timescale 1ns/1ps
// 9级非均匀32维Euclidean RVQ：q0=K256，q1~q8=K128。
// 每个码字32维INT8（4个64-bit word），紧凑码本共5120 words=40 KiB。
// 输出64 bit：q0占8 bit，q1~q8各占7 bit。
module rvq_core (
 input clk,input rst_n,
 input scale_cfg_valid,output scale_cfg_ready,input [3:0] scale_cfg_stage,
 input [31:0] scale_cfg_multiplier,input [5:0] scale_cfg_shift,
 input codebook_wr_valid,output codebook_wr_ready,input [13:0] codebook_wr_addr,input [63:0] codebook_wr_data,
 input latent_valid,output latent_ready,input [63:0] latent_data,input latent_last,
 output reg result_valid,input result_ready,output reg [63:0] result_indices,
 input [1:0] residual_debug_group,output [127:0] residual_debug_data,
 output busy,output reg error);
localparam [2:0] S_LOAD=0,S_SEARCH_REQ=1,S_SEARCH_WAIT=2,S_UPDATE_REQ=3,S_UPDATE_WAIT=4,S_OUTPUT=5;
reg [2:0] state;
reg [127:0] residual_mem [0:3];
reg [31:0] scale_multiplier [0:8]; reg [5:0] scale_shift [0:8];
reg [1:0] input_group,group_no; reg [3:0] stage;
reg [7:0] code_index,best_index; reg [31:0] distance_acc,min_distance;
reg [13:0] read_address; reg [35:0] distance_ext; reg [31:0] current_distance;
reg [127:0] latent_expanded; integer lane,i;
wire cb_rd_ready,cb_rsp_valid,cb_mem_wr_ready; wire [63:0] cb_rsp_data;
wire [127:0] aligned_codeword,updated_residual_group; wire [34:0] group_distance;
wire scale_overflow,residual_overflow;
wire [7:0] address_code_index =
    ((state==S_UPDATE_REQ)||(state==S_UPDATE_WAIT)) ? best_index : code_index;
function [13:0] stage_base; input [3:0] s; begin stage_base=(s==0)?14'd0:14'd1024+((s-1'b1)<<9); end endfunction
function [8:0] stage_entries; input [3:0] s; begin stage_entries=(s==0)?9'd256:9'd128; end endfunction
assign latent_ready=(state==S_LOAD)&&!result_valid;
assign scale_cfg_ready=(state==S_LOAD)&&!result_valid;
assign codebook_wr_ready=cb_mem_wr_ready&&(state==S_LOAD)&&!result_valid;
assign busy=(state!=S_LOAD)||result_valid||(input_group!=0);
assign residual_debug_data=residual_mem[residual_debug_group];
always @(*) begin
 latent_expanded=0;
 for(lane=0;lane<8;lane=lane+1) latent_expanded[16*lane+:16]={{8{latent_data[8*lane+7]}},latent_data[8*lane+:8]};
 // SEARCH阶段遍历code_index；UPDATE阶段必须重新读取best_index对应的获胜码字。
 // 如果UPDATE仍使用搜索结束时的code_index，就会错误减去每级最后一个码字。
 read_address=stage_base(stage)+({6'd0,address_code_index}<<2)+group_no;
 distance_ext={4'd0,distance_acc}+{1'b0,group_distance};
 current_distance=(|distance_ext[35:32])?32'hffff_ffff:distance_ext[31:0];
end
rvq_codebook_sram #(.DEPTH(5120)) u_codebook_sram(
 .clk(clk),.rst_n(rst_n),.wr_valid(codebook_wr_valid&&codebook_wr_ready),.wr_ready(cb_mem_wr_ready),
 .wr_addr(codebook_wr_addr),.wr_data(codebook_wr_data),
 .rd_valid(state==S_SEARCH_REQ||state==S_UPDATE_REQ),.rd_ready(cb_rd_ready),.rd_addr(read_address),
 .rd_rsp_valid(cb_rsp_valid),.rd_rsp_data(cb_rsp_data));
rvq_scale_align_8lane u_scale_align(.codebook_data(cb_rsp_data),.multiplier(scale_multiplier[stage]),
 .shift(scale_shift[stage]),.aligned_data(aligned_codeword),.overflow(scale_overflow));
rvq_distance_8lane u_distance(.residual_data(residual_mem[group_no]),.codeword_data(aligned_codeword),.group_distance(group_distance));
rvq_residual_update_8lane u_residual_update(.residual_data(residual_mem[group_no]),.codeword_data(aligned_codeword),
 .residual_next(updated_residual_group),.overflow(residual_overflow));
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  state<=S_LOAD;input_group<=0;group_no<=0;stage<=0;code_index<=0;best_index<=0;
  distance_acc<=0;min_distance<=32'hffff_ffff;result_valid<=0;result_indices<=0;error<=0;
  for(i=0;i<9;i=i+1) begin scale_multiplier[i]<=1;scale_shift[i]<=0;end
 end else begin
  if(scale_cfg_valid&&scale_cfg_ready) begin
   if(scale_cfg_stage<=8) begin scale_multiplier[scale_cfg_stage]<=scale_cfg_multiplier;scale_shift[scale_cfg_stage]<=scale_cfg_shift;end
   else error<=1;
  end
  case(state)
   S_LOAD:if(latent_valid&&latent_ready) begin
    residual_mem[input_group]<=latent_expanded;
    if(latent_last!=(input_group==3)) error<=1;
    if(input_group==3) begin input_group<=0;group_no<=0;stage<=0;code_index<=0;best_index<=0;
     distance_acc<=0;min_distance<=32'hffff_ffff;result_indices<=0;state<=S_SEARCH_REQ;end
    else input_group<=input_group+1'b1;
   end
   S_SEARCH_REQ:if(cb_rd_ready) state<=S_SEARCH_WAIT;
   S_SEARCH_WAIT:if(cb_rsp_valid) begin
    if(scale_overflow||(|distance_ext[35:32])) error<=1;
    if(group_no==3) begin
     if(current_distance<min_distance) begin min_distance<=current_distance;best_index<=code_index;end
     distance_acc<=0;group_no<=0;
     if(code_index==stage_entries(stage)-1'b1) state<=S_UPDATE_REQ;
     else begin code_index<=code_index+1'b1;state<=S_SEARCH_REQ;end
    end else begin distance_acc<=current_distance;group_no<=group_no+1'b1;state<=S_SEARCH_REQ;end
   end
   S_UPDATE_REQ:if(cb_rd_ready) state<=S_UPDATE_WAIT;
   S_UPDATE_WAIT:if(cb_rsp_valid) begin
    residual_mem[group_no]<=updated_residual_group;if(scale_overflow||residual_overflow) error<=1;
    if(group_no==3) begin group_no<=0;
     case(stage)
      0:result_indices[7:0]<=best_index;1:result_indices[14:8]<=best_index[6:0];
      2:result_indices[21:15]<=best_index[6:0];3:result_indices[28:22]<=best_index[6:0];
      4:result_indices[35:29]<=best_index[6:0];5:result_indices[42:36]<=best_index[6:0];
      6:result_indices[49:43]<=best_index[6:0];7:result_indices[56:50]<=best_index[6:0];
      8:result_indices[63:57]<=best_index[6:0];
     endcase
     if(stage==8) begin result_valid<=1;state<=S_OUTPUT;end
     else begin stage<=stage+1'b1;code_index<=0;best_index<=0;distance_acc<=0;min_distance<=32'hffff_ffff;state<=S_SEARCH_REQ;end
    end else begin group_no<=group_no+1'b1;state<=S_UPDATE_REQ;end
   end
   S_OUTPUT:if(result_valid&&result_ready) begin result_valid<=0;state<=S_LOAD;end
   default:begin state<=S_LOAD;error<=1;end
  endcase
 end
end
endmodule
