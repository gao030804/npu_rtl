`timescale 1ns/1ns

//=============================================================================
// A/B Weight SRAM + FAST READ连续预取测试。
//=============================================================================
module tb_weight_cache_ab;

reg clk;
reg rst_n;
reg req_valid;
wire req_ready;
reg [31:0] req_addr;
wire rsp_valid;
reg rsp_ready;
wire [255:0] rsp_data;

reg prefetch_valid;
wire prefetch_ready;
reg [23:0] prefetch_flash_base;
reg [15:0] prefetch_block_count;
reg prefetch_target_bank;
wire prefetch_done;

reg activate_valid;
wire activate_ready;
reg activate_first_layer;
reg activate_bank;
wire active_first_layer;
wire active_bank;
wire active_bank_valid;
wire first_layer_ready;
wire cache_busy;
wire cache_error;

wire flash_csn;
wire flash_sclk;
wire flash_mosi;
wire flash_miso;
tri1 flash_wpn;
tri1 flash_holdn;

integer error_count;
integer timeout_count;
integer byte_index;
integer cs_fall_count;
integer first_sram_write_count;
integer bank_a_sram_write_count;
integer bank_b_sram_write_count;
reg saw_first_read_during_b_prefetch;
reg saw_b_read_during_a_prefetch;
reg [255:0] held_data;

weight_cache_ab #(
    .CACHE_BLOCKS          (8),
    .CACHE_INDEX_WIDTH     (3),
    .FIRST_LAYER_FLASH_BASE(24'h000000),
    .FIRST_LAYER_BLOCKS    (16'd4),
    .SPI_DIVIDER           (16'd1)
) dut (
    .clk(clk), .rst_n(rst_n),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_data(rsp_data),
    .prefetch_valid(prefetch_valid), .prefetch_ready(prefetch_ready),
    .prefetch_flash_base(prefetch_flash_base),
    .prefetch_block_count(prefetch_block_count),
    .prefetch_target_bank(prefetch_target_bank),
    .prefetch_done(prefetch_done),
    .activate_valid(activate_valid), .activate_ready(activate_ready),
    .activate_first_layer(activate_first_layer), .activate_bank(activate_bank),
    .active_first_layer(active_first_layer),
    .active_bank(active_bank), .active_bank_valid(active_bank_valid),
    .first_layer_ready(first_layer_ready),
    .cache_busy(cache_busy), .cache_error(cache_error),
    .flash_csn(flash_csn), .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi), .flash_miso(flash_miso)
);

W25Q128JVxIM u_flash (
    .CSn(flash_csn), .CLK(flash_sclk),
    .DIO(flash_mosi), .DO(flash_miso),
    .WPn(flash_wpn), .HOLDn(flash_holdn)
);

initial clk = 1'b0;
always #5 clk = ~clk;

always @(negedge flash_csn)
    cs_fall_count = cs_fall_count + 1;

always @(posedge clk) begin
    // 打印真正发生的控制握手，便于区分“接口保持”与“重复接收”。
    if (prefetch_valid && prefetch_ready)
        $display(
            "[TRACE] prefetch accept time=%0t target=%s base=%06h blocks=%0d",
            $time,
            prefetch_target_bank ? "B" : "A",
            prefetch_flash_base,
            prefetch_block_count
        );

    if (prefetch_done)
        $display(
            "[TRACE] prefetch done   time=%0t target=%0d writes(first/A/B)=%0d/%0d/%0d",
            $time,
            dut.load_target,
            first_sram_write_count,
            bank_a_sram_write_count,
            bank_b_sram_write_count
        );

    if (dut.first_sram_write)
        first_sram_write_count = first_sram_write_count + 1;
    if (dut.bank_a_sram_write)
        bank_a_sram_write_count = bank_a_sram_write_count + 1;
    if (dut.bank_b_sram_write)
        bank_b_sram_write_count = bank_b_sram_write_count + 1;

    // TARGET_BANK_B=2：预取B期间仍从第一层常驻SRAM发起读取。
    if ((dut.load_target == 2'd2) &&
        (dut.control_state != 3'd3) && dut.first_sram_read)
        saw_first_read_during_b_prefetch = 1'b1;

    // TARGET_BANK_A=1：预取A期间仍从当前活动Bank B发起读取。
    if ((dut.load_target == 2'd1) &&
        (dut.control_state != 3'd3) && dut.bank_b_sram_read)
        saw_b_read_during_a_prefetch = 1'b1;
end

task verify_block;
    input [31:0] address;
    input integer first_byte;
    input integer stall_cycles;
    begin : verify_block_body
        $display("[TRACE] read request    time=%0t addr=%08h", $time, address);
        @(negedge clk);
        req_addr  = address;
        req_valid = 1'b1;
        timeout_count = 0;
        // 激励在negedge给出，必须到posedge判断真正的valid/ready握手。
        // 不能在刚修改地址/valid的同一仿真时隙立即读取组合ready。
        @(posedge clk);
        while (!req_ready && timeout_count < 1000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!req_ready) begin
            $display(
                "[ERROR] cache request timeout addr=%08h active_first=%0b active_bank=%0b state=%0d rsp_valid=%0b pending=%0b",
                address,
                active_first_layer,
                active_bank,
                dut.control_state,
                rsp_valid,
                dut.read_pending
            );
            error_count = error_count + 1;
            req_valid = 1'b0;
            disable verify_block_body;
        end
        @(negedge clk);
        req_valid = 1'b0;

        timeout_count = 0;
        while (!rsp_valid && timeout_count < 1000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!rsp_valid) begin
            $display("[ERROR] cache response timeout addr=%08h", address);
            error_count = error_count + 1;
        end else begin
            held_data = rsp_data;
            repeat (stall_cycles) begin
                @(posedge clk);
                if (!rsp_valid || rsp_data !== held_data) begin
                    $display("[ERROR] cache response changed under backpressure");
                    error_count = error_count + 1;
                end
            end

            for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
                if (rsp_data[8*byte_index +: 8] !==
                    ((first_byte + byte_index) & 8'hff)) begin
                    $display(
                        "[ERROR] addr=%08h byte=%0d expected=%02h actual=%02h",
                        address, byte_index,
                        ((first_byte + byte_index) & 8'hff),
                        rsp_data[8*byte_index +: 8]
                    );
                    error_count = error_count + 1;
                end
            end

            @(negedge clk);
            rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rsp_ready = 1'b0;
            $display("[TRACE] read complete   time=%0t addr=%08h", $time, address);
        end
    end
endtask

initial begin
    rst_n = 1'b0;
    req_valid = 1'b0;
    req_addr = 32'd0;
    rsp_ready = 1'b0;
    prefetch_valid = 1'b0;
    prefetch_flash_base = 24'd0;
    prefetch_block_count = 16'd0;
    prefetch_target_bank = 1'b0;
    activate_valid = 1'b0;
    activate_first_layer = 1'b0;
    activate_bank = 1'b0;
    error_count = 0;
    cs_fall_count = 0;
    first_sram_write_count = 0;
    bank_a_sram_write_count = 0;
    bank_b_sram_write_count = 0;
    saw_first_read_during_b_prefetch = 1'b0;
    saw_b_read_during_a_prefetch = 1'b0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // 第一层应在复位释放后自动连续读取4个block到Bank A。
    timeout_count = 0;
    while (!first_layer_ready && timeout_count < 300000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!first_layer_ready) begin
        $display("[ERROR] first-layer preload timeout");
        error_count = error_count + 1;
    end
    if (cs_fall_count != 1) begin
        $display("[ERROR] first-layer burst CS count expected=1 actual=%0d", cs_fall_count);
        error_count = error_count + 1;
    end

    verify_block(32'h0000_0000, 8'h00, 3);
    verify_block(32'h0000_0060, 8'h60, 0);

    // 当前Bank A计算期间，把下一层3个block连续预取到Bank B。
    @(negedge clk);
    prefetch_flash_base  = 24'h001000;
    prefetch_block_count = 16'd3;
    prefetch_target_bank = 1'b1;
    prefetch_valid       = 1'b1;
    @(posedge clk);
    while (!prefetch_ready)
        @(posedge clk);
    @(negedge clk);
    prefetch_valid = 1'b0;

    // 预取进行时活动Bank A必须仍能正常供数。
    verify_block(32'h0000_0020, 8'h20, 2);

    timeout_count = 0;
    // 直接等待DUT的完成脉冲。此处不再通过另一always块转存sticky标志，
    // 避免testbench多个过程同时读写同一变量造成仿真调度竞争。
    while (!prefetch_done && timeout_count < 300000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!prefetch_done) begin
        $display("[ERROR] next-layer prefetch timeout");
        error_count = error_count + 1;
    end
    if (cs_fall_count != 2) begin
        $display("[ERROR] two layer bursts expected CS count=2 actual=%0d", cs_fall_count);
        error_count = error_count + 1;
    end

    // 层间切换到已经装载完成的Bank B。
    @(negedge clk);
    activate_bank  = 1'b1;
    activate_first_layer = 1'b0;
    activate_valid = 1'b1;
    @(posedge clk);
    while (!activate_ready)
        @(posedge clk);
    @(negedge clk);
    activate_valid = 1'b0;

    verify_block(32'h0000_1000, 8'h80, 1);
    verify_block(32'h0000_1040, 8'hc0, 0);

    if (!active_bank || !active_bank_valid) begin
        $display("[ERROR] Bank B activation failed");
        error_count = error_count + 1;
    end

    // Bank B正在提供NPU读数据时，将下一层的一个block预取到非活动Bank A。
    // Flash 0x000100～0x00011f中的期望数据为00、01、...、1f。
    @(negedge clk);
    prefetch_flash_base   = 24'h000100;
    prefetch_block_count  = 16'd1;
    prefetch_target_bank  = 1'b0;
    prefetch_valid        = 1'b1;
    @(posedge clk);
    while (!prefetch_ready)
        @(posedge clk);
    @(negedge clk);
    prefetch_valid = 1'b0;

    // 预取Bank A期间，当前活动Bank B必须仍可读取并承受响应反压。
    verify_block(32'h0000_1000, 8'h80, 2);

    timeout_count = 0;
    while (!prefetch_done && timeout_count < 300000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!prefetch_done) begin
        $display("[ERROR] Bank A prefetch timeout");
        error_count = error_count + 1;
    end
    if (cs_fall_count != 3) begin
        $display(
            "[ERROR] three layer bursts expected CS count=3 actual=%0d",
            cs_fall_count
        );
        error_count = error_count + 1;
    end

    // 层边界切换到已经装载完成的Bank A，并读取其唯一的权重block。
    $display(
        "[TRACE] before A activate time=%0t state=%0d rsp_valid=%0b pending=%0b valid_a=%0b",
        $time, dut.control_state, rsp_valid, dut.read_pending, dut.bank_valid_a
    );
    @(negedge clk);
    activate_first_layer = 1'b0;
    activate_bank        = 1'b0;
    activate_valid       = 1'b1;
    timeout_count = 0;
    @(posedge clk);
    while (!activate_ready && timeout_count < 1000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!activate_ready) begin
        $display(
            "[ERROR] Bank A activate timeout state=%0d rsp_valid=%0b pending=%0b valid_a=%0b",
            dut.control_state, rsp_valid, dut.read_pending, dut.bank_valid_a
        );
        error_count = error_count + 1;
    end
    @(negedge clk);
    activate_valid = 1'b0;

    verify_block(32'h0000_0100, 8'h00, 1);

    if (active_first_layer || active_bank || !active_bank_valid) begin
        $display("[ERROR] Bank A activation failed");
        error_count = error_count + 1;
    end

    // 第一层使用独立常驻SRAM；切回后数据仍然存在，不需要再次访问Flash。
    $display(
        "[TRACE] before resident activate time=%0t state=%0d rsp_valid=%0b pending=%0b first_valid=%0b",
        $time, dut.control_state, rsp_valid, dut.read_pending, dut.first_layer_valid
    );
    @(negedge clk);
    activate_first_layer = 1'b1;
    activate_valid = 1'b1;
    timeout_count = 0;
    @(posedge clk);
    while (!activate_ready && timeout_count < 1000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!activate_ready) begin
        $display(
            "[ERROR] resident activate timeout state=%0d rsp_valid=%0b pending=%0b first_valid=%0b",
            dut.control_state, rsp_valid, dut.read_pending, dut.first_layer_valid
        );
        error_count = error_count + 1;
    end
    @(negedge clk);
    activate_valid = 1'b0;
    verify_block(32'h0000_0000, 8'h00, 0);
    if (!active_first_layer || (cs_fall_count != 3)) begin
        $display("[ERROR] resident first-layer cache reload or select failure");
        error_count = error_count + 1;
    end
    if (cache_error) begin
        $display("[ERROR] cache_error asserted");
        error_count = error_count + 1;
    end

    if ((first_sram_write_count != 4) ||
        (bank_b_sram_write_count != 3) ||
        (bank_a_sram_write_count != 1)) begin
        $display(
            "[ERROR] SRAM write counts first/A/B expected=4/1/3 actual=%0d/%0d/%0d",
            first_sram_write_count,
            bank_a_sram_write_count,
            bank_b_sram_write_count
        );
        error_count = error_count + 1;
    end

    if (!saw_first_read_during_b_prefetch) begin
        $display("[ERROR] no first-layer read observed while prefetching Bank B");
        error_count = error_count + 1;
    end
    if (!saw_b_read_during_a_prefetch) begin
        $display("[ERROR] no Bank B read observed while prefetching Bank A");
        error_count = error_count + 1;
    end

    if (error_count == 0)
        $display("[TB_PASS] resident first layer + B/A alternating prefetch + FAST READ burst correct");
    else
        $display("[TB_FAIL] errors=%0d", error_count);

    $finish;
end

endmodule
