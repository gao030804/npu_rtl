// 仅供仿真的 4x8 Mesh 行为模型：每列计算 4 个 INT8 乘积之和。
// LATENCY 模拟固定流水深度；ce=0 时权重、数据、valid、tag 全部保持。
// 该文件不是物理 Mesh RTL，不能替代真实阵列进行 ASIC 综合实现。
module mesh_core_4x8 #(parameter M_TAG_WIDTH=9, parameter LATENCY=3) (
 input clk,input rst_n,input ce,input weight_load,input [255:0] weight_data,
 input act_valid,input [31:0] act_data,input [M_TAG_WIDTH-1:0] act_m_tag,
 output psum_valid,output [159:0] psum_data,output [M_TAG_WIDTH-1:0] psum_m_tag
);
reg [255:0] w;
reg [LATENCY-1:0] vp;
reg [159:0] dp[0:LATENCY-1];
reg [M_TAG_WIDTH-1:0] tp[0:LATENCY-1];
reg signed [7:0] a0,a1,a2,a3,ww;
reg signed [19:0] sum;
reg [159:0] dot;
integer i,n;
assign psum_valid=vp[LATENCY-1];
assign psum_data=dp[LATENCY-1];
assign psum_m_tag=tp[LATENCY-1];
always @(*) begin
 a0=act_data[7:0];a1=act_data[15:8];a2=act_data[23:16];a3=act_data[31:24];
 ww=0;sum=0;dot=0;
 for(n=0;n<8;n=n+1) begin
  ww=w[8*(0*8+n) +: 8];sum=$signed(a0)*$signed(ww);
  ww=w[8*(1*8+n) +: 8];sum=sum+$signed(a1)*$signed(ww);
  ww=w[8*(2*8+n) +: 8];sum=sum+$signed(a2)*$signed(ww);
  ww=w[8*(3*8+n) +: 8];sum=sum+$signed(a3)*$signed(ww);
  dot[20*n +: 20]=sum;
 end
end
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin w<=0;vp<=0;for(i=0;i<LATENCY;i=i+1)begin dp[i]<=0;tp[i]<=0;end end
 else if(ce) begin
  if(weight_load)w<=weight_data;
  vp[0]<=act_valid;dp[0]<=dot;tp[0]<=act_m_tag;
  for(i=1;i<LATENCY;i=i+1)begin vp[i]<=vp[i-1];dp[i]<=dp[i-1];tp[i]<=tp[i-1];end
 end
end
endmodule
