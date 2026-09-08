//=============================================================================
// 模块：flash_weight_reader
// 功能：把NPU的单次32-Byte权重请求转换为W25Q128JV的SPI Read Data(03h)。
//
// 事务顺序：
//   1. 手动拉低CSn；
//   2. 发送 03h + 24-bit byte address（32个SPI时钟）；
//   3. 保持CSn为低，连续执行两次128-bit接收；
//   4. 按低地址字节放在weight_data[7:0]的规则重排字节；
//   5. 拉高CSn，产生256-bit valid/ready响应。
//
// SPI模式：Mode 0、MSB first、MOSI下降沿更新、MISO上升沿采样。
//=============================================================================

module flash_weight_reader #(
    parameter SPI_DIVIDER = 16'd1,
    parameter TIMEOUT_CYCLES = 32'd100000
) (
    input                                       clk,
    input                                       rst_n,
    input                                       req_valid,
    output                                      req_ready,
    input              [31:0]                   req_addr,
    output reg                                  rsp_valid,
    input                                       rsp_ready,
    output reg         [255:0]                  rsp_data,
    output                                      flash_csn,
    output                                      flash_sclk,
    output                                      flash_mosi,
    input                                       flash_miso,
    output reg                                  busy,
    output reg                                  error
);

// spi_top寄存器的byte地址。
localparam [4:0] SPI_RX_0_ADDR = 5'h00;
localparam [4:0] SPI_RX_1_ADDR = 5'h04;
localparam [4:0] SPI_RX_2_ADDR = 5'h08;
localparam [4:0] SPI_RX_3_ADDR = 5'h0c;
localparam [4:0] SPI_CTRL_ADDR = 5'h10;
localparam [4:0] SPI_DIV_ADDR  = 5'h14;
localparam [4:0] SPI_SS_ADDR   = 5'h18;

// CTRL[12]=IE，CTRL[10]=TX_NEGEDGE，CTRL[9]=RX_NEGEDGE=0，
// CTRL[8]=GO，CTRL[7:0]=bit length。长度0表示最大128 bit。
localparam [31:0] CTRL_CMD_32  = 32'h0000_1520;
localparam [31:0] CTRL_READ_128 = 32'h0000_1500;
localparam [5:0]
S_INIT_DIV          = 6'd0,
S_INIT_DIV_WAIT     = 6'd1,
S_IDLE              = 6'd2,
S_ASSERT_CS         = 6'd3,
S_ASSERT_CS_WAIT    = 6'd4,
S_WRITE_CMD         = 6'd5,
S_WRITE_CMD_WAIT    = 6'd6,
S_START_CMD         = 6'd7,
S_START_CMD_WAIT    = 6'd8,
S_WAIT_CMD_IRQ      = 6'd9,
S_START_READ0       = 6'd10,
S_START_READ0_WAIT  = 6'd11,
S_WAIT_READ0_IRQ    = 6'd12,
S_READ0_RX0         = 6'd13,
S_READ0_RX0_WAIT    = 6'd14,
S_READ0_RX1         = 6'd15,
S_READ0_RX1_WAIT    = 6'd16,
S_READ0_RX2         = 6'd17,
S_READ0_RX2_WAIT    = 6'd18,
S_READ0_RX3         = 6'd19,
S_READ0_RX3_WAIT    = 6'd20,
S_START_READ1       = 6'd21,
S_START_READ1_WAIT  = 6'd22,
S_WAIT_READ1_IRQ    = 6'd23,
S_READ1_RX0         = 6'd24,
S_READ1_RX0_WAIT    = 6'd25,
S_READ1_RX1         = 6'd26,
S_READ1_RX1_WAIT    = 6'd27,
S_READ1_RX2         = 6'd28,
S_READ1_RX2_WAIT    = 6'd29,
S_READ1_RX3         = 6'd30,
S_READ1_RX3_WAIT    = 6'd31,
S_DEASSERT_CS       = 6'd32,
S_DEASSERT_CS_WAIT  = 6'd33,
S_RESPONSE          = 6'd34;
reg [5:0] state;
reg [23:0] flash_addr_q;
reg [127:0] read0_raw;
reg [127:0] read1_raw;
reg [31:0] timeout_count;

// APB单次访问执行器。
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
assign flash_csn = spi_ss_n[0];
assign req_ready = (state == S_IDLE) && !rsp_valid;
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

// spi_shift在MSB-first的128-bit传输中把第一个Flash字节放在[127:120]。
// 此函数把它转换成“最低Flash地址位于结果[7:0]”的NPU存储格式。

