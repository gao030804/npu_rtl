// ============================================================================
// 中文阅读导引（当前实现）
// 8路INT20部分和符号扩展后跨k_group累加为8路INT32。
// 默认8个320×32-bit存储Bank，共10 KiB；地址对应输出时间位置m。
// 首k_group覆盖旧值，后续组读改写；流水中的地址/首组标记必须与数据一同传递。
// pipeline_busy用于层控制边界，避免最后一项尚未写回就开始后处理读取。
// ============================================================================
//=============================================================================
// 模块：accumulator_8lane
// 功能：保存一个 output_group 内、每个时间位置 m 的 8 路 INT32 累加值。
//
// 存储结构：8 个相互独立的 32-bit SRAM Bank，每个 Bank 对应一个输出
// lane。首 K 组直接覆盖；后续 K 组执行“同步读 -> 相加 -> 写回”。
// SRAM 内容不在复位时清零，新一轮计算必须先写 first_k_group。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 每拍接收一组8路INT20部分和，符号扩展为INT32后写入对应m地址。
// - first_k_group=1时覆盖旧值，其他k_group读取旧值后相加，形成完整Cin*K规约。
// - pipeline_busy表示仍有未提交的读改写事务，控制器必须等待其清空后读最终结果。
// -------------------------------------------------------------------------
module accumulator_8lane #(
    parameter MAX_M       = 320,
    parameter M_TAG_WIDTH = 9
) (
    input                                       clk,
    input                                       rst_n,
    input                                       in_valid,
    output                                      in_ready,
    input                                       first_k_group,
    input              [M_TAG_WIDTH-1:0]        in_m_tag,
    input              [159:0]                  in_psum,
    input                                       rd_req_valid,
    output                                      rd_req_ready,
    input              [M_TAG_WIDTH-1:0]        rd_req_addr,
    output                                      rd_rsp_valid,
    input                                       rd_rsp_ready,
    output             [255:0]                  rd_rsp_data,
    output             [M_TAG_WIDTH-1:0]        rd_rsp_addr,
    output                                      pipeline_busy
);

// 将 8 路 INT20 部分和拆开，并符号扩展为 INT32。
wire signed [19:0] p0 = in_psum[ 19:  0];
wire signed [19:0] p1 = in_psum[ 39: 20];
wire signed [19:0] p2 = in_psum[ 59: 40];
wire signed [19:0] p3 = in_psum[ 79: 60];
wire signed [19:0] p4 = in_psum[ 99: 80];
wire signed [19:0] p5 = in_psum[119:100];
wire signed [19:0] p6 = in_psum[139:120];
wire signed [19:0] p7 = in_psum[159:140];
wire signed [31:0] psum_ext0 = {{12{p0[19]}}, p0};
wire signed [31:0] psum_ext1 = {{12{p1[19]}}, p1};
wire signed [31:0] psum_ext2 = {{12{p2[19]}}, p2};
wire signed [31:0] psum_ext3 = {{12{p3[19]}}, p3};
wire signed [31:0] psum_ext4 = {{12{p4[19]}}, p4};
wire signed [31:0] psum_ext5 = {{12{p5[19]}}, p5};
wire signed [31:0] psum_ext6 = {{12{p6[19]}}, p6};
wire signed [31:0] psum_ext7 = {{12{p7[19]}}, p7};

// RMW 流水寄存器。rmw_pending=1 表示本拍应把 SRAM 读值加上 add* 后写回。
reg                       rmw_pending;
reg [M_TAG_WIDTH-1:0]     rmw_addr;
reg signed [31:0]         add0, add1, add2, add3;
reg signed [31:0]         add4, add5, add6, add7;

// 后处理请求已进入同步 SRAM，等待下一拍收集 8 Bank 数据。
reg                       post_read_pending;
reg [M_TAG_WIDTH-1:0]     post_read_addr_q;
reg [255:0]               post_rsp_data_fifo [0:7];
reg [M_TAG_WIDTH-1:0]     post_rsp_addr_fifo [0:7];
reg [2:0]                 post_rsp_wr_ptr;
reg [2:0]                 post_rsp_rd_ptr;
reg [3:0]                 post_rsp_count;

// 后处理读通道占用时暂停阵列输入。RMW 写回期间仍可接收下一笔后续组读取；
// 但首组覆盖写与 RMW 写回共用写端口，所以必须等待。
// 后续K组使用1R1W端口：本拍写回上一项的同时，可读取下一项，II=1。
// 只有第一K组直接覆盖写与尚未结束的RMW写回冲突时才暂停输入。
assign in_ready = !rd_req_valid && !rd_rsp_valid && !post_read_pending &&
    !(first_k_group && rmw_pending);
