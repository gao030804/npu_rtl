`timescale 1ns/1ps

//=============================================================================
// 63层SoundStream Encoder + 8级RVQ完整帧自检testbench
//
// 验证边界：
//   320点PCM16 -> PCM INT8量化 -> 63层逐byte对拍 -> 64维latent对拍
//   -> RVQ输入对拍 -> 8个UINT8 index对拍。
// Golden全部由Python预先生成；本testbench只负责激励、协议监视和记分板。
//=============================================================================
module tb_soundstream_encoder_rvq_full_frame;

localparam integer NUM_LAYERS       = 63;
localparam integer GOLDEN_STRIDE     = 8192;
localparam integer GOLDEN_BYTES      = NUM_LAYERS * GOLDEN_STRIDE;
localparam integer EXPECTED_BYTES    = 139136;
localparam integer MAX_TEST_CYCLES   = 100000000;
localparam [31:0] BUFFER_A_BASE      = 32'h0000_1000;
localparam [31:0] BUFFER_B_BASE      = 32'h0000_3000;
localparam [63:0] EXPECTED_INDICES   = 64'h0a09_0807_0605_0403;

reg clk, rst_n, frame_start;
wire frame_start_ready, frame_busy, frame_done, error;
reg pcm_valid;
wire pcm_ready;
reg signed [15:0] pcm_data;
reg [15:0] pcm_memory [0:319];
reg [7:0] golden_layers [0:GOLDEN_BYTES-1];
reg [7:0] golden_latent [0:63];

wire layer_prepare_valid;
reg layer_prepare_ready;
wire [5:0] physical_layer, logical_layer;
reg elu_lut_cfg_valid;
wire elu_lut_cfg_ready;
reg [6:0] elu_lut_cfg_addr;
reg [7:0] elu_lut_cfg_wdata;
wire param_rd_req_valid;
reg param_rd_req_ready, param_rd_rsp_valid;
wire param_rd_rsp_ready;

reg rvq_scale_cfg_valid;
wire rvq_scale_cfg_ready;
reg [2:0] rvq_scale_cfg_stage;
reg [31:0] rvq_scale_cfg_multiplier;
reg [5:0] rvq_scale_cfg_shift;
reg rvq_codebook_wr_valid;
wire rvq_codebook_wr_ready;
reg [13:0] rvq_codebook_wr_addr;
reg [63:0] rvq_codebook_wr_data;
reg rvq_config_done;
wire encoded_valid;
reg encoded_ready;
wire [63:0] encoded_indices;

wire flash_csn, flash_sclk;
tri flash_mosi, flash_miso, flash_wp, flash_hold;
wire octal_cmd_valid, octal_rx_ready;
wire [23:0] octal_cmd_flash_base, octal_cmd_byte_count;
wire [3:0] control_state_debug;
wire [2:0] latent_group_debug;

integer cycle_count, errors, pcm_index, pcm_compare_count;
integer activation_compare_count, latent_compare_count, completed_layers;
integer lane, offset, golden_index, current_layer;
integer actual_bytes [0:NUM_LAYERS-1];
integer expected_layer_bytes [0:NUM_LAYERS-1];
integer weight_reads [0:NUM_LAYERS-1];
integer expected_weight_reads [0:NUM_LAYERS-1];
integer layer_start_errors [0:NUM_LAYERS-1];
integer start_cycle [0:NUM_LAYERS-1];
reg result_seen;
reg [63:0] captured_indices;

assign flash_miso = 1'b1;
assign flash_wp   = 1'b1;
assign flash_hold = 1'b1;

soundstream_encoder_rvq_top #(
    .USE_GLOBAL_WEIGHT_HIERARCHY (0),
    .FAST_SIM_WEIGHT_CACHE       (1)
) u_dut (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
    .frame_start_ready(frame_start_ready), .frame_busy(frame_busy),
    .frame_done(frame_done), .error(error),
    .pcm_valid(pcm_valid), .pcm_ready(pcm_ready), .pcm_data(pcm_data),
    .pcm_multiplier(32'sd1), .pcm_shift(6'd8), .pcm_zero_point(8'sd0),
    .layer_prepare_valid(layer_prepare_valid),
    .layer_prepare_ready(layer_prepare_ready),
    .physical_layer(physical_layer), .logical_layer(logical_layer),
    .elu_lut_cfg_valid(elu_lut_cfg_valid),
    .elu_lut_cfg_ready(elu_lut_cfg_ready),
    .elu_lut_cfg_addr(elu_lut_cfg_addr),
    .elu_lut_cfg_wdata(elu_lut_cfg_wdata),
    .param_rd_req_valid(param_rd_req_valid),
    .param_rd_req_ready(param_rd_req_ready),
    .param_rd_layer(), .param_rd_output_group(),
    .param_rd_rsp_valid(param_rd_rsp_valid),
    .param_rd_rsp_ready(param_rd_rsp_ready),
    .param_bias_data(256'd0), .param_mult_data({8{32'd1}}),
    .param_shift_data(48'd0), .param_zero_point_data(64'd0),
    .rvq_scale_cfg_valid(rvq_scale_cfg_valid),
    .rvq_scale_cfg_ready(rvq_scale_cfg_ready),
    .rvq_scale_cfg_stage(rvq_scale_cfg_stage),
    .rvq_scale_cfg_multiplier(rvq_scale_cfg_multiplier),
    .rvq_scale_cfg_shift(rvq_scale_cfg_shift),
    .rvq_codebook_wr_valid(rvq_codebook_wr_valid),
    .rvq_codebook_wr_ready(rvq_codebook_wr_ready),
    .rvq_codebook_wr_addr(rvq_codebook_wr_addr),
    .rvq_codebook_wr_data(rvq_codebook_wr_data),
    .rvq_config_done(rvq_config_done),
    .encoded_valid(encoded_valid), .encoded_ready(encoded_ready),
    .encoded_indices(encoded_indices),
    .flash_csn(flash_csn), .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi), .flash_miso(flash_miso),
    .flash_wp(flash_wp), .flash_hold(flash_hold),
    .octal_cmd_valid(octal_cmd_valid), .octal_cmd_ready(1'b0),
    .octal_cmd_flash_base(octal_cmd_flash_base),
    .octal_cmd_byte_count(octal_cmd_byte_count),
    .octal_phy_clk(clk), .octal_phy_rst_n(rst_n),
    .octal_rx_valid(1'b0), .octal_rx_ready(octal_rx_ready),
    .octal_rx_data(16'd0), .octal_rx_last(1'b0), .octal_rx_error(1'b0),
    .control_state_debug(control_state_debug),
    .latent_group_debug(latent_group_debug)
);

always #5 clk = ~clk;

// PCM源严格遵循valid/ready：只有握手后才递增样本号。
always @(*) begin
    pcm_valid = frame_busy && (pcm_index < 320);
    pcm_data  = (pcm_index < 320) ? pcm_memory[pcm_index] : 16'sd0;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pcm_index   <= 0;
        cycle_count <= 0;
    end else begin
        cycle_count <= cycle_count + 1;
        if (pcm_valid && pcm_ready)
            pcm_index <= pcm_index + 1;
    end
end

// Parameter SRAM采用一拍请求/响应模型，参数使Requant成为恒等映射。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        param_rd_req_ready <= 1'b1;
        param_rd_rsp_valid <= 1'b0;
    end else begin
        if (param_rd_rsp_valid && param_rd_rsp_ready) begin
            param_rd_rsp_valid <= 1'b0;
            param_rd_req_ready <= 1'b1;
        end
        if (param_rd_req_valid && param_rd_req_ready) begin
            param_rd_req_ready <= 1'b0;
            param_rd_rsp_valid <= 1'b1;
        end
    end
end

// 监视PCM前端真正写入Activation SRAM的数据。
always @(posedge clk) begin
    if (rst_n && u_dut.pcm_wr_valid && u_dut.pcm_wr_ready) begin
        offset = u_dut.pcm_wr_addr - BUFFER_A_BASE;
        for (lane=0; lane<8; lane=lane+1)
            if (u_dut.pcm_wr_strb[lane]) begin
                if (u_dut.pcm_wr_data[8*lane +: 8] !==
                    pcm_memory[offset+lane][15:8]) begin
                    $display("[ERROR] PCM byte=%0d expected=%02h actual=%02h",
                        offset+lane, pcm_memory[offset+lane][15:8],
                        u_dut.pcm_wr_data[8*lane +: 8]);
                    errors = errors + 1;
                end
                pcm_compare_count = pcm_compare_count + 1;
            end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        result_seen      <= 1'b0;
        captured_indices <= 64'd0;
    end else if (encoded_valid && encoded_ready) begin
        result_seen      <= 1'b1;
        captured_indices <= encoded_indices;
    end
end

// 每一次有效写回都与Python生成的对应层、对应byte Golden比较。
always @(posedge clk) begin
    if (rst_n && u_dut.layer_write_fire_unused) begin
        offset = u_dut.layer_write_addr_unused -
                 (physical_layer[0] ? BUFFER_A_BASE : BUFFER_B_BASE);
        for (lane=0; lane<8; lane=lane+1)
            if (u_dut.layer_write_strb_unused[lane]) begin
                golden_index = physical_layer * GOLDEN_STRIDE + offset + lane;
                if ((offset < 0) || (offset + lane >= GOLDEN_STRIDE) ||
                    (u_dut.layer_write_data_unused[8*lane +: 8] !==
                     golden_layers[golden_index])) begin
                    if (errors < 40)
                        $display("[ERROR] layer=%0d byte=%0d expected=%02h actual=%02h",
                            physical_layer, offset+lane, golden_layers[golden_index],
                            u_dut.layer_write_data_unused[8*lane +: 8]);
                    errors = errors + 1;
                end
                actual_bytes[physical_layer] = actual_bytes[physical_layer] + 1;
                activation_compare_count = activation_compare_count + 1;
            end
    end
end

// 逐层检查输出数量、权重块读取数量，并打印每层计算周期。
always @(posedge clk) begin
    if (rst_n && u_dut.perf_engine_start_unused) begin
        current_layer = physical_layer;
        start_cycle[current_layer] = cycle_count;
        expected_layer_bytes[current_layer] =
            u_dut.u_encoder.cfg_cout * u_dut.u_encoder.cfg_output_length;
        // Dense/Pointwise权重先装入Mesh并在所有m位置复用，因此每块只读一次。
        // 当前Depthwise控制器按输出位置m重新装载本层权重，读取次数还要乘Lout。
        expected_weight_reads[current_layer] =
            u_dut.u_encoder.cfg_is_depthwise ?
            (u_dut.u_encoder.cfg_weight_blocks *
             u_dut.u_encoder.cfg_output_length) :
            u_dut.u_encoder.cfg_weight_blocks;
        layer_start_errors[current_layer] = errors;
    end
    if (rst_n && u_dut.perf_weight_read_unused)
        weight_reads[physical_layer] = weight_reads[physical_layer] + 1;
    if (rst_n && u_dut.perf_engine_done_unused) begin
        completed_layers = completed_layers + 1;
        if ((actual_bytes[physical_layer] != expected_layer_bytes[physical_layer]) ||
            (weight_reads[physical_layer] != expected_weight_reads[physical_layer]) ||
            (errors != layer_start_errors[physical_layer])) begin
            $display("[LAYER_FAIL] layer=%0d bytes=%0d/%0d reads=%0d/%0d",
                physical_layer, actual_bytes[physical_layer],
                expected_layer_bytes[physical_layer], weight_reads[physical_layer],
                expected_weight_reads[physical_layer]);
            errors = errors + 1;
        end else begin
            $display("[LAYER_PASS] layer=%0d bytes=%0d weight_blocks=%0d cycles=%0d",
                physical_layer, actual_bytes[physical_layer],
                weight_reads[physical_layer], cycle_count-start_cycle[physical_layer]);
        end
    end
end

// 检查Encoder交给RVQ的8个64-bit组是否正好组成Golden latent。
always @(posedge clk) begin
    if (rst_n && u_dut.rvq_latent_valid && u_dut.rvq_latent_ready) begin
        for (lane=0; lane<8; lane=lane+1) begin
            offset = latent_group_debug * 8 + lane;
            if (u_dut.latent_word[8*lane +: 8] !== golden_latent[offset]) begin
                $display("[ERROR] RVQ latent byte=%0d expected=%02h actual=%02h",
                    offset, golden_latent[offset], u_dut.latent_word[8*lane +: 8]);
                errors = errors + 1;
            end
            latent_compare_count = latent_compare_count + 1;
        end
    end
end

task write_scale;
    input [2:0] stage_no;
    begin
        @(negedge clk); rvq_scale_cfg_stage=stage_no;
        rvq_scale_cfg_multiplier=1; rvq_scale_cfg_shift=0;
        rvq_scale_cfg_valid=1;
        while (!rvq_scale_cfg_ready) @(negedge clk);
        @(posedge clk); @(negedge clk); rvq_scale_cfg_valid=0;
    end
endtask

task write_codebook_word;
    input [13:0] address;
    input [63:0] data;
    begin
        @(negedge clk); rvq_codebook_wr_addr=address;
        rvq_codebook_wr_data=data; rvq_codebook_wr_valid=1;
        while (!rvq_codebook_wr_ready) @(negedge clk);
        @(posedge clk); @(negedge clk); rvq_codebook_wr_valid=0;
    end
endtask

integer i, stage_no, index_no, group_no;
reg [63:0] target_word;
initial begin
    clk=0; rst_n=0; frame_start=0; layer_prepare_ready=1;
    elu_lut_cfg_valid=0; elu_lut_cfg_addr=0; elu_lut_cfg_wdata=0;
    rvq_scale_cfg_valid=0; rvq_scale_cfg_stage=0;
    rvq_scale_cfg_multiplier=1; rvq_scale_cfg_shift=0;
    rvq_codebook_wr_valid=0; rvq_codebook_wr_addr=0; rvq_codebook_wr_data=0;
    rvq_config_done=0; encoded_ready=1;
    errors=0; pcm_index=0; pcm_compare_count=0; activation_compare_count=0;
    latent_compare_count=0; completed_layers=0;
    for (i=0;i<NUM_LAYERS;i=i+1) begin
        actual_bytes[i]=0; expected_layer_bytes[i]=0; weight_reads[i]=0;
        expected_weight_reads[i]=0; layer_start_errors[i]=0; start_cycle[i]=0;
    end
    $readmemh("tb/data/full_encoder_rvq/pcm_frame.hex", pcm_memory);
    $readmemh("tb/data/full_encoder_rvq/golden_layers.mem", golden_layers);
    $readmemh("tb/data/full_encoder_rvq/golden_latent.hex", golden_latent);
    repeat(8) @(posedge clk); rst_n=1;

    for (stage_no=0; stage_no<8; stage_no=stage_no+1)
        write_scale(stage_no[2:0]);

    // 默认码字全部置20；随后写入每一级唯一的零距离目标码字。
    for (stage_no=0; stage_no<8; stage_no=stage_no+1)
        for (index_no=0; index_no<256; index_no=index_no+1)
            for (group_no=0; group_no<8; group_no=group_no+1)
                write_codebook_word({stage_no[2:0],index_no[7:0],group_no[2:0]},
                                    {8{8'd20}});
    for (group_no=0; group_no<8; group_no=group_no+1) begin
        target_word=0;
        for (lane=0; lane<8; lane=lane+1)
            target_word[8*lane +: 8]=golden_latent[group_no*8+lane];
        write_codebook_word({3'd0,8'd3,group_no[2:0]},target_word);
    end
    for (stage_no=1; stage_no<8; stage_no=stage_no+1)
        for (group_no=0; group_no<8; group_no=group_no+1)
            write_codebook_word(stage_no*2048+(stage_no+3)*8+group_no,64'd0);

    @(negedge clk); rvq_config_done=1; @(posedge clk);
    @(negedge clk); rvq_config_done=0;
    while (!frame_start_ready) @(posedge clk);
    @(negedge clk); frame_start=1; @(posedge clk);
    @(negedge clk); frame_start=0;
    while (!frame_done && (cycle_count < MAX_TEST_CYCLES)) @(posedge clk);

    if (!frame_done) begin $display("[ERROR] timeout"); errors=errors+1; end
    if (error) begin $display("[ERROR] DUT error asserted"); errors=errors+1; end
    if (pcm_compare_count != 320) begin
        $display("[ERROR] PCM comparisons=%0d expected=320",pcm_compare_count);
        errors=errors+1;
    end
    if (completed_layers != NUM_LAYERS) begin
        $display("[ERROR] completed_layers=%0d expected=63",completed_layers);
        errors=errors+1;
    end
    if (activation_compare_count != EXPECTED_BYTES) begin
        $display("[ERROR] activation comparisons=%0d expected=%0d",
                 activation_compare_count,EXPECTED_BYTES); errors=errors+1;
    end
    if (latent_compare_count != 64) begin
        $display("[ERROR] latent comparisons=%0d expected=64",latent_compare_count);
        errors=errors+1;
    end
    if (!result_seen || (captured_indices !== EXPECTED_INDICES)) begin
        $display("[ERROR] RVQ indices expected=%h actual=%h",
                 EXPECTED_INDICES,captured_indices); errors=errors+1;
    end
    if (errors==0)
        $display("[TB_PASS] PCM320 + 63 layers + latent64 + RVQ8 all passed");
    else
        $display("[TB_FAIL] errors=%0d",errors);
    $finish;
end

endmodule