function [127:0] reverse_bytes_128;
    input              [127:0]                  value;
    integer byte_index;
    begin
        for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
            reverse_bytes_128[8*byte_index +: 8] =
            value[127-8*byte_index -: 8];
    end
endfunction

// 启动一次APB写。

task launch_apb_write;
    input              [4:0]                    target_addr;
    input              [31:0]                   target_data;
    begin
        apb_addr  <= target_addr;
        apb_wdata <= target_data;
        apb_write <= 1'b1;
        apb_start <= 1'b1;
    end
endtask

// 启动一次APB读。

task launch_apb_read;
    input              [4:0]                    target_addr;
    begin
        apb_addr  <= target_addr;
        apb_wdata <= 32'd0;
        apb_write <= 1'b0;
        apb_start <= 1'b1;
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= S_INIT_DIV;
        flash_addr_q  <= 24'd0;
        read0_raw     <= 128'd0;
        read1_raw     <= 128'd0;
        timeout_count <= 32'd0;
        apb_start     <= 1'b0;
        apb_write     <= 1'b0;
        apb_addr      <= 5'd0;
        apb_wdata     <= 32'd0;
        rsp_valid     <= 1'b0;
        rsp_data      <= 256'd0;
        busy          <= 1'b1;
        error         <= 1'b0;
    end else begin
        apb_start <= 1'b0;
        if (apb_error)
            error <= 1'b1;
        case (state)
            S_INIT_DIV: begin
                if (apb_ready) begin
                    launch_apb_write(SPI_DIV_ADDR, {16'd0, SPI_DIVIDER});
                    state <= S_INIT_DIV_WAIT;
                end
            end
            S_INIT_DIV_WAIT: begin
                if (apb_done) begin
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            end
            S_IDLE: begin
                busy <= 1'b0;
                if (req_valid && req_ready) begin
                    busy <= 1'b1;
                    timeout_count <= 32'd0;
                    if ((req_addr[31:24] != 8'd0) ||
                        (req_addr[23:0] > 24'hff_ffe0)) begin

                        // W25Q128只支持24-bit地址；一个32-Byte块也不能越过
                        // 0xffffff，否则Flash连续读会回绕到地址0。
                        error     <= 1'b1;
                        rsp_data  <= 256'd0;
                        rsp_valid <= 1'b1;

                        // 请求仍未被上层rsp_ready接收，因此busy保持为1。
                        busy      <= 1'b1;
                        state     <= S_RESPONSE;
                    end else begin
                        flash_addr_q <= req_addr[23:0];
                        state <= S_ASSERT_CS;
                    end
                end
            end
            S_ASSERT_CS: begin
                if (apb_ready) begin

                    // ASS=0时SS寄存器直接控制片选；bit0=1对应CSn拉低。
                    launch_apb_write(SPI_SS_ADDR, 32'h0000_0001);
                    state <= S_ASSERT_CS_WAIT;
                end
            end
            S_ASSERT_CS_WAIT:
                if (apb_done) state <= S_WRITE_CMD;
            S_WRITE_CMD: begin
                if (apb_ready) begin

                    // 32-bit、MSB-first：03h首先发送，随后发送24-bit地址。
                    launch_apb_write(
                        SPI_RX_0_ADDR,
                        {8'h03, flash_addr_q}
                    );

                    state <= S_WRITE_CMD_WAIT;
                end
            end
            S_WRITE_CMD_WAIT:
                if (apb_done) state <= S_START_CMD;
            S_START_CMD: begin
                if (apb_ready) begin
                    launch_apb_write(SPI_CTRL_ADDR, CTRL_CMD_32);
                    state <= S_START_CMD_WAIT;
                end
            end
            S_START_CMD_WAIT: begin
                if (apb_done) begin
                    timeout_count <= 32'd0;
                    state <= S_WAIT_CMD_IRQ;
                end
            end
            S_WAIT_CMD_IRQ: begin
                if (spi_irq) begin
                    timeout_count <= 32'd0;
                    state <= S_START_READ0;
                end else if (timeout_count >= TIMEOUT_CYCLES-1) begin
                    error    <= 1'b1;
                    rsp_data <= 256'd0;
                    state    <= S_DEASSERT_CS;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end
            S_START_READ0: begin
                if (apb_ready) begin
                    launch_apb_write(SPI_CTRL_ADDR, CTRL_READ_128);
                    state <= S_START_READ0_WAIT;
                end
            end
            S_START_READ0_WAIT: begin
                if (apb_done) begin
                    timeout_count <= 32'd0;
                    state <= S_WAIT_READ0_IRQ;
                end
            end
            S_WAIT_READ0_IRQ: begin
                if (spi_irq) begin
                    timeout_count <= 32'd0;
                    state <= S_READ0_RX0;
                end else if (timeout_count >= TIMEOUT_CYCLES-1) begin
                    error    <= 1'b1;
                    rsp_data <= 256'd0;
                    state    <= S_DEASSERT_CS;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end
            S_READ0_RX0: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_0_ADDR);
                    state <= S_READ0_RX0_WAIT;
                end
            end
            S_READ0_RX0_WAIT:
                if (apb_done) begin
                read0_raw[31:0] <= apb_rdata;
                state <= S_READ0_RX1;
            end
            S_READ0_RX1: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_1_ADDR);
                    state <= S_READ0_RX1_WAIT;
                end
            end
            S_READ0_RX1_WAIT:
                if (apb_done) begin
                read0_raw[63:32] <= apb_rdata;
                state <= S_READ0_RX2;
            end
            S_READ0_RX2: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_2_ADDR);
                    state <= S_READ0_RX2_WAIT;
                end
            end
            S_READ0_RX2_WAIT:
                if (apb_done) begin
                read0_raw[95:64] <= apb_rdata;
                state <= S_READ0_RX3;
            end
            S_READ0_RX3: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_3_ADDR);
                    state <= S_READ0_RX3_WAIT;
                end
            end
            S_READ0_RX3_WAIT:
                if (apb_done) begin
                read0_raw[127:96] <= apb_rdata;
                state <= S_START_READ1;
            end
            S_START_READ1: begin
                if (apb_ready) begin
                    launch_apb_write(SPI_CTRL_ADDR, CTRL_READ_128);
                    state <= S_START_READ1_WAIT;
                end
            end
            S_START_READ1_WAIT: begin
                if (apb_done) begin
                    timeout_count <= 32'd0;
                    state <= S_WAIT_READ1_IRQ;
                end
            end
            S_WAIT_READ1_IRQ: begin
                if (spi_irq) begin
                    timeout_count <= 32'd0;
                    state <= S_READ1_RX0;
                end else if (timeout_count >= TIMEOUT_CYCLES-1) begin
                    error    <= 1'b1;
                    rsp_data <= 256'd0;
                    state    <= S_DEASSERT_CS;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end
            S_READ1_RX0: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_0_ADDR);
                    state <= S_READ1_RX0_WAIT;
                end
            end
            S_READ1_RX0_WAIT:
                if (apb_done) begin
                read1_raw[31:0] <= apb_rdata;
                state <= S_READ1_RX1;
            end
            S_READ1_RX1: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_1_ADDR);
                    state <= S_READ1_RX1_WAIT;
                end
            end
            S_READ1_RX1_WAIT:
                if (apb_done) begin
                read1_raw[63:32] <= apb_rdata;
                state <= S_READ1_RX2;
            end
            S_READ1_RX2: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_2_ADDR);
                    state <= S_READ1_RX2_WAIT;
                end
            end
            S_READ1_RX2_WAIT:
                if (apb_done) begin
                read1_raw[95:64] <= apb_rdata;
                state <= S_READ1_RX3;
            end
            S_READ1_RX3: begin
                if (apb_ready) begin
                    launch_apb_read(SPI_RX_3_ADDR);
                    state <= S_READ1_RX3_WAIT;
                end
            end
            S_READ1_RX3_WAIT: begin
                if (apb_done) begin
                    read1_raw[127:96] <= apb_rdata;
                    rsp_data <= {
                    reverse_bytes_128({apb_rdata, read1_raw[95:0]}),
                    reverse_bytes_128(read0_raw)
                    };
                    state <= S_DEASSERT_CS;
                end
            end
            S_DEASSERT_CS: begin
                if (apb_ready) begin
                    launch_apb_write(SPI_SS_ADDR, 32'h0000_0000);
                    state <= S_DEASSERT_CS_WAIT;
                end
            end
            S_DEASSERT_CS_WAIT: begin
                if (apb_done) begin
                    rsp_valid <= 1'b1;
                    busy      <= 1'b1;
                    state     <= S_RESPONSE;
                end
            end
            S_RESPONSE: begin
                busy <= 1'b1;
                if (rsp_valid && rsp_ready) begin
                    rsp_valid <= 1'b0;
                    busy      <= 1'b0;
                    state <= S_IDLE;
                end
            end
            default: begin
                error <= 1'b1;
                state <= S_INIT_DIV;
            end
        endcase
    end
end

endmodule
