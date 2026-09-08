// 256-bit 权重块存储模型，byte 地址右移 5 位得到 32-Byte block 索引。
module weight_sram_model 
#(parameter ADDR_WIDTH=32,parameter BLOCKS=4096)(
 input clk,input rst_n,input random_enable,
 input req_valid,output req_ready,
 input [ADDR_WIDTH-1:0] req_addr,
 output reg rsp_valid,input rsp_ready,
 output reg [255:0] rsp_data);
reg [255:0] mem[0:BLOCKS-1];
reg [15:0] lfsr;
reg pending;
reg [2:0] delay_count;
reg [ADDR_WIDTH-1:0] aq;
assign req_ready=!pending&&!rsp_valid&&(!random_enable||lfsr[0]);

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin 
             lfsr<=16'hace1;
             pending<=0;
             delay_count<=0;
             aq<=0;
             rsp_valid<=0;
             rsp_data<=0; 
         end
        else begin
            lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            if(req_valid&&req_ready)begin 
                 aq<=req_addr;pending<=1;
                 delay_count<=random_enable?{1'b0,lfsr[3:2]}:3'd1;
            end
            if(pending)begin 
                 if(delay_count!=0)
                     delay_count<=delay_count-1'b1;
                else begin 
                 pending<=0;
                 rsp_valid<=1;
                 rsp_data<=mem[aq>>5];
                 end 
            end
            if(rsp_valid&&rsp_ready)
                 rsp_valid<=0;
         end
    end
endmodule
