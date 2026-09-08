// 按 byte strobe 写入的 Output SRAM 模型，可随机拉低 wr_ready。
module output_sram_model #(parameter ADDR_WIDTH=32,parameter DEPTH=131072)(
 input clk,input rst_n,input random_enable,input wr_valid,output wr_ready,
 input [ADDR_WIDTH-1:0] wr_addr,input [63:0] wr_data,input [7:0] wr_strb);
reg signed [7:0] mem[0:DEPTH-1];reg [15:0] lfsr;integer i;
assign wr_ready=!random_enable||lfsr[0]||lfsr[3];
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)lfsr<=16'h55aa;
 else begin
  lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
  if(wr_valid&&wr_ready)for(i=0;i<8;i=i+1)if(wr_strb[i])mem[wr_addr+i]<=wr_data[8*i +: 8];
 end
end
endmodule
