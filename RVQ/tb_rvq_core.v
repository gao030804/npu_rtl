`timescale 1ns/1ps

//=============================================================================
// RVQ Core自检Testbench
//
// 测试向量：64维latent全部为40。
//   stage0：选中index=3，码字=5，Residual 40 -> 35
//   stage1：选中index=4，码字=10，Residual 35 -> 25
//   stage2：选中index=5，码字=5，mult=2，Residual 25 -> 15
//   stage3：选中index=6，码字=3，mult=5，Residual 15 -> 0
//   stage4~7：分别选中index=7~10，码字=0，Residual保持0
//
// 其他码字被设置成远离Residual的数值，从而保证最优index唯一。
//=============================================================================
module tb_rvq_core;

reg         clk;
reg         rst_n;
reg         scale_cfg_valid;
wire        scale_cfg_ready;
reg  [2:0]  scale_cfg_stage;
reg  [31:0] scale_cfg_multiplier;
reg  [5:0]  scale_cfg_shift;
reg         codebook_wr_valid;
wire        codebook_wr_ready;
reg  [13:0] codebook_wr_addr;
reg  [63:0] codebook_wr_data;
reg         latent_valid;
wire        latent_ready;
reg  [63:0] latent_data;
reg         latent_last;
wire        result_valid;
reg         result_ready;
wire [63:0] result_indices;
reg  [2:0]  residual_debug_group;
wire [127:0] residual_debug_data;
wire        busy;
wire        error;

integer cycle_count;
integer search_start_cycle;
integer search_done_cycle;
integer error_count;
integer addr;
integer stage_i;
integer entry_i;
integer group_i;
integer lane_i;
reg [7:0] code_value;
reg [63:0] expected_indices;
reg [63:0] held_indices;

rvq_core u_dut (
    .clk                  (clk),
    .rst_n                (rst_n),
    .scale_cfg_valid      (scale_cfg_valid),
    .scale_cfg_ready      (scale_cfg_ready),
    .scale_cfg_stage      (scale_cfg_stage),
    .scale_cfg_multiplier (scale_cfg_multiplier),
    .scale_cfg_shift      (scale_cfg_shift),
    .codebook_wr_valid    (codebook_wr_valid),
    .codebook_wr_ready    (codebook_wr_ready),
    .codebook_wr_addr     (codebook_wr_addr),
    .codebook_wr_data     (codebook_wr_data),
    .latent_valid         (latent_valid),
    .latent_ready         (latent_ready),
    .latent_data          (latent_data),
    .latent_last          (latent_last),
    .result_valid         (result_valid),
    .result_ready         (result_ready),
    .result_indices       (result_indices),
    .residual_debug_group (residual_debug_group),
    .residual_debug_data  (residual_debug_data),
    .busy                 (busy),
    .error                (error)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (!rst_n)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

function [7:0] target_code_value;
    input integer stage_number;
    begin
        case (stage_number)
            0: target_code_value = 8'd5;
            1: target_code_value = 8'd10;
            2: target_code_value = 8'd5;
            3: target_code_value = 8'd3;
            default: target_code_value = 8'd0;
        endcase
    end
endfunction

function [7:0] other_code_value;
    input integer stage_number;
    begin
        if (stage_number < 4)
            other_code_value = 8'd100;
        else
            other_code_value = 8'd20;
    end
endfunction

task configure_scale;
    input [2:0]  cfg_stage;
    input [31:0] cfg_multiplier;
    input [5:0]  cfg_shift;
    begin
        while (!scale_cfg_ready)
            @(negedge clk);
        scale_cfg_stage      = cfg_stage;
        scale_cfg_multiplier = cfg_multiplier;
        scale_cfg_shift      = cfg_shift;
        scale_cfg_valid      = 1'b1;
        @(negedge clk);
        scale_cfg_valid      = 1'b0;
    end
endtask

task load_full_codebook;
    begin
        while (!codebook_wr_ready)
            @(negedge clk);

        codebook_wr_valid = 1'b1;
        for (addr = 0; addr < 16384; addr = addr + 1) begin
            stage_i = (addr >> 11) & 7;
            entry_i = (addr >> 3) & 255;
            group_i = addr & 7;

            if (entry_i == (stage_i + 3))
                code_value = target_code_value(stage_i);
            else
                code_value = other_code_value(stage_i);

            codebook_wr_addr = addr[13:0];
            codebook_wr_data = {8{code_value}};
            @(negedge clk);
        end
        codebook_wr_valid = 1'b0;
        codebook_wr_addr  = 14'd0;
        codebook_wr_data  = 64'd0;

        $display(
            "[TRACE] codebook loaded: 16384 x 64-bit = 128 KiB, cycle=%0d",
            cycle_count
        );
    end
endtask

task send_latent_frame;
    begin
        latent_data = 64'h2828_2828_2828_2828;
        latent_valid = 1'b1;

        for (group_i = 0; group_i < 8; group_i = group_i + 1) begin
            while (!latent_ready)
                @(negedge clk);
            latent_last = (group_i == 7);
            @(negedge clk);
        end

        latent_valid = 1'b0;
        latent_last  = 1'b0;
        search_start_cycle = cycle_count;
        $display("[TRACE] 64-dimension latent accepted, search_start_cycle=%0d",
                 search_start_cycle);
    end
endtask

task check_final_residual;
    begin
        for (group_i = 0; group_i < 8; group_i = group_i + 1) begin
            residual_debug_group = group_i[2:0];
            #1;
            if (residual_debug_data !== 128'd0) begin
                error_count = error_count + 1;
                $display(
                    "[FAIL][RESIDUAL] group=%0d expected=0 actual=%032h",
                    group_i,residual_debug_data
                );
            end else begin
                $display("[PASS][RESIDUAL] group=%0d value=0",group_i);
            end
        end
    end
endtask

initial begin
    clk                  = 1'b0;
    rst_n                = 1'b0;
    scale_cfg_valid      = 1'b0;
    scale_cfg_stage      = 3'd0;
    scale_cfg_multiplier = 32'd0;
    scale_cfg_shift      = 6'd0;
    codebook_wr_valid    = 1'b0;
    codebook_wr_addr     = 14'd0;
    codebook_wr_data     = 64'd0;
    latent_valid         = 1'b0;
    latent_data          = 64'd0;
    latent_last          = 1'b0;
    result_ready         = 1'b0;
    residual_debug_group = 3'd0;
    cycle_count          = 0;
    search_start_cycle   = 0;
    search_done_cycle    = 0;
    error_count          = 0;
    expected_indices     = 64'h0a09_0807_0605_0403;
    held_indices         = 64'd0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // stage2/3刻意使用非1倍Scale，验证码本Scale对齐通路。
    for (stage_i = 0; stage_i < 8; stage_i = stage_i + 1) begin
        if (stage_i == 2)
            configure_scale(stage_i[2:0],32'd2,6'd0);
        else if (stage_i == 3)
            configure_scale(stage_i[2:0],32'd5,6'd0);
        else
            configure_scale(stage_i[2:0],32'd1,6'd0);
    end

    load_full_codebook;
    send_latent_frame;

    // result_ready保持为0，先验证DUT能够正确保持valid和输出数据。
    while (!result_valid)
        @(negedge clk);

    search_done_cycle = cycle_count;
    held_indices = result_indices;

    if (result_indices !== expected_indices) begin
        error_count = error_count + 1;
        $display(
            "[FAIL][INDEX] expected=%016h actual=%016h",
            expected_indices,result_indices
        );
    end else begin
        $display("[PASS][INDEX] q7..q0=%016h",result_indices);
    end

    check_final_residual;

    repeat (4) begin
        @(posedge clk);
        #1;
        if (!result_valid || (result_indices !== held_indices)) begin
            error_count = error_count + 1;
            $display(
                "[FAIL][BACKPRESSURE] valid=%0d held=%016h actual=%016h",
                result_valid,held_indices,result_indices
            );
        end
    end

    if (error) begin
        error_count = error_count + 1;
        $display("[FAIL] DUT error flag asserted");
    end

    $display(
        "[TIMING] RVQ search+update cycles=%0d time_ns=%0d time_us=%0d.%02d",
        search_done_cycle-search_start_cycle,
        (search_done_cycle-search_start_cycle)*10,
        (search_done_cycle-search_start_cycle)/100,
        (search_done_cycle-search_start_cycle)%100
    );

    @(negedge clk);
    result_ready = 1'b1;
    @(negedge clk);
    result_ready = 1'b0;

    if (busy) begin
        error_count = error_count + 1;
        $display("[FAIL] busy did not clear after result handshake");
    end

    if (error_count == 0)
        $display("[TB_PASS] 8-stage/256-entry RVQ, INT16 residual and UINT8 indices correct");
    else
        $display("[TB_FAIL] rvq_core errors=%0d",error_count);

    $finish;
end

// 防止握手或状态机错误导致run -all永久运行。
initial begin
    #1000000;
    $display("[TB_FAIL] timeout");
    $finish;
end

endmodule
