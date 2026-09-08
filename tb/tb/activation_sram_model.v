// 4 读口行为模型：可随机阻塞请求并随机延迟响应；响应 valid 可保持。
module activation_sram_model #(parameter ADDR_WIDTH=32,parameter DEPTH=131072)(
     input clk,
     input rst_n,
     input random_enable,
     input req_valid,
     output req_ready,
     input [ADDR_WIDTH-1:0] addr0,addr1,addr2,addr3,
     input [3:0] mask,
     output reg rsp_valid,
     input rsp_ready,
     output reg [31:0] rsp_data);
      reg signed [7:0] mem[0:DEPTH-1];
      reg [15:0] lfsr;
      reg pending;
      reg [2:0] delay_count;
      reg [ADDR_WIDTH-1:0] a0,a1,a2,a3;
      reg [3:0] mq;
     assign req_ready=!pending&&!rsp_valid&&(!random_enable||lfsr[0]);
      always @(posedge clk or negedge rst_n) begin
                 if(!rst_n)begin 
                    lfsr<=16'h1;
                    pending<=0;
                    delay_count<=0;
                    rsp_valid<=0;
                    rsp_data<=0;
                    a0<=0; a1<=0; a2<=0; a3<=0;
                    mq<=0;
                    end
                else begin
                 lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
                         if(req_valid&&req_ready) begin 
                            a0<=addr0;a1<=addr1;a2<=addr2;a3<=addr3;
                            mq<=mask;pending<=1;delay_count<=random_enable?{1'b0,lfsr[2:1]}:3'd1;
                         end
                  if(pending)begin
                       if(delay_count!=0)
                           delay_count<=delay_count-1'b1;
                        else begin 
                            pending<=0;rsp_valid<=1;
                            rsp_data[7:0]<=mq[0]?mem[a0]:8'd0;
                            rsp_data[15:8]<=mq[1]?mem[a1]:8'd0;
                            rsp_data[23:16]<=mq[2]?mem[a2]:8'd0;
                            rsp_data[31:24]<=mq[3]?mem[a3]:8'd0;
                             end
                    end
                   if(rsp_valid&&rsp_ready)
                       rsp_valid<=0;
                end
         end
endmodule
