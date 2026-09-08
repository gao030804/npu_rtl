// 每个 output_group 返回 8 路 bias、multiplier 和 shift 的参数模型。
module parameter_memory_model #(parameter GROUPS=32)(
 input clk,input rst_n,input random_enable,input req_valid,output req_ready,input [5:0] output_group,
 output reg rsp_valid,input rsp_ready,output reg [255:0] bias_data,mult_data,output reg [47:0] shift_data,
 output reg [63:0] zero_point_data);
reg [255:0] bias_mem[0:GROUPS-1],mult_mem[0:GROUPS-1];reg [47:0] shift_mem[0:GROUPS-1];
reg [63:0] zero_point_mem[0:GROUPS-1];
reg [15:0] lfsr;reg pending;reg [2:0] delay_count;reg [5:0] gq;
assign req_ready=!pending&&!rsp_valid&&(!random_enable||lfsr[0]);
always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin lfsr<=16'h1234;pending<=0;delay_count<=0;gq<=0;rsp_valid<=0;bias_data<=0;mult_data<=0;shift_data<=0;zero_point_data<=0;end
 else begin
  lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
  if(req_valid&&req_ready)begin gq<=output_group;pending<=1;delay_count<=random_enable?{1'b0,lfsr[2:1]}:3'd1;end
  if(pending)begin if(delay_count!=0)delay_count<=delay_count-1'b1;else begin pending<=0;rsp_valid<=1;bias_data<=bias_mem[gq];mult_data<=mult_mem[gq];shift_data<=shift_mem[gq];zero_point_data<=zero_point_mem[gq];end end
  if(rsp_valid&&rsp_ready)rsp_valid<=0;
 end
end
endmodule
