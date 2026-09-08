`timescale 1ns/1ps

//=============================================================================
// 模块名称：tb_flash_weight_load_timing
// 测试目标：
//   1. 测量初始卷积层权重从外部SPI Flash搬到第一层常驻SRAM的时间；
//   2. 测量下一卷积层权重从外部SPI Flash预取到Weight SRAM B的时间；
//   3. 检查FAST READ命令次数、SRAM写入块数，并读回首/尾块进行数据比较。
//
// 当前真实层参数：
//   初始层：Flash 0x000000，4个256-bit块，  128 Byte；
//   下一层：Flash 0x000080，56个256-bit块，1792 Byte。
//
// 时钟与SPI配置：
//   系统时钟100 MHz（10 ns）；SPI_DIVIDER=1时，SPI SCLK约为25 MHz。
//=============================================================================
module tb_flash_weight_load_timing;

localparam integer CLOCK_PERIOD_NS  = 10;
localparam integer TIMEOUT_CYCLES   = 1000000;

localparam [23:0] FIRST_FLASH_BASE  = 24'h000000;
localparam [15:0] FIRST_BLOCKS      = 16'd4;
localparam [23:0] NEXT_FLASH_BASE   = 24'h000080;
localparam [15:0] NEXT_BLOCKS       = 16'd56;

reg          clk;
reg          rst_n;

reg          req_valid;
wire         req_ready;
reg  [31:0]  req_addr;
wire         rsp_valid;
reg          rsp_ready;
wire [255:0] rsp_data;

reg          prefetch_valid;
wire         prefetch_ready;
reg  [23:0]  prefetch_flash_base;
reg  [15:0]  prefetch_block_count;
reg          prefetch_target_bank;
wire         prefetch_done;

reg          activate_valid;
wire         activate_ready;
reg          activate_first_layer;
reg          activate_bank;
wire         active_first_layer;
wire         active_bank;
wire         active_bank_valid;
wire         first_layer_ready;
wire         cache_busy;
wire         cache_error;

wire         flash_csn;
wire         flash_sclk;
wire         flash_mosi;
wire         flash_miso;
tri1         flash_wpn;
tri1         flash_holdn;

integer cycle_count;
integer error_count;
integer timeout_count;
integer byte_index;
integer csv_file;

integer reset_release_cycle;
integer first_ready_cycle;
integer boot_dma_start_cycle;
integer boot_dma_done_cycle;
integer next_accept_cycle;
integer next_dma_start_cycle;
integer next_dma_done_cycle;

integer first_write_count;
integer bank_b_write_count;
integer cs_fall_count;
integer boot_cs_start;
integer next_cs_start;

reg boot_done_seen;
reg next_done_seen;

// 64个block足以容纳真实下一层的56个block。
weight_cache_ab #(
    .CACHE_BLOCKS           (64),
    .CACHE_INDEX_WIDTH      (6),
    .FIRST_LAYER_FLASH_BASE (FIRST_FLASH_BASE),
    .FIRST_LAYER_BLOCKS     (FIRST_BLOCKS),
    .SPI_DIVIDER            (16'd1)
) dut (
    .clk                    (clk),
    .rst_n                  (rst_n),

    .req_valid              (req_valid),
    .req_ready              (req_ready),
    .req_addr               (req_addr),
    .rsp_valid              (rsp_valid),
    .rsp_ready              (rsp_ready),
    .rsp_data               (rsp_data),

    .prefetch_valid         (prefetch_valid),
    .prefetch_ready         (prefetch_ready),
    .prefetch_flash_base    (prefetch_flash_base),
    .prefetch_block_count   (prefetch_block_count),
    .prefetch_target_bank   (prefetch_target_bank),
    .prefetch_done          (prefetch_done),

    .activate_valid         (activate_valid),
    .activate_ready         (activate_ready),
    .activate_first_layer   (activate_first_layer),
    .activate_bank          (activate_bank),

    .active_first_layer     (active_first_layer),
    .active_bank            (active_bank),
    .active_bank_valid      (active_bank_valid),
    .first_layer_ready      (first_layer_ready),
    .cache_busy             (cache_busy),
    .cache_error            (cache_error),

    .flash_csn              (flash_csn),
    .flash_sclk             (flash_sclk),
    .flash_mosi             (flash_mosi),
    .flash_miso             (flash_miso)
);

// Winbond W25Q128真实逐位行为模型。
W25Q128JVxIM u_flash (
    .CSn   (flash_csn),
    .CLK   (flash_sclk),
    .DIO   (flash_mosi),
    .DO    (flash_miso),
    .WPn   (flash_wpn),
    .HOLDn (flash_holdn)
);

initial clk = 1'b0;
always #(CLOCK_PERIOD_NS/2) clk = ~clk;

// 系统周期计数器。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

// 每次CSn下降代表启动了一次SPI事务。本设计每层应只有一次连续Burst。
always @(negedge flash_csn)
    cs_fall_count = cs_fall_count + 1;

// 统一采集内部DMA握手、完成事件以及SRAM写入次数。
always @(posedge clk) begin
    if (rst_n) begin
        if (dut.dma_cmd_valid && dut.dma_cmd_ready) begin
            if (dut.load_target == 2'd0) begin
                boot_dma_start_cycle = cycle_count;
                $display("[TRACE] initial DMA start cycle=%0d time=%0t base=%06h blocks=%0d",
                         cycle_count, $time, dut.load_base_q, dut.load_count_q);
            end
            else if (dut.load_target == 2'd2) begin
                next_dma_start_cycle = cycle_count;
                $display("[TRACE] next DMA start    cycle=%0d time=%0t base=%06h blocks=%0d target=B",
                         cycle_count, $time, dut.load_base_q, dut.load_count_q);
            end
        end

        if (dut.first_sram_write)
            first_write_count = first_write_count + 1;
        if (dut.bank_b_sram_write)
            bank_b_write_count = bank_b_write_count + 1;

        if (dut.dma_done) begin
            if (dut.load_target == 2'd0) begin
                boot_dma_done_cycle = cycle_count;
                boot_done_seen      = 1'b1;
                $display("[TRACE] initial DMA done  cycle=%0d time=%0t writes=%0d",
                         cycle_count, $time, first_write_count);
            end
            else if (dut.load_target == 2'd2) begin
                next_dma_done_cycle = cycle_count;
                next_done_seen      = 1'b1;
                $display("[TRACE] next DMA done     cycle=%0d time=%0t writes=%0d",
                         cycle_count, $time, bank_b_write_count);
            end
        end
    end
end

// 打印周期、ns和us。100 MHz下，每100个周期正好是1 us。
task print_duration;
    input [8*32-1:0] name;
    input integer cycles;
    begin
        $display("[TIMING] %0s cycles=%0d time_ns=%0d time_us=%0d.%02d",
                 name, cycles, cycles*CLOCK_PERIOD_NS,
                 cycles/100, cycles%100);
    end
endtask

// 从当前活动Weight SRAM读一个256-bit块，并逐字节与Flash原始内容比较。
task verify_sram_block;
    input [31:0] address;
    begin : verify_body
        @(negedge clk);
        req_addr  = address;
        req_valid = 1'b1;

        timeout_count = 0;
        @(posedge clk);
        while (!req_ready && timeout_count < 1000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!req_ready) begin
            $display("[ERROR] SRAM request timeout addr=%08h", address);
            error_count = error_count + 1;
            req_valid = 1'b0;
            disable verify_body;
        end

        @(negedge clk);
        req_valid = 1'b0;

        timeout_count = 0;
        while (!rsp_valid && timeout_count < 1000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!rsp_valid) begin
            $display("[ERROR] SRAM response timeout addr=%08h", address);
            error_count = error_count + 1;
        end
        else begin
            for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
                if (rsp_data[8*byte_index +: 8] !==
                    u_flash.memory[address + byte_index]) begin
                    $display("[ERROR] data mismatch addr=%08h byte=%0d flash=%02h sram=%02h",
                             address, byte_index,
                             u_flash.memory[address + byte_index],
                             rsp_data[8*byte_index +: 8]);
                    error_count = error_count + 1;
                end
            end

            @(negedge clk);
            rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rsp_ready = 1'b0;
            $display("[CHECK] SRAM block matches Flash addr=%08h", address);
        end
    end
endtask

initial begin
    rst_n                 = 1'b0;
    req_valid             = 1'b0;
    req_addr              = 32'd0;
    rsp_ready             = 1'b0;
    prefetch_valid        = 1'b0;
    prefetch_flash_base   = 24'd0;
    prefetch_block_count  = 16'd0;
    prefetch_target_bank  = 1'b0;
    activate_valid        = 1'b0;
    activate_first_layer  = 1'b0;
    activate_bank         = 1'b0;

    cycle_count           = 0;
    error_count           = 0;
    timeout_count         = 0;
    reset_release_cycle   = -1;
    first_ready_cycle     = -1;
    boot_dma_start_cycle  = -1;
    boot_dma_done_cycle   = -1;
    next_accept_cycle     = -1;
    next_dma_start_cycle  = -1;
    next_dma_done_cycle   = -1;
    first_write_count     = 0;
    bank_b_write_count    = 0;
    cs_fall_count         = 0;
    boot_cs_start         = 0;
    next_cs_start         = 0;
    boot_done_seen        = 1'b0;
    next_done_seen        = 1'b0;

    csv_file = $fopen("logs/flash_weight_load_timing.csv", "w");
    if (csv_file == 0) begin
        $display("[TB_FAIL] cannot open logs/flash_weight_load_timing.csv");
        $finish;
    end
    $fwrite(csv_file,
            "load,flash_base,blocks,bytes,request_cycles,dma_cycles,time_ns,time_us,sram_writes,spi_transactions\n");

    // ----------------------------------------------------------------------
    // 测试1：复位释放后，控制器自动加载第一层权重。
    // ----------------------------------------------------------------------
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n               = 1'b1;
    reset_release_cycle = cycle_count;
    boot_cs_start       = cs_fall_count;

    timeout_count = 0;
    while (!first_layer_ready && timeout_count < TIMEOUT_CYCLES) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    first_ready_cycle = cycle_count;

    if (!first_layer_ready) begin
        $display("[ERROR] initial-layer load timeout");
        error_count = error_count + 1;
    end
    if (!boot_done_seen || boot_dma_start_cycle < 0) begin
        $display("[ERROR] initial-layer DMA timing event missing");
        error_count = error_count + 1;
    end
    if (first_write_count != FIRST_BLOCKS) begin
        $display("[ERROR] initial SRAM writes expected=%0d actual=%0d",
                 FIRST_BLOCKS, first_write_count);
        error_count = error_count + 1;
    end
    if ((cs_fall_count - boot_cs_start) != 1) begin
        $display("[ERROR] initial layer expected one SPI burst actual=%0d",
                 cs_fall_count - boot_cs_start);
        error_count = error_count + 1;
    end

    $display("============================================================");
    $display("[RESULT] initial layer base=%06h blocks=%0d bytes=%0d",
             FIRST_FLASH_BASE, FIRST_BLOCKS, FIRST_BLOCKS*32);
    print_duration("reset_to_first_ready",
                   first_ready_cycle-reset_release_cycle);
    print_duration("initial_dma_transfer",
                   boot_dma_done_cycle-boot_dma_start_cycle);
    $fwrite(csv_file,"initial_layer,%06h,%0d,%0d,%0d,%0d,%0d,%0d.%02d,%0d,%0d\n",
            FIRST_FLASH_BASE, FIRST_BLOCKS, FIRST_BLOCKS*32,
            first_ready_cycle-reset_release_cycle,
            boot_dma_done_cycle-boot_dma_start_cycle,
            (boot_dma_done_cycle-boot_dma_start_cycle)*CLOCK_PERIOD_NS,
            (boot_dma_done_cycle-boot_dma_start_cycle)/100,
            (boot_dma_done_cycle-boot_dma_start_cycle)%100,
            first_write_count, cs_fall_count-boot_cs_start);

    // 对第一层常驻SRAM的首块和末块做数据比较。
    verify_sram_block({8'd0,FIRST_FLASH_BASE});
    verify_sram_block({8'd0,FIRST_FLASH_BASE} + (FIRST_BLOCKS-1)*32);

    // ----------------------------------------------------------------------
    // 测试2：发出真实下一层预取命令，权重写入非活动Bank B。
    // ----------------------------------------------------------------------
    next_cs_start = cs_fall_count;
    @(negedge clk);
    prefetch_flash_base  = NEXT_FLASH_BASE;
    prefetch_block_count = NEXT_BLOCKS;
    prefetch_target_bank = 1'b1;
    prefetch_valid       = 1'b1;

    timeout_count = 0;
    @(posedge clk);
    while (!prefetch_ready && timeout_count < 1000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!prefetch_ready) begin
        $display("[ERROR] next-layer prefetch request timeout");
        error_count = error_count + 1;
    end
    next_accept_cycle = cycle_count;

    @(negedge clk);
    prefetch_valid = 1'b0;

    timeout_count = 0;
    while (!next_done_seen && timeout_count < TIMEOUT_CYCLES) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!next_done_seen) begin
        $display("[ERROR] next-layer DMA timeout");
        error_count = error_count + 1;
    end
    if (bank_b_write_count != NEXT_BLOCKS) begin
        $display("[ERROR] Bank B writes expected=%0d actual=%0d",
                 NEXT_BLOCKS, bank_b_write_count);
        error_count = error_count + 1;
    end
    if ((cs_fall_count - next_cs_start) != 1) begin
        $display("[ERROR] next layer expected one SPI burst actual=%0d",
                 cs_fall_count - next_cs_start);
        error_count = error_count + 1;
    end

    $display("============================================================");
    $display("[RESULT] next layer base=%06h blocks=%0d bytes=%0d target=Bank B",
             NEXT_FLASH_BASE, NEXT_BLOCKS, NEXT_BLOCKS*32);
    print_duration("prefetch_accept_to_done",
                   next_dma_done_cycle-next_accept_cycle);
    print_duration("next_dma_transfer",
                   next_dma_done_cycle-next_dma_start_cycle);
    $fwrite(csv_file,"next_layer,%06h,%0d,%0d,%0d,%0d,%0d,%0d.%02d,%0d,%0d\n",
            NEXT_FLASH_BASE, NEXT_BLOCKS, NEXT_BLOCKS*32,
            next_dma_done_cycle-next_accept_cycle,
            next_dma_done_cycle-next_dma_start_cycle,
            (next_dma_done_cycle-next_dma_start_cycle)*CLOCK_PERIOD_NS,
            (next_dma_done_cycle-next_dma_start_cycle)/100,
            (next_dma_done_cycle-next_dma_start_cycle)%100,
            bank_b_write_count, cs_fall_count-next_cs_start);

    // 切换到Bank B，再读回下一层的首块和末块，与Flash逐字节比较。
    @(negedge clk);
    activate_first_layer = 1'b0;
    activate_bank        = 1'b1;
    activate_valid       = 1'b1;
    timeout_count        = 0;
    @(posedge clk);
    while (!activate_ready && timeout_count < 1000) begin
        @(posedge clk);
        timeout_count = timeout_count + 1;
    end
    if (!activate_ready) begin
        $display("[ERROR] Bank B activation timeout");
        error_count = error_count + 1;
    end
    @(negedge clk);
    activate_valid = 1'b0;

    verify_sram_block({8'd0,NEXT_FLASH_BASE});
    verify_sram_block({8'd0,NEXT_FLASH_BASE} + (NEXT_BLOCKS-1)*32);

    if (!active_bank_valid || !active_bank || active_first_layer) begin
        $display("[ERROR] Bank B is not the valid active weight source");
        error_count = error_count + 1;
    end
    if (cache_error) begin
        $display("[ERROR] cache_error asserted");
        error_count = error_count + 1;
    end

    $display("============================================================");
    if (error_count == 0)
        $display("[TB_PASS] initial and next-layer Flash-to-SRAM timing/data checks passed");
    else
        $display("[TB_FAIL] errors=%0d", error_count);

    $fclose(csv_file);
    $finish;
end

endmodule