wire post_rsp_pop = rd_rsp_valid && rd_rsp_ready;
wire [4:0] post_reserved_count = {1'b0, post_rsp_count} +
    (post_read_pending ? 5'd1 : 5'd0);
wire post_rsp_has_space = (post_reserved_count < 5'd8) || post_rsp_pop;
assign rd_req_ready = !in_valid && !rmw_pending && post_rsp_has_space;
wire in_fire       = in_valid && in_ready;
wire first_wr_fire = in_fire &&  first_k_group;
wire rmw_rd_fire   = in_fire && !first_k_group;
wire post_rd_fire  = rd_req_valid && rd_req_ready;
assign pipeline_busy = rmw_pending;
assign rd_rsp_valid = (post_rsp_count != 0);
assign rd_rsp_data  = post_rsp_data_fifo[post_rsp_rd_ptr];
assign rd_rsp_addr  = post_rsp_addr_fifo[post_rsp_rd_ptr];

// 读端口：RMW 和后处理二选一；写端口：RMW 写回优先于首组覆盖。
wire                   bank_rd_req  = rmw_rd_fire || post_rd_fire;
wire [M_TAG_WIDTH-1:0] bank_rd_addr = rmw_rd_fire ? in_m_tag : rd_req_addr;
wire                   bank_wr_req  = rmw_pending || first_wr_fire;
wire [M_TAG_WIDTH-1:0] bank_wr_addr = rmw_pending ? rmw_addr : in_m_tag;
wire signed [31:0] bank_q0, bank_q1, bank_q2, bank_q3;
wire signed [31:0] bank_q4, bank_q5, bank_q6, bank_q7;
wire unused_v0, unused_v1, unused_v2, unused_v3;
wire unused_v4, unused_v5, unused_v6, unused_v7;
wire signed [31:0] bank_w0 = rmw_pending ? bank_q0 + add0 : psum_ext0;
wire signed [31:0] bank_w1 = rmw_pending ? bank_q1 + add1 : psum_ext1;
wire signed [31:0] bank_w2 = rmw_pending ? bank_q2 + add2 : psum_ext2;
wire signed [31:0] bank_w3 = rmw_pending ? bank_q3 + add3 : psum_ext3;
wire signed [31:0] bank_w4 = rmw_pending ? bank_q4 + add4 : psum_ext4;
wire signed [31:0] bank_w5 = rmw_pending ? bank_q5 + add5 : psum_ext5;
wire signed [31:0] bank_w6 = rmw_pending ? bank_q6 + add6 : psum_ext6;
wire signed [31:0] bank_w7 = rmw_pending ? bank_q7 + add7 : psum_ext7;

// 每个实例内部均为 OpenTitan prim_ram_1r1w，32 bit 整字写入。
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank0 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w0),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q0),
    .rd_valid_o                  (unused_v0));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank1 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w1),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q1),
    .rd_valid_o                  (unused_v1));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank2 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w2),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q2),
    .rd_valid_o                  (unused_v2));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank3 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w3),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q3),
    .rd_valid_o                  (unused_v3));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank4 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w4),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q4),
    .rd_valid_o                  (unused_v4));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank5 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w5),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q5),
    .rd_valid_o                  (unused_v5));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank6 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w6),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q6),
    .rd_valid_o                  (unused_v6));
opentitan_sram_1r1w_adapter #(.WIDTH(32),
    .DEPTH                       (MAX_M),
    .DATA_BITS_PER_MASK          (32)) u_bank7 (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .wr_req_i                    (bank_wr_req),
    .wr_addr_i                   (bank_wr_addr),
    .wr_data_i                   (bank_w7),
    .wr_mask_i                   (1'b1),
    .rd_req_i                    (bank_rd_req),
    .rd_addr_i                   (bank_rd_addr),
    .rd_data_o                   (bank_q7),
    .rd_valid_o                  (unused_v7));

// 锁存 RMW 标签/加数，并把后处理读出的 8 个 Bank 拼成 256 bit。

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rmw_pending       <= 1'b0;
        rmw_addr          <= {M_TAG_WIDTH{1'b0}};
        post_read_pending <= 1'b0;
        post_read_addr_q  <= {M_TAG_WIDTH{1'b0}};
        post_rsp_wr_ptr   <= 3'd0;
        post_rsp_rd_ptr   <= 3'd0;
        post_rsp_count    <= 4'd0;
        add0 <= 32'sd0;
        add1 <= 32'sd0;
        add2 <= 32'sd0;
        add3 <= 32'sd0;
        add4 <= 32'sd0;
        add5 <= 32'sd0;
        add6 <= 32'sd0;
        add7 <= 32'sd0;
    end else begin

        // 上一笔 pending 操作在本拍完成；下方若接收新请求会重新置位。
        rmw_pending       <= 1'b0;
        post_read_pending <= 1'b0;
        if (post_read_pending) begin
            post_rsp_data_fifo[post_rsp_wr_ptr] <= {
            bank_q7, bank_q6, bank_q5, bank_q4,
            bank_q3, bank_q2, bank_q1, bank_q0
            };
            post_rsp_addr_fifo[post_rsp_wr_ptr] <= post_read_addr_q;
            post_rsp_wr_ptr <= post_rsp_wr_ptr + 1'b1;
        end
        if (post_rsp_pop)
            post_rsp_rd_ptr <= post_rsp_rd_ptr + 1'b1;
        case ({post_read_pending, post_rsp_pop})
            2'b10: post_rsp_count <= post_rsp_count + 1'b1;
            2'b01: post_rsp_count <= post_rsp_count - 1'b1;
            default: post_rsp_count <= post_rsp_count;
        endcase
        if (rmw_rd_fire) begin
            rmw_pending <= 1'b1;
            rmw_addr    <= in_m_tag;
            add0 <= psum_ext0;
            add1 <= psum_ext1;
            add2 <= psum_ext2;
            add3 <= psum_ext3;
            add4 <= psum_ext4;
            add5 <= psum_ext5;
            add6 <= psum_ext6;
            add7 <= psum_ext7;
        end
        if (post_rd_fire) begin
            post_read_pending <= 1'b1;
            post_read_addr_q  <= rd_req_addr;
        end
    end
end

endmodule
