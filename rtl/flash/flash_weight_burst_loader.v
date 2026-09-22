//=============================================================================
// 模块：flash_weight_burst_loader
// 功能：使用W25Q128 0Bh FAST READ连续读取多个32-Byte权重块。
//
// 只发送一次 0Bh + 24-bit地址 + 8-bit dummy，随后保持CSn为低，连续
// 输出block_count个256-bit块。这样避免每个block重复发送命令和地址。
//=============================================================================

// [中文注释-自动补充]
// 模块作用：SPI Flash权重Burst搬运控制器。
// 关键变量/接口：一次命令连续读取多个32-Byte权重块；block_valid/ready对下游反压，done表示整段完成。
// 握手约定：valid与ready在同一上升沿同时为1才完成一次传输；反压期间数据必须保持。
// 位宽约定：地址通常按Byte计，Weight块为256 bit，Activation/Weight基本元素为signed INT8。
// -----------------------------------------------------------------------------
module flash_weight_burst_loader #(
    parameter SPI_DIVIDER = 16'd1,
    parameter TIMEOUT_CYCLES = 32'd100000
) (
    input                                       clk,
    input                                       rst_n,
    input                                       cmd_valid,
    output                                      cmd_ready,
    input              [23:0]                   cmd_flash_base,
    input              [15:0]                   cmd_block_count,
    output reg                                  block_valid,
    input                                       block_ready,
    output reg         [15:0]                   block_index,
    output reg         [255:0]                  block_data,
    output reg                                  done,
    output reg                                  busy,
    output reg                                  error,
    output                                      flash_csn,
    output                                      flash_sclk,
    output                                      flash_mosi,
    input                                       flash_miso
);

localparam [4:0] SPI_RX_0_ADDR = 5'h00;
localparam [4:0] SPI_TX_1_ADDR = 5'h04;
localparam [4:0] SPI_CTRL_ADDR = 5'h10;
localparam [4:0] SPI_DIV_ADDR  = 5'h14;
localparam [4:0] SPI_SS_ADDR   = 5'h18;

// 0Bh + 24-bit地址 + 8-bit dummy，共40bit。
localparam [31:0] CTRL_PREFIX_40 = 32'h0000_1528;

