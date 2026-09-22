`timescale 1ns/1ps

//=============================================================================
// Octal DDR Weight Cache
//
// 存储组织与原weight_cache_ab一致：
//   - 第一层4×256-bit常驻SRAM；
//   - 后续层使用两组4096×256-bit Weight SRAM A/B；
//   - NPU读取活动Bank时，DMA只写非活动Bank。
//
// 与原SPI版本的区别：外存侧不是spi_top，而是“命令 + 16-bit接收流”。
// 该边界应连接真正的S28HS512T OPI控制器及CDC FIFO。
//=============================================================================

// [中文注释-自动补充]
// 模块作用：Octal DDR权重A/B缓存。
// 关键变量/接口：命令侧发起连续读，数据侧经打包和DMA写入Local A/B，再由计算端读取。
// 握手约定：valid与ready在同一上升沿同时为1才完成一次传输；反压期间数据必须保持。
// 位宽约定：地址通常按Byte计，Weight块为256 bit，Activation/Weight基本元素为signed INT8。
// -----------------------------------------------------------------------------
module weight_cache_ab_octal #(
    parameter CACHE_BLOCKS           = 4096,
    parameter CACHE_INDEX_WIDTH      = 12,
    parameter FIRST_LAYER_FLASH_BASE = 24'h000000,
    parameter FIRST_LAYER_BLOCKS     = 16'd4
) (
    input                                       clk,
    input                                       rst_n,
    input                                       req_valid,
    output                                      req_ready,
    input              [31:0]                   req_addr,
    output reg                                  rsp_valid,
    input                                       rsp_ready,
    output reg         [255:0]                  rsp_data,
    input                                       prefetch_valid,
    output                                      prefetch_ready,
    input              [23:0]                   prefetch_flash_base,
    input              [15:0]                   prefetch_block_count,
    input                                       prefetch_target_bank,
    output reg                                  prefetch_done,
    input                                       activate_valid,
    output                                      activate_ready,
    input                                       activate_first_layer,
    input                                       activate_bank,
    output reg                                  active_first_layer,
    output reg                                  active_bank,
    output                                      active_bank_valid,
    output reg                                  first_layer_ready,
    output                                      cache_busy,
    output reg                                  cache_error,

    // 外部S28 OPI控制器边界。
    output                                      octal_cmd_valid,
    input                                       octal_cmd_ready,
    output             [23:0]                   octal_cmd_flash_base,
    output             [23:0]                   octal_cmd_byte_count,
    input                                       octal_rx_valid,
    output                                      octal_rx_ready,
    input              [15:0]                   octal_rx_data,
    input                                       octal_rx_last,
    input                                       octal_rx_error
);

localparam [2:0] C_BOOT_LAUNCH = 3'd0,
C_LOAD_LAUNCH = 3'd1,
C_LOAD_WAIT   = 3'd2,
C_IDLE        = 3'd3;
localparam [1:0] TARGET_FIRST  = 2'd0,
TARGET_BANK_A = 2'd1,
TARGET_BANK_B = 2'd2;
localparam FIRST_INDEX_WIDTH = $clog2(FIRST_LAYER_BLOCKS);
reg [2:0]  control_state;
reg        boot_load;
reg [1:0]  load_target;
reg [23:0] load_base_q;
reg [15:0] load_count_q;
reg        dma_cmd_valid;
reg        prefetch_armed;
reg        first_layer_valid;
reg [23:0] bank_base_a;
reg [23:0] bank_base_b;
reg [15:0] bank_blocks_a;
reg [15:0] bank_blocks_b;
reg        bank_valid_a;
reg        bank_valid_b;
reg        read_pending;
reg        read_source_first_q;
reg        read_bank_q;
wire       dma_cmd_ready;
wire       dma_block_valid;
wire       dma_block_ready;
wire [15:0] dma_block_index;
wire [255:0] dma_block_data;
wire       dma_done;
wire       dma_busy;
wire       dma_error;
wire selected_bank_valid = active_first_layer ? first_layer_valid :
    (active_bank ? bank_valid_b : bank_valid_a);
wire [23:0] selected_bank_base = active_first_layer ? FIRST_LAYER_FLASH_BASE :
    (active_bank ? bank_base_b : bank_base_a);
wire [15:0] selected_bank_blocks = active_first_layer ? FIRST_LAYER_BLOCKS :
    (active_bank ? bank_blocks_b : bank_blocks_a);
wire [31:0] request_offset = req_addr - {8'd0,selected_bank_base};
wire [26:0] request_block_index = request_offset[31:5];
wire request_in_range = (req_addr[31:24] == 8'd0) &&
    (req_addr >= {8'd0,selected_bank_base}) &&
    (request_offset[4:0] == 5'd0) &&
    (request_block_index < selected_bank_blocks) &&
    (active_first_layer ?
    (request_block_index < FIRST_LAYER_BLOCKS) :
    (request_block_index < CACHE_BLOCKS));
wire load_conflicts_active = (control_state != C_IDLE) &&
    ((active_first_layer && (load_target == TARGET_FIRST)) ||
    (!active_first_layer && !active_bank && (load_target == TARGET_BANK_A)) ||
    (!active_first_layer &&  active_bank && (load_target == TARGET_BANK_B)));
wire dma_write_fire   = dma_block_valid && dma_block_ready;
wire npu_read_fire    = req_valid && req_ready && request_in_range;
wire first_sram_write = dma_write_fire && (load_target == TARGET_FIRST);
wire bank_a_sram_write= dma_write_fire && (load_target == TARGET_BANK_A);
wire bank_b_sram_write= dma_write_fire && (load_target == TARGET_BANK_B);
wire first_sram_read  = npu_read_fire && active_first_layer;
wire bank_a_sram_read = npu_read_fire && !active_first_layer && !active_bank;
wire bank_b_sram_read = npu_read_fire && !active_first_layer && active_bank;
wire [FIRST_INDEX_WIDTH-1:0] first_sram_addr = first_sram_write ?
    dma_block_index[FIRST_INDEX_WIDTH-1:0] :
    request_block_index[FIRST_INDEX_WIDTH-1:0];
wire [CACHE_INDEX_WIDTH-1:0] bank_a_sram_addr = bank_a_sram_write ?
    dma_block_index[CACHE_INDEX_WIDTH-1:0] :
    request_block_index[CACHE_INDEX_WIDTH-1:0];
wire [CACHE_INDEX_WIDTH-1:0] bank_b_sram_addr = bank_b_sram_write ?
    dma_block_index[CACHE_INDEX_WIDTH-1:0] :
    request_block_index[CACHE_INDEX_WIDTH-1:0];
wire [255:0] first_sram_rdata;
wire [255:0] bank_a_sram_rdata;
wire [255:0] bank_b_sram_rdata;
wire first_sram_rvalid;
wire bank_a_sram_rvalid;
wire bank_b_sram_rvalid;
wire selected_read_rvalid = read_source_first_q ? first_sram_rvalid :
    (read_bank_q ? bank_b_sram_rvalid : bank_a_sram_rvalid);
wire [255:0] selected_read_data = read_source_first_q ? first_sram_rdata :
    (read_bank_q ? bank_b_sram_rdata : bank_a_sram_rdata);
// 连续赋值：组合生成active_bank_valid及其相邻接口信号，表达握手、选择或地址关系。
assign active_bank_valid = selected_bank_valid;
assign req_ready = selected_bank_valid && !rsp_valid && !read_pending &&
    !load_conflicts_active;
// 连续赋值：组合生成prefetch_ready及其相邻接口信号，表达握手、选择或地址关系。
assign prefetch_ready = prefetch_armed && (control_state == C_IDLE) &&
    (active_first_layer || !selected_bank_valid ||
    (prefetch_target_bank != active_bank));
// 连续赋值：组合生成activate_ready及其相邻接口信号，表达握手、选择或地址关系。
assign activate_ready = (control_state == C_IDLE) && !rsp_valid && !read_pending &&
    (activate_first_layer ? first_layer_valid :
    (activate_bank ? bank_valid_b : bank_valid_a));
// 连续赋值：组合生成cache_busy及其相邻接口信号，表达握手、选择或地址关系。
assign cache_busy = (control_state != C_IDLE) || dma_busy || dma_cmd_valid;
assign dma_block_ready = (load_target == TARGET_FIRST) ?
    (dma_block_index < FIRST_LAYER_BLOCKS) :
    (dma_block_index < CACHE_BLOCKS);
opentitan_sram_1p_adapter #(
    .WIDTH                       (256),
    .DEPTH                       (FIRST_LAYER_BLOCKS),
    .DATA_BITS_PER_MASK          (8)
) u_first_layer_sram (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .req_i                       (first_sram_write || first_sram_read),
    .write_i                     (first_sram_write),
    .addr_i                      (first_sram_addr),
    .wdata_i                     (dma_block_data),
    .wmask_i                     (32'hffff_ffff),
    .rdata_o                     (first_sram_rdata),
    .rvalid_o                    (first_sram_rvalid)
);

opentitan_sram_1p_adapter #(
    .WIDTH                       (256),
    .DEPTH                       (CACHE_BLOCKS),
    .DATA_BITS_PER_MASK          (8)
) u_weight_sram_a (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .req_i                       (bank_a_sram_write || bank_a_sram_read),
    .write_i                     (bank_a_sram_write),
    .addr_i                      (bank_a_sram_addr),
    .wdata_i                     (dma_block_data),
    .wmask_i                     (32'hffff_ffff),
    .rdata_o                     (bank_a_sram_rdata),
    .rvalid_o                    (bank_a_sram_rvalid)
);

opentitan_sram_1p_adapter #(
    .WIDTH                       (256),
    .DEPTH                       (CACHE_BLOCKS),
    .DATA_BITS_PER_MASK          (8)
) u_weight_sram_b (
    .clk_i                       (clk),
    .rst_ni                      (rst_n),
    .req_i                       (bank_b_sram_write || bank_b_sram_read),
    .write_i                     (bank_b_sram_write),
    .addr_i                      (bank_b_sram_addr),
    .wdata_i                     (dma_block_data),
    .wmask_i                     (32'hffff_ffff),
    .rdata_o                     (bank_b_sram_rdata),
    .rvalid_o                    (bank_b_sram_rvalid)
);

weight_stream_dma u_dma (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .cmd_valid                   (dma_cmd_valid),
    .cmd_ready                   (dma_cmd_ready),
    .cmd_flash_base              (load_base_q),
    .cmd_block_count             (load_count_q),
    .ext_cmd_valid               (octal_cmd_valid),
    .ext_cmd_ready               (octal_cmd_ready),
    .ext_cmd_flash_base          (octal_cmd_flash_base),
    .ext_cmd_byte_count          (octal_cmd_byte_count),
    .rx_valid                    (octal_rx_valid),
    .rx_ready                    (octal_rx_ready),
    .rx_data                     (octal_rx_data),
    .rx_last                     (octal_rx_last),
    .rx_error                    (octal_rx_error),
    .block_valid                 (dma_block_valid),
    .block_ready                 (dma_block_ready),
    .block_index                 (dma_block_index),
    .block_data                  (dma_block_data),
    .done                        (dma_done),
    .busy                        (dma_busy),
    .error                       (dma_error)
);

// 时序逻辑：在时钟沿更新control_state、boot_load、load_target、load_base_q、load_count_q、dma_cmd_valid；复位分支负责恢复确定的空闲状态。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        control_state       <= C_BOOT_LAUNCH;
        boot_load           <= 1'b1;
        load_target         <= TARGET_FIRST;
        load_base_q         <= FIRST_LAYER_FLASH_BASE;
        load_count_q        <= FIRST_LAYER_BLOCKS;
        dma_cmd_valid       <= 1'b0;
        prefetch_armed      <= 1'b1;
        bank_base_a         <= 24'd0;
        bank_base_b         <= 24'd0;
        bank_blocks_a       <= 16'd0;
        bank_blocks_b       <= 16'd0;
        first_layer_valid   <= 1'b0;
        bank_valid_a        <= 1'b0;
        bank_valid_b        <= 1'b0;
        active_first_layer  <= 1'b0;
        active_bank         <= 1'b0;
        first_layer_ready   <= 1'b0;
        prefetch_done       <= 1'b0;
        cache_error         <= 1'b0;
        rsp_valid           <= 1'b0;
        rsp_data            <= 256'd0;
        read_pending        <= 1'b0;
        read_source_first_q <= 1'b0;
        read_bank_q         <= 1'b0;
    end else begin
        prefetch_done <= 1'b0;
        if (!prefetch_valid)
            prefetch_armed <= 1'b1;
        if (dma_error)
            cache_error <= 1'b1;
        if (req_valid && req_ready) begin
            if (!request_in_range) begin
                rsp_data    <= 256'd0;
                rsp_valid   <= 1'b1;
                cache_error <= 1'b1;
            end else begin
                read_pending        <= 1'b1;
                read_source_first_q <= active_first_layer;
                read_bank_q         <= active_bank;
            end
        end
        if (read_pending && selected_read_rvalid) begin
            rsp_data     <= selected_read_data;
            rsp_valid    <= 1'b1;
            read_pending <= 1'b0;
        end else if (rsp_valid && rsp_ready) begin
            rsp_valid <= 1'b0;
        end
        if (activate_valid && activate_ready) begin
            active_first_layer <= activate_first_layer;
            if (!activate_first_layer)
                active_bank <= activate_bank;
        end
        case (control_state)
            C_BOOT_LAUNCH: begin
                load_target       <= TARGET_FIRST;
                load_base_q       <= FIRST_LAYER_FLASH_BASE;
                load_count_q      <= FIRST_LAYER_BLOCKS;
                first_layer_valid <= 1'b0;
                control_state     <= C_LOAD_LAUNCH;
            end
            C_LOAD_LAUNCH: begin
                if (!dma_cmd_valid && dma_cmd_ready)
                    dma_cmd_valid <= 1'b1;
                else if (dma_cmd_valid && dma_cmd_ready) begin
                    dma_cmd_valid <= 1'b0;
                    if (load_target == TARGET_BANK_B) begin
                        bank_base_b   <= load_base_q;
                        bank_blocks_b <= load_count_q;
                    end else if (load_target == TARGET_BANK_A) begin
                        bank_base_a   <= load_base_q;
                        bank_blocks_a <= load_count_q;
                    end
                    control_state <= C_LOAD_WAIT;
                end
            end
            C_LOAD_WAIT: begin
                if (dma_done) begin
                    if (!dma_error) begin
                        if (load_target == TARGET_FIRST)
                            first_layer_valid <= 1'b1;
                        else if (load_target == TARGET_BANK_B)
                            bank_valid_b <= 1'b1;
                        else
                        bank_valid_a <= 1'b1;
                        if (boot_load) begin
                            active_first_layer <= 1'b1;
                            active_bank        <= 1'b0;
                            first_layer_ready  <= 1'b1;
                            boot_load          <= 1'b0;
                        end else begin
                            prefetch_done <= 1'b1;
                        end
                    end
                    control_state <= C_IDLE;
                end
            end
            C_IDLE: begin
                if (prefetch_valid && prefetch_ready) begin
                    prefetch_armed <= 1'b0;
                    if ((prefetch_block_count == 0) ||
                        (prefetch_block_count > CACHE_BLOCKS)) begin
                        cache_error   <= 1'b1;
                        prefetch_done <= 1'b1;
                    end else begin
                        load_target  <= prefetch_target_bank ?
                            TARGET_BANK_B : TARGET_BANK_A;
                        load_base_q  <= prefetch_flash_base;
                        load_count_q <= prefetch_block_count;
                        if (prefetch_target_bank)
                            bank_valid_b <= 1'b0;
                        else
                        bank_valid_a <= 1'b0;
                        control_state <= C_LOAD_LAUNCH;
                    end
                end
            end
            default: begin
                cache_error   <= 1'b1;
                control_state <= C_BOOT_LAUNCH;
            end
        endcase
    end
end

endmodule
