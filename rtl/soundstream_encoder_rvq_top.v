`timescale 1ns/1ps

//=============================================================================
// 模块：soundstream_encoder_rvq_top
// 功能：PCM16 -> INT8 -> 多层Conv1d Encoder -> 1x64 latent -> 8级RVQ。
//
// 一帧控制顺序：
//   C_IDLE       等待码本/Scale配置完成并接受frame_start；
//   C_PCM        接收固定数量PCM16，量化并写Activation SRAM；
//   C_ENC_WAIT   等待Flash权重上电搬运完成；
//   C_ENCODE     执行完整卷积层调度；
//   C_RD_*       从最终Activation Buffer读取64维INT8 latent；
//   C_RVQ_SEND   每拍向RVQ提交8维；
//   C_RVQ_WAIT   等待8个UINT8索引并通过valid/ready输出。
//=============================================================================

// -------------------------------------------------------------------------
// 详细阅读说明：
// - 系统帧级入口。frame_start只在frame_start_ready=1时接受；一帧执行期间frame_busy保持为1。
// - 数据顺序为PCM采集、Encoder等待权重、63层卷积、分8组读取64维latent、启动8级RVQ、输出64-bit索引。
// - encoded_valid受encoded_ready反压；等待期间encoded_indices必须保持不变。
// -------------------------------------------------------------------------
module soundstream_encoder_rvq_top #(
    parameter ADDR_WIDTH                  = 32,
    parameter PCM_SAMPLES_PER_FRAME       = 320,
    parameter BUFFER_A_BASE               = 32'h0000_1000,
    parameter BUFFER_B_BASE               = 32'h0000_3000,
    parameter FLASH_QSPI_HALF_DIV         = 16'd1,
    parameter USE_GLOBAL_WEIGHT_HIERARCHY = 1,
    parameter GLOBAL_DEPTH_BLOCKS         = 8192,
    parameter GLOBAL_INDEX_WIDTH          = 13,
    parameter GLOBAL_MODEL_BLOCKS         = 5084,
    parameter FAST_SIM_WEIGHT_CACHE       = 0
) (
    input                                       clk,
    input                                       rst_n,
    input                                       frame_start,
    output                                      frame_start_ready,
    output                                      frame_busy,
    output reg                                  frame_done,
    output reg                                  error,

    // 原始PCM输入及PCM16->INT8量化参数。
    input                                       pcm_valid,
    output                                      pcm_ready,
    input       signed [15:0]                   pcm_data,
    input       signed [31:0]                   pcm_multiplier,
    input              [5:0]                    pcm_shift,
    input       signed [7:0]                    pcm_zero_point,

    // 每层参数准备和Parameter SRAM接口。
    output                                      layer_prepare_valid,
    input                                       layer_prepare_ready,
    output             [5:0]                    physical_layer,
    output             [5:0]                    logical_layer,
    input                                       elu_lut_cfg_valid,
    output                                      elu_lut_cfg_ready,
    input              [6:0]                    elu_lut_cfg_addr,
    input              [7:0]                    elu_lut_cfg_wdata,
    output                                      param_rd_req_valid,
    input                                       param_rd_req_ready,
    output             [5:0]                    param_rd_layer,
    output             [5:0]                    param_rd_output_group,
    input                                       param_rd_rsp_valid,
    output                                      param_rd_rsp_ready,
    input              [255:0]                  param_bias_data,
    input              [255:0]                  param_mult_data,
    input              [47:0]                   param_shift_data,
    input              [63:0]                   param_zero_point_data,

    // RVQ部署配置：8级Scale和128 KiB码本应在rvq_config_done前写完。
    input                                       rvq_scale_cfg_valid,
    output                                      rvq_scale_cfg_ready,
    input              [2:0]                    rvq_scale_cfg_stage,
    input              [31:0]                   rvq_scale_cfg_multiplier,
    input              [5:0]                    rvq_scale_cfg_shift,
    input                                       rvq_codebook_wr_valid,
    output                                      rvq_codebook_wr_ready,
    input              [13:0]                   rvq_codebook_wr_addr,
    input              [63:0]                   rvq_codebook_wr_data,
    input                                       rvq_config_done,

    // 最终码流：index[8*stage +:8]，stage0位于最低字节。
    output                                      encoded_valid,
    input                                       encoded_ready,
    output             [63:0]                   encoded_indices,

    // P25Q32H QSPI接口。
    output                                      flash_csn,
    output                                      flash_sclk,
    inout                                       flash_mosi,
    inout                                       flash_miso,
    inout                                       flash_wp,
    inout                                       flash_hold,

    // 保留现有Octal接口；本顶层默认不选用。
    output                                      octal_cmd_valid,
    input                                       octal_cmd_ready,
    output             [23:0]                   octal_cmd_flash_base,
    output             [23:0]                   octal_cmd_byte_count,
    input                                       octal_phy_clk,
    input                                       octal_phy_rst_n,
    input                                       octal_rx_valid,
    output                                      octal_rx_ready,
    input              [15:0]                   octal_rx_data,
    input                                       octal_rx_last,
    input                                       octal_rx_error,
    output             [3:0]                    control_state_debug,
    output             [2:0]                    latent_group_debug
);

localparam [3:0]
C_IDLE       = 4'd0,
C_PCM        = 4'd1,
C_ENC_WAIT   = 4'd2,
C_ENC_START  = 4'd3,
C_ENCODE     = 4'd4,
C_RD_LO_REQ  = 4'd5,
C_RD_LO_WAIT = 4'd6,
C_RD_HI_REQ  = 4'd7,
C_RD_HI_WAIT = 4'd8,
C_RVQ_SEND   = 4'd9,
C_RVQ_WAIT   = 4'd10,
C_ERROR      = 4'd11;
reg [3:0] state;
reg [2:0] latent_group;
reg [63:0] latent_word;
reg rvq_configured;
wire pcm_start = frame_start && frame_start_ready;
wire pcm_busy;
wire pcm_done;
wire pcm_wr_valid;
wire pcm_wr_ready;
wire [ADDR_WIDTH-1:0] pcm_wr_addr;
wire [63:0] pcm_wr_data;
wire [7:0] pcm_wr_strb;
wire encoder_start_ready;
wire encoder_busy;
wire encoder_done;
wire encoder_error;
wire encoder_start = (state == C_ENC_START);
wire input_buffer_select_unused;
wire [ADDR_WIDTH-1:0] input_buffer_base;
wire result_buffer_select_unused;
wire [ADDR_WIDTH-1:0] result_buffer_base;
wire result_rd_req_ready;
wire result_rd_rsp_valid;
wire [31:0] result_rd_data;
wire result_rd_req_valid = (state == C_RD_LO_REQ) ||
    (state == C_RD_HI_REQ);
wire result_rd_rsp_ready = (state == C_RD_LO_WAIT) ||
    (state == C_RD_HI_WAIT);
wire [ADDR_WIDTH-1:0] latent_byte_base =
    result_buffer_base + {26'd0, latent_group, 3'b000};
wire high_half = (state == C_RD_HI_REQ) || (state == C_RD_HI_WAIT);
wire [ADDR_WIDTH-1:0] read_half_base = latent_byte_base +
    (high_half ? 32'd4 : 32'd0);
wire rvq_latent_ready;
wire rvq_result_valid;
wire [63:0] rvq_result_indices;
wire rvq_busy;
wire rvq_error;
wire rvq_scale_cfg_ready_core;
wire rvq_codebook_wr_ready_core;
wire rvq_latent_valid = (state == C_RVQ_SEND);
wire rvq_latent_last = (latent_group == 3'd7);
wire layer_write_fire_unused;
wire [ADDR_WIDTH-1:0] layer_write_addr_unused;
wire [63:0] layer_write_data_unused;
wire [7:0] layer_write_strb_unused;
wire perf_engine_start_unused;
wire perf_engine_done_unused;
wire perf_weight_read_unused;
wire perf_prefetch_fire_unused;
wire perf_prefetch_done_unused;
wire [23:0] perf_prefetch_base_unused;
wire [15:0] perf_prefetch_blocks_unused;
assign frame_start_ready = (state == C_IDLE) && rvq_configured;
assign frame_busy = (state != C_IDLE);

// 配置只允许在帧空闲期修改，防止搜索过程中码本或Scale发生变化。
assign rvq_scale_cfg_ready = (state == C_IDLE) && rvq_scale_cfg_ready_core;
assign rvq_codebook_wr_ready = (state == C_IDLE) && rvq_codebook_wr_ready_core;
assign encoded_valid = (state == C_RVQ_WAIT) && rvq_result_valid;
assign encoded_indices = rvq_result_indices;
assign control_state_debug = state;
assign latent_group_debug = latent_group;
pcm16_input_frontend #(
    .ADDR_WIDTH                  (ADDR_WIDTH),
    .COUNT_WIDTH                 (16)
) u_pcm_frontend (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .start                       (pcm_start),
    .cfg_output_base             (input_buffer_base),
    // 前端计数器接口固定为16 bit；显式截取可避免工具把integer参数按32 bit连接。
    .cfg_sample_count            (PCM_SAMPLES_PER_FRAME[15:0]),
    .cfg_multiplier              (pcm_multiplier),
    .cfg_shift                   (pcm_shift),
    .cfg_zero_point              (pcm_zero_point),
    .busy                        (pcm_busy),
    .done                        (pcm_done),
    .pcm_valid                   (pcm_valid),
    .pcm_ready                   (pcm_ready),
    .pcm_data                    (pcm_data),
    .wr_valid                    (pcm_wr_valid),
    .wr_ready                    (pcm_wr_ready),
    .wr_addr                     (pcm_wr_addr),
    .wr_data                     (pcm_wr_data),
    .wr_strb                     (pcm_wr_strb)
);

soundstream_encoder_top #(
    .ADDR_WIDTH                  (ADDR_WIDTH),
    .BUFFER_A_BASE               (BUFFER_A_BASE),
    .BUFFER_B_BASE               (BUFFER_B_BASE),
    .FLASH_SPI_DIVIDER           (FLASH_QSPI_HALF_DIV),
    .USE_GLOBAL_WEIGHT_HIERARCHY (USE_GLOBAL_WEIGHT_HIERARCHY),
    .GLOBAL_DEPTH_BLOCKS         (GLOBAL_DEPTH_BLOCKS),
    .GLOBAL_INDEX_WIDTH          (GLOBAL_INDEX_WIDTH),
    .GLOBAL_MODEL_BLOCKS         (GLOBAL_MODEL_BLOCKS),
    .USE_OCTAL_STREAM_WEIGHT_CACHE (0),
    .FAST_SIM_WEIGHT_CACHE       (FAST_SIM_WEIGHT_CACHE)
) u_encoder (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .start                       (encoder_start),
    .start_ready                 (encoder_start_ready),
    .busy                        (encoder_busy),
    .done                        (encoder_done),
    .error                       (encoder_error),
    .input_wr_valid              (pcm_wr_valid),
    .input_wr_ready              (pcm_wr_ready),
    .input_wr_addr               (pcm_wr_addr),
    .input_wr_data               (pcm_wr_data),
    .input_wr_strb               (pcm_wr_strb),
    .input_buffer_select         (input_buffer_select_unused),
    .input_buffer_base           (input_buffer_base),
    .layer_prepare_valid         (layer_prepare_valid),
    .layer_prepare_ready         (layer_prepare_ready),
    .physical_layer              (physical_layer),
    .logical_layer               (logical_layer),
    .elu_lut_cfg_valid           (elu_lut_cfg_valid),
    .elu_lut_cfg_ready           (elu_lut_cfg_ready),
    .elu_lut_cfg_addr            (elu_lut_cfg_addr),
    .elu_lut_cfg_wdata           (elu_lut_cfg_wdata),
    .param_rd_req_valid          (param_rd_req_valid),
    .param_rd_req_ready          (param_rd_req_ready),
    .param_rd_layer              (param_rd_layer),
    .param_rd_output_group       (param_rd_output_group),
    .param_rd_rsp_valid          (param_rd_rsp_valid),
    .param_rd_rsp_ready          (param_rd_rsp_ready),
    .param_bias_data             (param_bias_data),
    .param_mult_data             (param_mult_data),
    .param_shift_data            (param_shift_data),
    .param_zero_point_data       (param_zero_point_data),
    .result_rd_req_valid         (result_rd_req_valid),
    .result_rd_req_ready         (result_rd_req_ready),
    .result_rd_addr0             (read_half_base),
    .result_rd_addr1             (read_half_base + 1'b1),
    .result_rd_addr2             (read_half_base + 2'd2),
    .result_rd_addr3             (read_half_base + 2'd3),
    .result_rd_mask              (4'b1111),
    .result_rd_rsp_valid         (result_rd_rsp_valid),
    .result_rd_rsp_ready         (result_rd_rsp_ready),
    .result_rd_data              (result_rd_data),
    .result_buffer_select        (result_buffer_select_unused),
    .result_buffer_base          (result_buffer_base),
    .layer_write_fire            (layer_write_fire_unused),
    .layer_write_addr            (layer_write_addr_unused),
    .layer_write_data            (layer_write_data_unused),
    .layer_write_strb            (layer_write_strb_unused),
    .perf_engine_start           (perf_engine_start_unused),
    .perf_engine_done            (perf_engine_done_unused),
    .perf_weight_sram_read_fire  (perf_weight_read_unused),
    .perf_weight_prefetch_fire   (perf_prefetch_fire_unused),
    .perf_weight_prefetch_done   (perf_prefetch_done_unused),
    .perf_weight_prefetch_base   (perf_prefetch_base_unused),
    .perf_weight_prefetch_blocks (perf_prefetch_blocks_unused),
    .flash_csn                   (flash_csn),
    .flash_sclk                  (flash_sclk),
    .flash_mosi                  (flash_mosi),
    .flash_miso                  (flash_miso),
    .flash_wp                    (flash_wp),
    .flash_hold                  (flash_hold),
    .octal_cmd_valid             (octal_cmd_valid),
    .octal_cmd_ready             (octal_cmd_ready),
    .octal_cmd_flash_base        (octal_cmd_flash_base),
    .octal_cmd_byte_count        (octal_cmd_byte_count),
    .octal_phy_clk               (octal_phy_clk),
    .octal_phy_rst_n             (octal_phy_rst_n),
    .octal_rx_valid              (octal_rx_valid),
    .octal_rx_ready              (octal_rx_ready),
    .octal_rx_data               (octal_rx_data),
    .octal_rx_last               (octal_rx_last),
    .octal_rx_error              (octal_rx_error)
);

rvq_core u_rvq (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .scale_cfg_valid             (rvq_scale_cfg_valid && (state == C_IDLE)),
    .scale_cfg_ready             (rvq_scale_cfg_ready_core),
    .scale_cfg_stage             (rvq_scale_cfg_stage),
    .scale_cfg_multiplier        (rvq_scale_cfg_multiplier),
    .scale_cfg_shift             (rvq_scale_cfg_shift),
    .codebook_wr_valid           (rvq_codebook_wr_valid && (state == C_IDLE)),
    .codebook_wr_ready           (rvq_codebook_wr_ready_core),
    .codebook_wr_addr            (rvq_codebook_wr_addr),
    .codebook_wr_data            (rvq_codebook_wr_data),
    .latent_valid                (rvq_latent_valid),
    .latent_ready                (rvq_latent_ready),
    .latent_data                 (latent_word),
    .latent_last                 (rvq_latent_last),
    .result_valid                (rvq_result_valid),
    .result_ready                (encoded_ready && (state == C_RVQ_WAIT)),
    .result_indices              (rvq_result_indices),
    .residual_debug_group        (3'd0),
    .residual_debug_data         (),
    .busy                        (rvq_busy),
    .error                       (rvq_error)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= C_IDLE;
        latent_group   <= 3'd0;
        latent_word    <= 64'd0;
        rvq_configured <= 1'b0;
        frame_done     <= 1'b0;
        error          <= 1'b0;
    end else begin
        frame_done <= 1'b0;
        if (rvq_config_done && (state == C_IDLE))
            rvq_configured <= 1'b1;
        if (encoder_error || rvq_error) begin
            error <= 1'b1;
            state <= C_ERROR;
        end else begin
            case (state)
                C_IDLE: begin
                    if (frame_start && frame_start_ready) begin
                        latent_group <= 3'd0;
                        latent_word  <= 64'd0;
                        state        <= C_PCM;
                    end
                end
                C_PCM:
                    if (pcm_done)
                    state <= C_ENC_WAIT;
                C_ENC_WAIT:
                    if (encoder_start_ready)
                    state <= C_ENC_START;
                C_ENC_START:
                    state <= C_ENCODE;
                C_ENCODE:
                    if (encoder_done) begin
                    latent_group <= 3'd0;
                    state <= C_RD_LO_REQ;
                end
                C_RD_LO_REQ:
                    if (result_rd_req_valid && result_rd_req_ready)
                    state <= C_RD_LO_WAIT;
                C_RD_LO_WAIT:
                    if (result_rd_rsp_valid && result_rd_rsp_ready) begin
                    latent_word[31:0] <= result_rd_data;
                    state <= C_RD_HI_REQ;
                end
                C_RD_HI_REQ:
                    if (result_rd_req_valid && result_rd_req_ready)
                    state <= C_RD_HI_WAIT;
                C_RD_HI_WAIT:
                    if (result_rd_rsp_valid && result_rd_rsp_ready) begin
                    latent_word[63:32] <= result_rd_data;
                    state <= C_RVQ_SEND;
                end
                C_RVQ_SEND: begin
                    if (rvq_latent_valid && rvq_latent_ready) begin
                        if (latent_group == 3'd7) begin
                            state <= C_RVQ_WAIT;
                        end else begin
                            latent_group <= latent_group + 1'b1;
                            state <= C_RD_LO_REQ;
                        end
                    end
                end
                C_RVQ_WAIT: begin
                    if (encoded_valid && encoded_ready) begin
                        frame_done <= 1'b1;
                        state <= C_IDLE;
                    end
                end
                C_ERROR:
                    state <= C_ERROR;
                default: begin
                    error <= 1'b1;
                    state <= C_ERROR;
                end
            endcase
        end
    end
end

endmodule
