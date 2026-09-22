`timescale 1ns/1ps

//=============================================================================
// 63层Encoder + 64→32 Projection + 9级非均匀RVQ完整帧自检testbench
//
// 验证边界：
//   320点PCM16 -> PCM INT8量化 -> 63层逐byte对拍 -> 64维latent对拍
//   -> Projection输入对拍 -> 9级RVQ紧凑64-bit index对拍。
// Golden全部由Python预先生成；本testbench只负责激励、协议监视和记分板。
//=============================================================================
// [中文注释-自动补充]
// 模块作用：Encoder+RVQ完整帧自检Testbench。
// 关键变量/接口：驱动PCM/参数/码本，逐byte比较63层结果和latent，并检查权重读次数与最终RVQ索引。
// 握手约定：valid与ready在同一上升沿同时为1才完成一次传输；反压期间数据必须保持。
// 位宽约定：地址通常按Byte计，Weight块为256 bit，Activation/Weight基本元素为signed INT8。
// -----------------------------------------------------------------------------
module tb_soundstream_encoder_rvq_full_frame;

localparam integer NUM_LAYERS       = 63;
localparam integer GOLDEN_STRIDE     = 8192;
localparam integer GOLDEN_BYTES      = NUM_LAYERS * GOLDEN_STRIDE;
localparam integer EXPECTED_BYTES    = 139136;
localparam integer MAX_TEST_CYCLES   = 100000000;
localparam integer CLOCK_PERIOD_NS   = 10;       // 100 MHz系统时钟
localparam integer FRAME_AUDIO_US    = 20000;    // 320 sample对应20 ms音频帧
localparam integer FRAME_BUDGET_CYCLES =
    (FRAME_AUDIO_US * 1000) / CLOCK_PERIOD_NS;
localparam [31:0] BUFFER_A_BASE      = 32'h0000_1000;
localparam [31:0] BUFFER_B_BASE      = 32'h0000_3000;
localparam [63:0] EXPECTED_INDICES   = 64'h1628_4880_e182_8403;

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
reg [3:0] rvq_scale_cfg_stage;
reg [31:0] rvq_scale_cfg_multiplier;
reg [5:0] rvq_scale_cfg_shift;
reg rvq_codebook_wr_valid;
wire rvq_codebook_wr_ready;
reg [13:0] rvq_codebook_wr_addr;
reg [63:0] rvq_codebook_wr_data;
reg rvq_config_done;
reg projection_wr_valid;
wire projection_wr_ready;
reg [7:0] projection_wr_addr;
reg [63:0] projection_wr_data;
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
integer frame_accept_cycle, pcm_done_cycle;
integer encoder_start_cycle, encoder_done_cycle;
integer projection_start_cycle, encoded_result_cycle;
integer frame_total_cycles, pcm_stage_cycles;
integer encoder_stage_cycles, projection_rvq_cycles;
integer realtime_margin_cycles, realtime_util_percent;
integer actual_bytes [0:NUM_LAYERS-1];
integer expected_layer_bytes [0:NUM_LAYERS-1];
integer weight_reads [0:NUM_LAYERS-1];
integer expected_weight_reads [0:NUM_LAYERS-1];
integer layer_start_errors [0:NUM_LAYERS-1];
integer start_cycle [0:NUM_LAYERS-1];
reg result_seen;
reg [63:0] captured_indices;

// 连续赋值：组合生成flash_miso及其相邻接口信号，表达握手、选择或地址关系。
assign flash_miso = 1'b1;
assign flash_wp   = 1'b1;
// 连续赋值：组合生成flash_hold及其相邻接口信号，表达握手、选择或地址关系。
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
    .projection_wr_valid(projection_wr_valid),
    .projection_wr_ready(projection_wr_ready),
    .projection_wr_addr(projection_wr_addr),
    .projection_wr_data(projection_wr_data),
    .projection_multiplier(32'sd1), .projection_shift(6'd0),
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
// 组合逻辑：根据当前输入计算pcm_valid、pcm_data、offset、lane、byte、expected；本逻辑块不保存跨周期状态。
always @(*) begin
    pcm_valid = frame_busy && (pcm_index < 320);
    pcm_data  = (pcm_index < 320) ? pcm_memory[pcm_index] : 16'sd0;
end
// 时序逻辑：在时钟沿更新pcm_index、cycle_count、param_rd_req_ready、param_rd_rsp_valid；复位分支负责恢复确定的空闲状态。
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

// 帧级性能计数器：只统计frame_start握手之后的一帧运行时间。
// RVQ Scale、Projection矩阵和Codebook的上电配置发生在frame_start之前，
// 属于初始化时间，因此不计入每帧编码延迟。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_accept_cycle    <= -1;
        pcm_done_cycle        <= -1;
        encoder_start_cycle   <= -1;
        encoder_done_cycle    <= -1;
        projection_start_cycle<= -1;
        encoded_result_cycle  <= -1;
    end else begin
        if (frame_start && frame_start_ready)
            frame_accept_cycle <= cycle_count;
        if (u_dut.pcm_done)
            pcm_done_cycle <= cycle_count;
        if (u_dut.encoder_start)
            encoder_start_cycle <= cycle_count;
        if (u_dut.encoder_done)
            encoder_done_cycle <= cycle_count;
        if (u_dut.projection_in_valid && u_dut.projection_in_ready &&
            (projection_start_cycle < 0))
            projection_start_cycle <= cycle_count;
        if (encoded_valid && encoded_ready)
            encoded_result_cycle <= cycle_count;
    end
end

// Parameter SRAM采用一拍请求/响应模型，参数使Requant成为恒等映射。
// 时序逻辑：在时钟沿更新param_rd_req_ready、param_rd_rsp_valid、result_seen、captured_indices；复位分支负责恢复确定的空闲状态。
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
// 时序逻辑：在时钟沿更新result_seen、captured_indices；复位分支负责恢复确定的空闲状态。
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

// 时序逻辑：在时钟沿更新result_seen、captured_indices；复位分支负责恢复确定的空闲状态。
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
// 时序逻辑：在时钟沿更新状态寄存器和流水寄存器；复位分支负责恢复确定的空闲状态。
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
// 时序逻辑：在时钟沿更新状态寄存器和流水寄存器；复位分支负责恢复确定的空闲状态。
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

// 检查Encoder交给Projection-In的8个64-bit组是否正好组成Golden latent。
// 时序逻辑：在时钟沿更新状态寄存器和流水寄存器；复位分支负责恢复确定的空闲状态。
always @(posedge clk) begin
    if (rst_n && u_dut.projection_in_valid && u_dut.projection_in_ready) begin
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

// 辅助过程write_scale：封装重复计算或测试激励，便于独立检查输入、输出及边界条件。
task write_scale;
    input [3:0] stage_no;
    begin
        @(negedge clk); rvq_scale_cfg_stage=stage_no;
        rvq_scale_cfg_multiplier=1; rvq_scale_cfg_shift=0;
        rvq_scale_cfg_valid=1;
        while (!rvq_scale_cfg_ready) @(negedge clk);
        @(posedge clk); @(negedge clk); rvq_scale_cfg_valid=0;
    end
endtask

task write_projection_word;
    input [7:0] address; input [63:0] data;
    begin
        @(negedge clk); projection_wr_addr=address; projection_wr_data=data; projection_wr_valid=1;
        while(!projection_wr_ready) @(negedge clk);
        @(posedge clk); @(negedge clk); projection_wr_valid=0;
    end
endtask

// 辅助过程write_codebook_word：封装重复计算或测试激励，便于独立检查输入、输出及边界条件。
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
    projection_wr_valid=0; projection_wr_addr=0; projection_wr_data=0;
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

    // 64->32投影采用前32维单位选择矩阵。
    for (i=0;i<256;i=i+1) begin
        target_word=0;
        if ((i&7)==((i>>3)>>3)) target_word[8*((i>>3)&7)+:8]=8'd1;
        write_projection_word(i[7:0],target_word);
    end
    for (stage_no=0; stage_no<9; stage_no=stage_no+1)
        write_scale(stage_no[3:0]);

    // 默认码字全部置20；随后写入每一级唯一的零距离目标码字。
    for (stage_no=0; stage_no<9; stage_no=stage_no+1)
        for (index_no=0; index_no<((stage_no==0)?256:128); index_no=index_no+1)
            for (group_no=0; group_no<4; group_no=group_no+1)
                write_codebook_word((stage_no==0 ? 0 : 1024+(stage_no-1)*512)+index_no*4+group_no,{8{8'd20}});
    for (group_no=0; group_no<4; group_no=group_no+1) begin
        target_word=0;
        for (lane=0; lane<8; lane=lane+1)
            target_word[8*lane +: 8]=golden_latent[group_no*8+lane];
        write_codebook_word(3*4+group_no,target_word);
    end
    for (stage_no=1; stage_no<9; stage_no=stage_no+1)
        for (group_no=0; group_no<4; group_no=group_no+1)
            write_codebook_word(1024+(stage_no-1)*512+(stage_no+3)*4+group_no,64'd0);

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

    // stage0码字被构造为与32维投影结果完全一致，后8级目标码字均为0，
    // 因而正确的Residual Update结束后，4组INT16 Residual都必须严格为0。
    // 该检查能发现“索引搜索正确、但UPDATE阶段读取了错误码字”的隐蔽故障。
    for (group_no=0; group_no<4; group_no=group_no+1) begin
        if (u_dut.u_rvq.residual_mem[group_no] !== 128'd0) begin
            $display("[ERROR] final RVQ residual group=%0d expected=0 actual=%032h",
                     group_no,u_dut.u_rvq.residual_mem[group_no]);
            errors=errors+1;
        end else begin
            $display("[RVQ_RESIDUAL_PASS] group=%0d value=0",group_no);
        end
    end

    // 一帧端到端耗时：从frame_start被接受，到最终packed RVQ索引完成握手。
    // 100 MHz下1 cycle=10 ns，100 cycle=1 us；20 ms实时预算为2,000,000 cycle。
    frame_total_cycles    = encoded_result_cycle - frame_accept_cycle;
    pcm_stage_cycles      = pcm_done_cycle - frame_accept_cycle;
    encoder_stage_cycles  = encoder_done_cycle - encoder_start_cycle;
    projection_rvq_cycles = encoded_result_cycle - encoder_done_cycle;
    realtime_margin_cycles= FRAME_BUDGET_CYCLES - frame_total_cycles;
    realtime_util_percent = (frame_total_cycles * 100) / FRAME_BUDGET_CYCLES;
    $display("============================================================");
    $display("[FRAME_TIMING] clock=100MHz period_ns=%0d",CLOCK_PERIOD_NS);
    $display("[FRAME_TIMING] PCM_load cycles=%0d time_us=%0d.%02d",
             pcm_stage_cycles,pcm_stage_cycles/100,pcm_stage_cycles%100);
    $display("[FRAME_TIMING] Encoder63 cycles=%0d time_us=%0d.%02d",
             encoder_stage_cycles,encoder_stage_cycles/100,
             encoder_stage_cycles%100);
    $display("[FRAME_TIMING] Projection_plus_RVQ cycles=%0d time_us=%0d.%02d",
             projection_rvq_cycles,projection_rvq_cycles/100,
             projection_rvq_cycles%100);
    $display("[FRAME_TIMING] frame_start_to_encoded_result cycles=%0d time_ns=%0d time_us=%0d.%02d",
             frame_total_cycles,frame_total_cycles*CLOCK_PERIOD_NS,
             frame_total_cycles/100,frame_total_cycles%100);
    $display("[FRAME_TIMING] 20ms_budget cycles=%0d utilization_percent=%0d margin_cycles=%0d margin_us=%0d.%02d",
             FRAME_BUDGET_CYCLES,realtime_util_percent,realtime_margin_cycles,
             realtime_margin_cycles/100,realtime_margin_cycles%100);
    if (frame_total_cycles <= FRAME_BUDGET_CYCLES)
        $display("[FRAME_REALTIME_PASS] one frame finishes within 20 ms");
    else begin
        $display("[FRAME_REALTIME_FAIL] one frame exceeds 20 ms");
        errors=errors+1;
    end
    $display("============================================================");
    if (errors==0)
        $display("[TB_PASS] PCM320 + Encoder63 + Projection64to32 + RVQ9 + packed64 all passed");
    else
        $display("[TB_FAIL] errors=%0d",errors);
    $finish;
end

endmodule
