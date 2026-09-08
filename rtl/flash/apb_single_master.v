//=============================================================================
// 模块：apb_single_master
// 功能：把一次 start 脉冲转换成标准 APB setup/access 传输。
//
// 本模块只允许一个 outstanding 请求。done 在传输完成后拉高一个时钟；
// 对读操作，rdata 与 done 同时有效。
//=============================================================================

module apb_single_master (
    input                                       clk,
    input                                       rst_n,
    input                                       start,
    output                                      ready,
    input                                       write,
    input              [4:0]                    addr,
    input              [31:0]                   wdata,
    output reg                                  done,
    output reg         [31:0]                   rdata,
    output reg         [4:0]                    paddr,
    output reg         [31:0]                   pwdata,
    input              [31:0]                   prdata,
    output reg                                  pwrite,
    output                                      psel,
    output                                      penable,
    input                                       pready,
    input                                       pslverr,
    output reg                                  error
);

localparam APB_IDLE   = 2'd0;
localparam APB_SETUP  = 2'd1;
localparam APB_ACCESS = 2'd2;
reg [1:0] state;
assign ready   = (state == APB_IDLE);
assign psel    = (state != APB_IDLE);
assign penable = (state == APB_ACCESS);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state  <= APB_IDLE;
        paddr  <= 5'd0;
        pwdata <= 32'd0;
        pwrite <= 1'b0;
        done   <= 1'b0;
        rdata  <= 32'd0;
        error  <= 1'b0;
    end else begin
        done <= 1'b0;
        case (state)
            APB_IDLE: begin
                if (start) begin
                    paddr  <= addr;
                    pwdata <= wdata;
                    pwrite <= write;
                    state  <= APB_SETUP;
                end
            end
            APB_SETUP: begin

                // APB规定setup阶段持续一个时钟，随后进入access阶段。
                state <= APB_ACCESS;
            end
            APB_ACCESS: begin
                if (pready) begin
                    rdata <= prdata;
                    done  <= 1'b1;
                    if (pslverr)
                        error <= 1'b1;
                    state <= APB_IDLE;
                end
            end
            default: state <= APB_IDLE;
        endcase
    end
end

endmodule
