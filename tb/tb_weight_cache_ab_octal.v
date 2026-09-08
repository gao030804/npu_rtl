`timescale 1ns/1ps

//=============================================================================
// 100 MHz Octal DDR接收流 -> 256-bit DMA -> 第一层/A/B Weight SRAM测试。
//=============================================================================
module tb_weight_cache_ab_octal;

localparam [23:0] FIRST_BASE   = 24'h000000;
localparam [15:0] FIRST_BLOCKS = 16'd4;
localparam [23:0] NEXT_BASE    = 24'h000080;
localparam [15:0] NEXT_BLOCKS  = 16'd56;

reg clk;
reg phy_clk;
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

wire cmd_valid,cmd_ready;
wire [23:0] cmd_base,cmd_bytes;
wire phy_rx_valid,phy_rx_ready,phy_rx_last,phy_rx_error;
wire [15:0] phy_rx_data;
wire rx_valid,rx_ready;
wire [17:0] rx_payload;

integer cycle_count;
integer first_start_cycle,first_done_cycle;
integer next_start_cycle,next_done_cycle;
integer first_writes,bank_b_writes;
integer errors,timeout_count,byte_index;

weight_cache_ab_octal #(
    .CACHE_BLOCKS(64), .CACHE_INDEX_WIDTH(6),
    .FIRST_LAYER_FLASH_BASE(FIRST_BASE),
    .FIRST_LAYER_BLOCKS(FIRST_BLOCKS)
) dut (
    .clk(clk),.rst_n(rst_n),
    .req_valid(req_valid),.req_ready(req_ready),.req_addr(req_addr),
    .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_data(rsp_data),
    .prefetch_valid(prefetch_valid),.prefetch_ready(prefetch_ready),
    .prefetch_flash_base(prefetch_flash_base),
    .prefetch_block_count(prefetch_block_count),
    .prefetch_target_bank(prefetch_target_bank),.prefetch_done(prefetch_done),
    .activate_valid(activate_valid),.activate_ready(activate_ready),
    .activate_first_layer(activate_first_layer),.activate_bank(activate_bank),
    .active_first_layer(active_first_layer),.active_bank(active_bank),
    .active_bank_valid(active_bank_valid),.first_layer_ready(first_layer_ready),
    .cache_busy(cache_busy),.cache_error(cache_error),
    .octal_cmd_valid(cmd_valid),.octal_cmd_ready(cmd_ready),
    .octal_cmd_flash_base(cmd_base),.octal_cmd_byte_count(cmd_bytes),
    .octal_rx_valid(rx_valid),.octal_rx_ready(rx_ready),
    .octal_rx_data(rx_payload[15:0]),.octal_rx_last(rx_payload[16]),
    .octal_rx_error(rx_payload[17])
);

octal_ddr_async_fifo #(
    .DATA_WIDTH(18), .ADDR_WIDTH(5)
) cdc_fifo (
    .wr_clk(phy_clk),.wr_rst_n(rst_n),
    .wr_valid(phy_rx_valid),.wr_ready(phy_rx_ready),
    .wr_data({phy_rx_error,phy_rx_last,phy_rx_data}),
    .rd_clk(clk),.rd_rst_n(rst_n),
    .rd_valid(rx_valid),.rd_ready(rx_ready),.rd_data(rx_payload)
);

octal_ddr_weight_source_model #(
    .MEM_BYTES(1048576),
    .MEM_FILE("tb/data/full_encoder/weights.mem")
) source (
    .cmd_clk(clk),.phy_clk(phy_clk),.rst_n(rst_n),
    .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
    .cmd_flash_base(cmd_base),.cmd_byte_count(cmd_bytes),
    .rx_valid(phy_rx_valid),.rx_ready(phy_rx_ready),.rx_data(phy_rx_data),
    .rx_last(phy_rx_last),.rx_error(phy_rx_error)
);

initial clk=1'b0;
always #5 clk=~clk;
// 同为100 MHz但错开2 ns相位，用于验证真实跨时钟路径。
initial begin
    phy_clk=1'b0;
    #2;
    forever #5 phy_clk=~phy_clk;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

always @(posedge clk) begin
    if (rst_n) begin
        if (cmd_valid && cmd_ready) begin
            if (cmd_base == FIRST_BASE)
                first_start_cycle = cycle_count;
            else if (cmd_base == NEXT_BASE)
                next_start_cycle = cycle_count;
            $display("[TRACE] octal command cycle=%0d base=%06h bytes=%0d",
                     cycle_count,cmd_base,cmd_bytes);
        end
        if (dut.first_sram_write)
            first_writes = first_writes + 1;
        if (dut.bank_b_sram_write)
            bank_b_writes = bank_b_writes + 1;
        if (dut.dma_done && dut.load_target==2'd0)
            first_done_cycle = cycle_count;
        if (dut.dma_done && dut.load_target==2'd2)
            next_done_cycle = cycle_count;
    end
end

task verify_block;
    input [31:0] address;
    begin
        @(negedge clk); req_addr=address; req_valid=1'b1;
        @(posedge clk);
        while(!req_ready) @(posedge clk);
        @(negedge clk); req_valid=1'b0;
        while(!rsp_valid) @(posedge clk);
        for(byte_index=0;byte_index<32;byte_index=byte_index+1) begin
            if(rsp_data[8*byte_index +: 8] !== source.memory[address+byte_index]) begin
                $display("[ERROR] addr=%08h byte=%0d expected=%02h actual=%02h",
                         address,byte_index,source.memory[address+byte_index],
                         rsp_data[8*byte_index +: 8]);
                errors=errors+1;
            end
        end
        @(negedge clk); rsp_ready=1'b1;
        @(posedge clk); @(negedge clk); rsp_ready=1'b0;
        $display("[CHECK] SRAM matches external image addr=%08h",address);
    end
endtask

initial begin
    rst_n=0; req_valid=0; req_addr=0; rsp_ready=0;
    prefetch_valid=0; prefetch_flash_base=0; prefetch_block_count=0;
    prefetch_target_bank=0; activate_valid=0; activate_first_layer=0;
    activate_bank=0; cycle_count=0; first_start_cycle=-1;
    first_done_cycle=-1; next_start_cycle=-1; next_done_cycle=-1;
    first_writes=0; bank_b_writes=0; errors=0;

    repeat(5) @(posedge clk);
    @(negedge clk); rst_n=1;

    timeout_count=0;
    while(!first_layer_ready && timeout_count<10000) begin
        @(posedge clk); timeout_count=timeout_count+1;
    end
    if(!first_layer_ready) begin
        $display("[ERROR] initial layer timeout"); errors=errors+1;
    end
    $display("[TIMING] initial blocks=4 cycles=%0d time_us=%0d.%02d writes=%0d",
             first_done_cycle-first_start_cycle,
             (first_done_cycle-first_start_cycle)/100,
             (first_done_cycle-first_start_cycle)%100,first_writes);
    if(first_writes!=4) errors=errors+1;
    verify_block(32'h00000000);
    verify_block(32'h00000060);

    @(negedge clk);
    prefetch_flash_base=NEXT_BASE; prefetch_block_count=NEXT_BLOCKS;
    prefetch_target_bank=1'b1; prefetch_valid=1'b1;
    @(posedge clk); while(!prefetch_ready) @(posedge clk);
    @(negedge clk); prefetch_valid=1'b0;
    timeout_count=0;
    while(!prefetch_done && timeout_count<100000) begin
        @(posedge clk); timeout_count=timeout_count+1;
    end
    if(!prefetch_done) begin
        $display("[ERROR] next layer timeout"); errors=errors+1;
    end
    $display("[TIMING] next blocks=56 cycles=%0d time_us=%0d.%02d writes=%0d",
             next_done_cycle-next_start_cycle,
             (next_done_cycle-next_start_cycle)/100,
             (next_done_cycle-next_start_cycle)%100,bank_b_writes);
    if(bank_b_writes!=56) errors=errors+1;

    @(negedge clk); activate_first_layer=0; activate_bank=1; activate_valid=1;
    @(posedge clk); while(!activate_ready) @(posedge clk);
    @(negedge clk); activate_valid=0;
    verify_block(32'h00000080);
    verify_block(32'h00000760);

    if(cache_error || !active_bank_valid || !active_bank)
        errors=errors+1;
    if(errors==0)
        $display("[TB_PASS] Octal stream DMA + resident/A/B Weight SRAM correct");
    else
        $display("[TB_FAIL] errors=%0d",errors);
    $finish;
end

endmodule
