//=============================================================================
// 模块：apb_single_master
// 功能：把一次 start 脉冲转换成标准 APB setup/access 传输。
//
// 本模块只允许一个 outstanding 请求。done 在传输完成后拉高一个时钟；
// 对读操作，rdata 与 done 同时有效。
//=============================================================================

// [中文注释-自动补充]
// 模块作用：单事务APB主机。
// 关键变量/接口：req_valid/ready接收请求，PSEL/PENABLE构成APB两阶段访问，rsp_valid返回完成或错误。
// 握手约定：valid与ready在同一上升沿同时为1才完成一次传输；反压期间数据必须保持。
// 位宽约定：地址通常按Byte计，Weight块为256 bit，Activation/Weight基本元素为signed INT8。
// -----------------------------------------------------------------------------
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
// 连续赋值：组合生成ready及其相邻接口信号，表达握手、选择或地址关系。
assign ready   = (state == APB_IDLE);
assign psel    = (state != APB_IDLE);
// 连续赋值：组合生成penable及其相邻接口信号，表达握手、选择或地址关系。
assign penable = (state == APB_ACCESS);

// 时序逻辑：在时钟沿更新state、paddr、pwdata、pwrite、done、rdata；复位分支负责恢复确定的空闲状态。
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
