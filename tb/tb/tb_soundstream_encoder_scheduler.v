`timescale 1ns/1ps

//=============================================================================
// 完整层调度器测试
// 用短延迟模型代替真实卷积与 Flash，只验证控制顺序和每层配置：
// 31 个物理卷积、30 次下一层预取、A/B 交替、12 次残差保存/相加、
// 以及逻辑第 29 层拆成两个 128 KiB 权重子层。
//=============================================================================
module tb_soundstream_encoder_scheduler;

reg clk, rst_n, start;
wire start_ready, busy, done, error;
reg first_layer_weight_ready, active_weight_is_first_layer, weight_error;
wire weight_prefetch_valid;
reg weight_prefetch_ready;
wire [23:0] weight_prefetch_flash_base;
wire [15:0] weight_prefetch_block_count;
wire weight_prefetch_target_bank;
reg weight_prefetch_done;
wire weight_activate_valid;
reg weight_activate_ready;
wire weight_activate_first_layer, weight_activate_bank;
wire engine_start;
reg engine_done, engine_error;
wire capture_start;
reg capture_start_ready, capture_done, capture_error;
wire layer_prepare_valid;
reg layer_prepare_ready;
wire [5:0] physical_layer, logical_layer;
wire current_buffer_select, residual_add_enable;
wire [8:0] cfg_cin,cfg_cout,cfg_input_length,cfg_output_length;
wire [4:0] cfg_kernel;
wire [3:0] cfg_stride,cfg_dilation;
wire [7:0] cfg_left_pad;
wire [11:0] cfg_k_total;
wire [9:0] cfg_k_groups;
wire [5:0] cfg_n_groups;
wire cfg_is_depthwise,cfg_relu_enable,cfg_elu_enable;
wire [23:0] cfg_weight_flash_base;
wire [15:0] cfg_weight_block_count;

integer errors, engine_count, prefetch_count, activate_count;
integer capture_count, residual_add_count, cycles;
integer engine_delay, prefetch_delay, capture_delay;
reg expected_buffer;

soundstream_encoder_scheduler u_dut (
    .clk(clk),.rst_n(rst_n),.start(start),.start_ready(start_ready),
    .busy(busy),.done(done),.error(error),
    .first_layer_weight_ready(first_layer_weight_ready),
    .active_weight_is_first_layer(active_weight_is_first_layer),
    .weight_error(weight_error),
    .weight_prefetch_valid(weight_prefetch_valid),
    .weight_prefetch_ready(weight_prefetch_ready),
    .weight_prefetch_flash_base(weight_prefetch_flash_base),
    .weight_prefetch_block_count(weight_prefetch_block_count),
    .weight_prefetch_target_bank(weight_prefetch_target_bank),
    .weight_prefetch_done(weight_prefetch_done),
    .weight_activate_valid(weight_activate_valid),
    .weight_activate_ready(weight_activate_ready),
    .weight_activate_first_layer(weight_activate_first_layer),
    .weight_activate_bank(weight_activate_bank),
    .engine_start(engine_start),.engine_done(engine_done),.engine_error(engine_error),
    .capture_start(capture_start),.capture_start_ready(capture_start_ready),
    .capture_done(capture_done),.capture_error(capture_error),
    .layer_prepare_valid(layer_prepare_valid),.layer_prepare_ready(layer_prepare_ready),
    .physical_layer(physical_layer),.logical_layer(logical_layer),
    .current_buffer_select(current_buffer_select),
    .residual_add_enable(residual_add_enable),
    .cfg_cin(cfg_cin),.cfg_cout(cfg_cout),.cfg_kernel(cfg_kernel),
    .cfg_stride(cfg_stride),.cfg_dilation(cfg_dilation),.cfg_left_pad(cfg_left_pad),
    .cfg_input_length(cfg_input_length),.cfg_output_length(cfg_output_length),
    .cfg_k_total(cfg_k_total),.cfg_k_groups(cfg_k_groups),.cfg_n_groups(cfg_n_groups),
    .cfg_is_depthwise(cfg_is_depthwise),.cfg_relu_enable(cfg_relu_enable),
    .cfg_elu_enable(cfg_elu_enable),.cfg_weight_flash_base(cfg_weight_flash_base),
    .cfg_weight_block_count(cfg_weight_block_count)
);

always #5 clk = ~clk;

task flag_error;
    input [8*100-1:0] message;
    begin
        $display("[ERROR] layer=%0d %0s", physical_layer, message);
        errors = errors + 1;
    end
endtask

// 可控的 Flash/卷积/Residual Capture 延迟模型。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        engine_done <= 1'b0;
        weight_prefetch_done <= 1'b0;
        capture_done <= 1'b0;
        engine_delay <= 0;
        prefetch_delay <= 0;
        capture_delay <= 0;
    end else begin
        engine_done <= 1'b0;
        weight_prefetch_done <= 1'b0;
        capture_done <= 1'b0;

        if (engine_start)
            engine_delay <= 6;
        else if (engine_delay > 1)
            engine_delay <= engine_delay - 1;
        else if (engine_delay == 1) begin
            engine_delay <= 0;
            engine_done <= 1'b1;
        end

        if (weight_prefetch_valid && weight_prefetch_ready)
            prefetch_delay <= 3;
        else if (prefetch_delay > 1)
            prefetch_delay <= prefetch_delay - 1;
        else if (prefetch_delay == 1) begin
            prefetch_delay <= 0;
            weight_prefetch_done <= 1'b1;
        end

        if (capture_start && capture_start_ready)
            capture_delay <= 2;
        else if (capture_delay > 1)
            capture_delay <= capture_delay - 1;
        else if (capture_delay == 1) begin
            capture_delay <= 0;
            capture_done <= 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (rst_n) begin
        if (capture_start && capture_start_ready)
            capture_count = capture_count + 1;

        if (weight_prefetch_valid && weight_prefetch_ready) begin
            if (weight_prefetch_target_bank !== ((physical_layer + 1'b1) & 1'b1))
                flag_error("prefetch target bank is not alternating");
            if (weight_prefetch_block_count > 16'd4096)
                flag_error("prefetch exceeds one 128 KiB SRAM bank");
            prefetch_count = prefetch_count + 1;
        end

        if (weight_activate_valid && weight_activate_ready)
            activate_count = activate_count + 1;

        if (engine_start) begin
            if (physical_layer !== engine_count[5:0])
                flag_error("physical layer sequence mismatch");
            if (current_buffer_select !== expected_buffer)
                flag_error("activation ping-pong selection mismatch");
            if (residual_add_enable)
                residual_add_count = residual_add_count + 1;

            // 原逻辑第29层拆分的两个物理层。
            if ((physical_layer==8) && (!cfg_is_depthwise ||
                cfg_k_total!=7 || cfg_k_groups!=2))
                flag_error("first revision-3 depthwise configuration mismatch");
            if ((physical_layer==62) && (cfg_cin!=256 || cfg_cout!=64 ||
                cfg_kernel!=3 || cfg_weight_flash_base!=24'd113536 ||
                cfg_weight_block_count!=1536))
                flag_error("final projection configuration mismatch");

            $display("[TRACE] physical=%0d logical=%0d Cin=%0d Cout=%0d K=%0d S=%0d Lin=%0d Lout=%0d blocks=%0d residual_add=%0d",
                     physical_layer,logical_layer,cfg_cin,cfg_cout,cfg_kernel,
                     cfg_stride,cfg_input_length,cfg_output_length,
                     cfg_weight_block_count,residual_add_enable);
            engine_count = engine_count + 1;
            expected_buffer = ~expected_buffer;
        end
    end
end

initial begin
    clk=0; rst_n=0; start=0;
    first_layer_weight_ready=1; active_weight_is_first_layer=1;
    weight_error=0; weight_prefetch_ready=1; weight_activate_ready=1;
    engine_error=0; capture_start_ready=1; capture_error=0;
    layer_prepare_ready=1;
    errors=0; engine_count=0; prefetch_count=0; activate_count=0;
    capture_count=0; residual_add_count=0; cycles=0;
    engine_delay=0; prefetch_delay=0; capture_delay=0;
    expected_buffer=0;

    repeat (4) @(posedge clk);
    rst_n=1;
    repeat (2) @(posedge clk);
    if (!start_ready)
        flag_error("start_ready should be high");
    start=1;
    @(posedge clk);
    start=0;

    while (!done && cycles < 3000) begin
        @(posedge clk);
        cycles = cycles + 1;
    end
    @(posedge clk);

    if (!done && cycles >= 3000)
        flag_error("scheduler timeout");
    if (engine_count != 63)
        flag_error("expected 63 physical convolutions");
    if (prefetch_count != 62)
        flag_error("expected 62 next-layer prefetches");
    if (activate_count != 63)
        flag_error("expected 62 bank switches plus first-layer return");
    if (capture_count != 12)
        flag_error("expected 12 residual captures");
    if (residual_add_count != 12)
        flag_error("expected 12 residual additions");
    if (current_buffer_select != 1'b1)
        flag_error("63 layers should leave final result in buffer B");
    if (error)
        flag_error("scheduler error unexpectedly asserted");

    if (errors == 0)
        $display("[TB_PASS] 63-layer revision-3 schedule and residual flow correct");
    else
        $display("[TB_FAIL] errors=%0d", errors);
    $finish;
end

endmodule
