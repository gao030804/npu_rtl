// ============================================================================
// 中文阅读导引（当前实现）
// 当前配置8级×256码字×64维。S_LOAD装入8组latent；S_SEARCH逐码字计算距离；S_UPDATE减去选中码字；S_OUTPUT等待结果握手。
// 码本地址={stage[3:0],index[3:0],dimension_group[2:0]}，共11 bit。
// result_indices[8*stage +:8]保存本级UINT8索引，8级合计64 bit；只在result_valid有效后读取最终结果。
// 不同级码本先映射到共同残差Scale。距离和残差使用饱和逻辑，error用于报告溢出或输入last位置错误。
// ============================================================================
`timescale 1ns/1ps

//=============================================================================
// 模块：rvq_core
// 功能：8级、256码字/级、64维Residual Vector Quantizer顶层。
//
// 数据格式：
//   Encoder输入latent       ：8路signed INT8，每帧8拍，共64维
//   Codebook SRAM          ：8路signed INT8，每字64 bit
//   Residual Buffer        ：8路signed INT16，每组128 bit
//   Distance              ：UINT32，溢出时饱和到32'hffff_ffff
//   输出index              ：8级 × UINT8 = 64 bit
//
// 工作顺序：
//   1. latent_valid/ready装入8拍INT8 latent，并符号扩展为INT16；
//   2. 对当前stage连续读取16×8个码本word；
//   3. 每拍计算8维平方距离，64维完成后更新最小距离；
//   4. 重新读取选中码字，用INT16饱和减法更新Residual；
//   5. 重复8级，最后通过result_valid/ready输出8个UINT8 index。
//
// 相同距离采用较小index：码字按0到15扫描，比较条件使用严格小于。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 接收64维INT8 latent，按8维一组装入内部Residual寄存器。
// - 每级扫描256个64维码字；每个码字读取8个64-bit word并累加UINT32平方距离。
// - 选择最小距离index后，从Residual减去选中码字并量化回INT8，再进入下一级搜索。
// - result_indices[8*stage+:8]保存8级UINT8索引；result_valid等待result_ready时保持结果。
// -------------------------------------------------------------------------
module rvq_core (
    input                                       clk,
    input                                       rst_n,

    // 每个stage的码本Scale对齐参数，配置应在输入一帧latent前完成。
    input                                       scale_cfg_valid,
    output                                      scale_cfg_ready,
    input              [2:0]                    scale_cfg_stage,
    input              [31:0]                   scale_cfg_multiplier,
    input              [5:0]                    scale_cfg_shift,

    // 码本装载端口：地址格式为{stage,index,dimension_group}。
    input                                       codebook_wr_valid,
    output                                      codebook_wr_ready,
    input              [13:0]                   codebook_wr_addr,
    input              [63:0]                   codebook_wr_data,

    // 64维latent流：每拍8×INT8，共8拍。第8拍必须同时拉高latent_last。
    input                                       latent_valid,
    output                                      latent_ready,
    input              [63:0]                   latent_data,
    input                                       latent_last,

    // 8个UINT8 RVQ index，result_valid受result_ready反压。
    output reg                                  result_valid,
    input                                       result_ready,
    output reg         [63:0]                   result_indices,

    // 调试读口：读取当前64维Residual中的一个8维分组。
    input              [2:0]                    residual_debug_group,
    output             [127:0]                  residual_debug_data,
    output                                      busy,
    output reg                                  error
);

localparam [1:0] S_LOAD   = 2'd0;

// S_LOAD接收latent；SEARCH只读残差；UPDATE修改残差；OUTPUT保持结果。
localparam [1:0] S_SEARCH = 2'd1;
localparam [1:0] S_UPDATE = 2'd2;
localparam [1:0] S_OUTPUT = 2'd3;
reg [1:0] state;

// 每个stage保存一个非负32-bit multiplier和6-bit右移量。
reg [31:0] scale_multiplier [0:7];

// 8级参数独立保存；残差始终采用同一量化尺度。
reg [5:0]  scale_shift      [0:7];

// 64维Residual按8组存放，每组8×INT16=128 bit。
reg [127:0] residual_mem [0:7];
reg [2:0] input_group;
reg [2:0] stage;

// 搜索阶段共发出128次读取：16个码字×8个维度组。
reg [11:0] search_issue_count;
reg [2:0]  search_rsp_group;
reg [7:0]  search_rsp_index;
reg [31:0] distance_acc;
reg [31:0] min_distance;
reg [7:0]  best_index;

// Residual更新阶段重新读取选中码字的8个维度组。
reg [3:0] update_issue_count;
reg [2:0] update_rsp_group;
wire        cb_rd_valid;
wire        cb_rd_ready;
wire [13:0] cb_rd_addr;
wire        cb_rsp_valid;
wire [63:0] cb_rsp_data;
wire        cb_mem_wr_ready;
wire [127:0] aligned_codeword;
wire         scale_overflow;
wire [127:0] active_residual_group;
wire [34:0]  group_distance;
wire [127:0] updated_residual_group;
wire         residual_overflow;
reg [35:0] distance_sum_ext;
reg [31:0] distance_after_group;
reg        distance_overflow;
reg [127:0] latent_expanded;
integer lane;
integer cfg_i;
assign latent_ready = (state == S_LOAD) && !result_valid;
assign scale_cfg_ready = (state == S_LOAD) && !result_valid;
assign codebook_wr_ready = cb_mem_wr_ready && (state == S_LOAD) && !result_valid;
assign busy = (state != S_LOAD) || result_valid || (input_group != 3'd0);
assign residual_debug_data = residual_mem[residual_debug_group];

// SEARCH连续顺序扫描一个stage；UPDATE只读best_index对应的8个word。
assign cb_rd_valid = ((state == S_SEARCH) &&
    (search_issue_count < 12'd2048)) ||
    ((state == S_UPDATE) &&
    (update_issue_count < 4'd8));
assign cb_rd_addr = (state == S_SEARCH) ?
    {stage,search_issue_count[10:0]} :
    {stage,best_index,update_issue_count[2:0]};
rvq_codebook_sram u_codebook_sram (

    // 码本与运算通路的边界：请求与同步返回由核心计数器对应。
    .clk                         (clk),
    .rst_n                       (rst_n),
    .wr_valid                    (codebook_wr_valid && codebook_wr_ready),
    .wr_ready                    (cb_mem_wr_ready),
    .wr_addr                     (codebook_wr_addr),
    .wr_data                     (codebook_wr_data),
    .rd_valid                    (cb_rd_valid),
    .rd_ready                    (cb_rd_ready),
    .rd_addr                     (cb_rd_addr),
    .rd_rsp_valid                (cb_rsp_valid),
    .rd_rsp_data                 (cb_rsp_data)
);

rvq_scale_align_8lane u_scale_align (
    .codebook_data               (cb_rsp_data),
    .multiplier                  (scale_multiplier[stage]),
    .shift                       (scale_shift[stage]),
    .aligned_data                (aligned_codeword),
    .overflow                    (scale_overflow)
);

assign active_residual_group = (state == S_UPDATE) ?
    residual_mem[update_rsp_group] :
    residual_mem[search_rsp_group];
rvq_distance_8lane u_distance (
    .residual_data               (active_residual_group),
    .codeword_data               (aligned_codeword),
    .group_distance              (group_distance)
);

rvq_residual_update_8lane u_residual_update (
    .residual_data               (active_residual_group),
    .codeword_data               (aligned_codeword),
    .residual_next               (updated_residual_group),
    .overflow                    (residual_overflow)
);

// 把INT8 latent符号扩展成INT16 Residual初值。

always @(*) begin
    latent_expanded = 128'd0;
    for (lane = 0; lane < 8; lane = lane + 1)
        latent_expanded[16*lane +: 16] =
        {{8{latent_data[8*lane+7]}},latent_data[8*lane +: 8]};
end

// UINT32距离采用饱和加法，防止配置错误时无符号回绕。

always @(*) begin
    distance_sum_ext = {4'd0,distance_acc} + {1'b0,group_distance};
    if (distance_sum_ext[35:32] != 4'd0) begin
        distance_after_group = 32'hffff_ffff;
        distance_overflow = 1'b1;
    end else begin
        distance_after_group = distance_sum_ext[31:0];
        distance_overflow = 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= S_LOAD;
        input_group         <= 3'd0;
        stage               <= 3'd0;
        search_issue_count  <= 12'd0;
        search_rsp_group    <= 3'd0;
        search_rsp_index    <= 8'd0;
        distance_acc        <= 32'd0;
        min_distance        <= 32'hffff_ffff;
        best_index          <= 8'd0;
        update_issue_count  <= 4'd0;
        update_rsp_group    <= 3'd0;
        result_valid        <= 1'b0;
        result_indices      <= 64'd0;
        error               <= 1'b0;
        for (cfg_i = 0; cfg_i < 8; cfg_i = cfg_i + 1) begin
            scale_multiplier[cfg_i] <= 32'd1;
            scale_shift[cfg_i]      <= 6'd0;
        end
    end else begin

        // Scale配置只在空闲/latent装载阶段接收。
        if (scale_cfg_valid && scale_cfg_ready) begin
            scale_multiplier[scale_cfg_stage] <= scale_cfg_multiplier;
            scale_shift[scale_cfg_stage]      <= scale_cfg_shift;
        end
        case (state)

            // 输入阶段：只在输入握手成功时接收 latent，写入残差工作区。
            S_LOAD: begin
                if (latent_valid && latent_ready) begin
                    residual_mem[input_group] <= latent_expanded;

                    // last必须与固定的第8拍严格对齐。
                    if (latent_last != (input_group == 3'd7))
                        error <= 1'b1;
                    if (input_group == 3'd7) begin
                        input_group        <= 3'd0;
                        stage              <= 3'd0;
                        search_issue_count <= 12'd0;
                        search_rsp_group   <= 3'd0;
                        search_rsp_index   <= 8'd0;
                        distance_acc       <= 32'd0;
                        min_distance       <= 32'hffff_ffff;
                        best_index         <= 8'd0;
                        result_indices     <= 64'd0;
                        state              <= S_SEARCH;
                    end else begin
                        input_group <= input_group + 1'b1;
                    end
                end
            end

            // 搜索阶段：扫描当前级码字，累计各维距离，保留最小距离及索引。
            S_SEARCH: begin

                // 同步SRAM允许连续发请求；响应严格保持请求顺序。
                if (cb_rd_valid && cb_rd_ready)
                    search_issue_count <= search_issue_count + 1'b1;
                if (cb_rsp_valid) begin
                    if (scale_overflow)
                        error <= 1'b1;
                    if (distance_overflow)
                        error <= 1'b1;
                    if (search_rsp_group == 3'd7) begin

                        // 64维距离完成。严格小于保证相同距离选择较小index。
                        if (distance_after_group < min_distance) begin
                            min_distance <= distance_after_group;
                            best_index   <= search_rsp_index;
                        end
                        distance_acc     <= 32'd0;
                        search_rsp_group <= 3'd0;
                        if (search_rsp_index == 8'hff) begin
                            update_issue_count <= 4'd0;
                            update_rsp_group   <= 3'd0;
                            state              <= S_UPDATE;
                        end else begin
                            search_rsp_index <= search_rsp_index + 1'b1;
                        end
                    end else begin
                        distance_acc     <= distance_after_group;
                        search_rsp_group <= search_rsp_group + 1'b1;
                    end
                end
            end

            // 更新阶段：用本级获胜码字更新残差，供下一级继续量化。
            S_UPDATE: begin
                if (cb_rd_valid && cb_rd_ready)
                    update_issue_count <= update_issue_count + 1'b1;
                if (cb_rsp_valid) begin
                    residual_mem[update_rsp_group] <= updated_residual_group;
                    if (scale_overflow || residual_overflow)
                        error <= 1'b1;
                    if (update_rsp_group == 3'd7) begin
                        result_indices[8*stage +: 8] <= best_index;
                        update_rsp_group <= 3'd0;
                        if (stage == 3'd7) begin
                            result_valid <= 1'b1;
                            state        <= S_OUTPUT;
                        end else begin
                            stage               <= stage + 1'b1;
                            search_issue_count  <= 12'd0;
                            search_rsp_group    <= 3'd0;
                            search_rsp_index    <= 8'd0;
                            distance_acc        <= 32'd0;
                            min_distance        <= 32'hffff_ffff;
                            best_index          <= 8'd0;
                            state               <= S_SEARCH;
                        end
                    end else begin
                        update_rsp_group <= update_rsp_group + 1'b1;
                    end
                end
            end

            // 输出阶段：完整索引已就绪；等待 result_valid/ready 握手。
            // 搜索过程中看到的 result_indices 只是尚未完成的中间内容。
            S_OUTPUT: begin

                // valid和data在ready=0时保持稳定。
                if (result_valid && result_ready) begin
                    result_valid <= 1'b0;
                    state        <= S_LOAD;
                end
            end
            default: begin
                state <= S_LOAD;
                error <= 1'b1;
            end
        endcase
    end
end

endmodule