// 长度字段为0代表SPI_MAX_CHAR=128。
localparam [31:0] CTRL_READ_128  = 32'h0000_1500;
localparam [4:0]
S_INIT_DIV       = 5'd0,
S_INIT_DIV_WAIT  = 5'd1,
S_IDLE           = 5'd2,
S_ASSERT_CS      = 5'd3,
S_ASSERT_WAIT    = 5'd4,
S_WRITE_TX0      = 5'd5,
S_WRITE_TX0_WAIT = 5'd6,
S_WRITE_TX1      = 5'd7,
S_WRITE_TX1_WAIT = 5'd8,
S_START_PREFIX   = 5'd9,
S_PREFIX_WAIT    = 5'd10,
S_WAIT_PREFIX    = 5'd11,
S_START_CHUNK    = 5'd12,
S_START_CHUNK_WAIT = 5'd13,
S_WAIT_CHUNK     = 5'd14,
S_READ_WORD      = 5'd15,
S_READ_WORD_WAIT = 5'd16,
S_BLOCK_OUTPUT   = 5'd17,
S_DEASSERT_CS    = 5'd18,
S_DEASSERT_WAIT  = 5'd19,
S_FINISH         = 5'd20;
reg [4:0] state;
reg [23:0] base_q;
reg [15:0] count_q;
reg        chunk_select;
reg [1:0]  rx_word_index;
reg [127:0] raw_chunk;
reg [127:0] first_chunk;
reg [31:0] timeout_count;
reg         apb_start;
wire        apb_ready;
reg         apb_write;
reg  [4:0]  apb_addr;
reg  [31:0] apb_wdata;
wire        apb_done;
wire [31:0] apb_rdata;
wire        apb_error;
wire [4:0]  paddr;
wire [31:0] pwdata;
wire [31:0] prdata;
wire        pwrite;
wire        psel;
wire        penable;
wire        pready;
wire        pslverr;
wire        spi_irq;
wire [7:0]  spi_ss_n;
wire [40:0] requested_bytes = {25'd0, cmd_block_count} << 5;
wire [40:0] end_address_ext = {17'd0, cmd_flash_base} + requested_bytes;
// 连续赋值：组合生成cmd_ready及其相邻接口信号，表达握手、选择或地址关系。
assign cmd_ready  = (state == S_IDLE);
assign flash_csn = spi_ss_n[0];
apb_single_master u_apb_master (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .start                       (apb_start),
    .ready                       (apb_ready),
    .write                       (apb_write),
    .addr                        (apb_addr),
    .wdata                       (apb_wdata),
    .done                        (apb_done),
    .rdata                       (apb_rdata),
    .paddr                       (paddr),
    .pwdata                      (pwdata),
    .prdata                      (prdata),
    .pwrite                      (pwrite),
    .psel                        (psel),
    .penable                     (penable),
    .pready                      (pready),
    .pslverr                     (pslverr),
    .error                       (apb_error)
);

spi_top u_spi_top (
    .PCLK                        (clk),
    .PRESETN                     (rst_n),
    .PADDR                       (paddr),
    .PWDATA                      (pwdata),
    .PRDATA                      (prdata),
    .PSEL                        (psel),
    .PWRITE                      (pwrite),
    .PENABLE                     (penable),
    .PREADY                      (pready),
    .PSLVERR                     (pslverr),
    .IRQ                         (spi_irq),
    .ss_pad_o                    (spi_ss_n),
    .sclk_pad_o                  (flash_sclk),
    .mosi_pad_o                  (flash_mosi),
    .miso_pad_i                  (flash_miso)
);

// 辅助过程reverse_bytes_128：封装重复计算或测试激励，便于独立检查输入、输出及边界条件。
function [127:0] reverse_bytes_128;
    input              [127:0]                  value;
    integer byte_index;
    begin
        for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
            reverse_bytes_128[8*byte_index +: 8] =
            value[127-8*byte_index -: 8];
    end
endfunction

// 辅助过程launch_write：封装重复计算或测试激励，便于独立检查输入、输出及边界条件。
task launch_write;
    input              [4:0]                    target_addr;
    input              [31:0]                   target_data;
    begin
        apb_addr <= target_addr;
        apb_wdata <= target_data;
        apb_write <= 1'b1;
        apb_start <= 1'b1;
    end
endtask

// 辅助过程launch_read：封装重复计算或测试激励，便于独立检查输入、输出及边界条件。
task launch_read;
    input              [4:0]                    target_addr;
    begin
        apb_addr <= target_addr;
        apb_wdata <= 32'd0;
        apb_write <= 1'b0;
        apb_start <= 1'b1;
    end
endtask

// 时序逻辑：在时钟沿更新state、base_q、count_q、chunk_select、rx_word_index、raw_chunk；复位分支负责恢复确定的空闲状态。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= S_INIT_DIV;
        base_q        <= 24'd0;
        count_q       <= 16'd0;
        chunk_select  <= 1'b0;
        rx_word_index <= 2'd0;
        raw_chunk     <= 128'd0;
        first_chunk   <= 128'd0;
        timeout_count <= 32'd0;
        apb_start     <= 1'b0;
        apb_write     <= 1'b0;
        apb_addr      <= 5'd0;
        apb_wdata     <= 32'd0;
        block_valid   <= 1'b0;
        block_index   <= 16'd0;
        block_data    <= 256'd0;
        done          <= 1'b0;
        busy          <= 1'b1;
        error         <= 1'b0;
    end else begin
        apb_start <= 1'b0;
        done      <= 1'b0;
        if (apb_error)
            error <= 1'b1;
        case (state)
            S_INIT_DIV: begin
                if (apb_ready) begin
                    launch_write(SPI_DIV_ADDR, {16'd0, SPI_DIVIDER});
                    state <= S_INIT_DIV_WAIT;
                end
            end
            S_INIT_DIV_WAIT:
                if (apb_done) begin
                busy <= 1'b0;
                state <= S_IDLE;
            end
            S_IDLE: begin
                busy <= 1'b0;
                if (cmd_valid && cmd_ready) begin
                    busy <= 1'b1;
                    if ((cmd_block_count == 0) ||
                        (end_address_ext > 41'h0_0100_0000)) begin
                        error <= 1'b1;
                        state <= S_FINISH;
                    end else begin
                        base_q        <= cmd_flash_base;
                        count_q       <= cmd_block_count;
                        block_index   <= 16'd0;
                        chunk_select  <= 1'b0;
                        timeout_count <= 32'd0;
                        state         <= S_ASSERT_CS;
                    end
                end
            end
            S_ASSERT_CS: begin
                if (apb_ready) begin
                    launch_write(SPI_SS_ADDR, 32'd1);
                    state <= S_ASSERT_WAIT;
                end
            end
            S_ASSERT_WAIT:
                if (apb_done) state <= S_WRITE_TX0;
            S_WRITE_TX0: begin
                if (apb_ready) begin

                    // data[31:8]=24-bit地址，data[7:0]=dummy byte。
                    launch_write(SPI_RX_0_ADDR, {base_q, 8'h00});
                    state <= S_WRITE_TX0_WAIT;
                end
            end
            S_WRITE_TX0_WAIT:
                if (apb_done) state <= S_WRITE_TX1;
            S_WRITE_TX1: begin
                if (apb_ready) begin

                    // 40-bit MSB-first传输的最高8bit位于data[39:32]。
                    launch_write(SPI_TX_1_ADDR, 32'h0000_000b);
                    state <= S_WRITE_TX1_WAIT;
                end
            end
            S_WRITE_TX1_WAIT:
                if (apb_done) state <= S_START_PREFIX;
            S_START_PREFIX: begin
                if (apb_ready) begin
                    launch_write(SPI_CTRL_ADDR, CTRL_PREFIX_40);
                    state <= S_PREFIX_WAIT;
                end
            end
            S_PREFIX_WAIT:
                if (apb_done) begin
                timeout_count <= 0;
                state <= S_WAIT_PREFIX;
            end
            S_WAIT_PREFIX: begin
                if (spi_irq) begin
                    timeout_count <= 0;
                    chunk_select <= 0;
                    state <= S_START_CHUNK;
                end else if (timeout_count >= TIMEOUT_CYCLES-1) begin
                    error <= 1'b1;
                    state <= S_DEASSERT_CS;
                end else timeout_count <= timeout_count + 1'b1;
            end
            S_START_CHUNK: begin
                if (apb_ready) begin
                    launch_write(SPI_CTRL_ADDR, CTRL_READ_128);
                    state <= S_START_CHUNK_WAIT;
                end
            end
            S_START_CHUNK_WAIT:
                if (apb_done) begin
                timeout_count <= 0;
                state <= S_WAIT_CHUNK;
            end
            S_WAIT_CHUNK: begin
                if (spi_irq) begin
                    rx_word_index <= 0;
                    timeout_count <= 0;
                    state <= S_READ_WORD;
                end else if (timeout_count >= TIMEOUT_CYCLES-1) begin
                    error <= 1'b1;
                    state <= S_DEASSERT_CS;
                end else timeout_count <= timeout_count + 1'b1;
            end
            S_READ_WORD: begin
                if (apb_ready) begin
                    launch_read({rx_word_index, 2'b00});
                    state <= S_READ_WORD_WAIT;
                end
            end
            S_READ_WORD_WAIT: begin
                if (apb_done) begin
                    raw_chunk[32*rx_word_index +: 32] <= apb_rdata;
                    if (rx_word_index != 2'd3) begin
                        rx_word_index <= rx_word_index + 1'b1;
                        state <= S_READ_WORD;
                    end else if (!chunk_select) begin
                        first_chunk <= {apb_rdata, raw_chunk[95:0]};
                        chunk_select <= 1'b1;
                        state <= S_START_CHUNK;
                    end else begin
                        block_data <= {
                        reverse_bytes_128({apb_rdata, raw_chunk[95:0]}),
                        reverse_bytes_128(first_chunk)
                        };
                        block_valid <= 1'b1;
                        state <= S_BLOCK_OUTPUT;
                    end
                end
            end
            S_BLOCK_OUTPUT: begin
                if (block_valid && block_ready) begin
                    block_valid <= 1'b0;
                    if ((block_index + 1'b1) < count_q) begin
                        block_index  <= block_index + 1'b1;
                        chunk_select <= 1'b0;
                        state <= S_START_CHUNK;
                    end else begin
                        state <= S_DEASSERT_CS;
                    end
                end
            end
            S_DEASSERT_CS: begin
                if (apb_ready) begin
                    launch_write(SPI_SS_ADDR, 32'd0);
                    state <= S_DEASSERT_WAIT;
                end
            end
            S_DEASSERT_WAIT:
                if (apb_done) state <= S_FINISH;
            S_FINISH: begin
                done <= 1'b1;
                busy <= 1'b0;
                state <= S_IDLE;
            end
            default: begin
                error <= 1'b1;
                state <= S_INIT_DIV;
            end
        endcase
    end
end

endmodule
