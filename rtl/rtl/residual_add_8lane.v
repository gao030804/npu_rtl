// ============================================================================
// 中文阅读导引（当前实现）
// 主支路INT8结果与Scratchpad中的identity逐通道相加、饱和并写回。
// 两条支路必须具有相同量化Scale，本模块不执行独立的支路Scale转换。
// 输出反压会延缓完成，帧级调度器须等待最后一次实际写回。
// ============================================================================
//=============================================================================
// 模块：residual_add_8lane
// 功能：将主支路8路INT8与Residual Scratch中的8路INT8执行饱和加法。
//
// 量化约束：两路数据必须已经位于相同的signed-INT8 scale，zero_point=0。
// 该约束对应训练端HardwareResidualAdd的shared-scale量化方式。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 根据主分支输出Byte地址换算Scratch word地址，读出8路identity并逐lane相加。
// - 加法使用signed 9-bit中间值并饱和到[-128,127]；write strobe为0的lane不产生有效结果。
// - 当前要求主分支与identity使用相同Scale；非单位Residual Scale需额外Requant参数。
// -------------------------------------------------------------------------
module residual_add_8lane #(
    parameter ADDR_WIDTH = 32,
    parameter SCRATCH_ADDR_WIDTH = 10
) (
    input                                       clk,
    input                                       rst_n,
    input                                       in_valid,
    output                                      in_ready,
    output                                      busy,
    input              [ADDR_WIDTH-1:0]         in_addr,
    input              [ADDR_WIDTH-1:0]         output_base,
    input              [63:0]                   in_data,
    input              [7:0]                    in_strb,
    output                                      scratch_rd_valid,
    input                                       scratch_rd_ready,
    output             [SCRATCH_ADDR_WIDTH-1:0] scratch_rd_addr,
    input                                       scratch_rsp_valid,
    input              [63:0]                   scratch_rsp_data,
    output reg                                  out_valid,
    input                                       out_ready,
    output reg         [ADDR_WIDTH-1:0]         out_addr,
    output reg         [63:0]                   out_data,
    output reg         [7:0]                    out_strb,
    output reg                                  error
);

localparam [1:0] S_IDLE = 2'd0, S_READ = 2'd1, S_WAIT = 2'd2;
reg [1:0] state;
reg [ADDR_WIDTH-1:0] addr_q;
reg [ADDR_WIDTH-1:0] base_q;
reg [63:0] data_q;
reg [7:0] strb_q;
wire [ADDR_WIDTH-1:0] byte_offset = addr_q - base_q;
wire [ADDR_WIDTH-1:0] input_byte_offset = in_addr - output_base;
assign in_ready = (state == S_IDLE) && (!out_valid || out_ready);

// state回到IDLE但out_valid仍被反压时，模块仍未排空。
assign busy = (state != S_IDLE) || out_valid;
assign scratch_rd_valid = (state == S_READ);
assign scratch_rd_addr = byte_offset[SCRATCH_ADDR_WIDTH+2:3];
integer lane;
reg signed [8:0] lane_sum;
reg [63:0] added_data;

always @(*) begin
    added_data = 64'd0;
    lane_sum = 9'sd0;
    for (lane=0; lane<8; lane=lane+1) begin
        lane_sum = $signed(data_q[8*lane +: 8]) +
            $signed(scratch_rsp_data[8*lane +: 8]);
        if (!strb_q[lane])
            added_data[8*lane +: 8] = 8'd0;
        else if (lane_sum > 9'sd127)
            added_data[8*lane +: 8] = 8'h7f;
        else if (lane_sum < -9'sd128)
            added_data[8*lane +: 8] = 8'h80;
        else
        added_data[8*lane +: 8] = lane_sum[7:0];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= S_IDLE;
        addr_q    <= {ADDR_WIDTH{1'b0}};
        base_q    <= {ADDR_WIDTH{1'b0}};
        data_q    <= 64'd0;
        strb_q    <= 8'd0;
        out_valid <= 1'b0;
        out_addr  <= {ADDR_WIDTH{1'b0}};
        out_data  <= 64'd0;
        out_strb  <= 8'd0;
        error     <= 1'b0;
    end else begin
        if (out_valid && out_ready)
            out_valid <= 1'b0;
        case (state)
            S_IDLE: begin
                if (in_valid && in_ready) begin
                    addr_q <= in_addr;
                    base_q <= output_base;
                    data_q <= in_data;
                    strb_q <= in_strb;
                    if ((in_addr < output_base) ||
                        (input_byte_offset[2:0] != 3'b000)) begin
                        error <= 1'b1;
                    end
                    state <= S_READ;
                end
            end
            S_READ:
                if (scratch_rd_valid && scratch_rd_ready)
                state <= S_WAIT;
            S_WAIT: begin
                if (scratch_rsp_valid) begin
                    out_valid <= 1'b1;
                    out_addr  <= addr_q;
                    out_data  <= added_data;
                    out_strb  <= strb_q;
                    state     <= S_IDLE;
                end
            end
            default: begin
                state <= S_IDLE;
                error <= 1'b1;
            end
        endcase
    end
end

endmodule
