`timescale 1ns/1ps

//=============================================================================
// 模块名称：tb_conv1d_agu_initial_layer
//
// 测试目标：
//   只验证编码器的第一层卷积，不测试其他卷积层，也不测试SRAM握手。
//
// 第一层卷积参数：
//   Cin          = 1
//   Cout         = 16（Cout不参与AGU地址计算，仅作为层参数说明）
//   Kernel       = 7
//   Stride       = 1
//   Dilation     = 1
//   Left padding = 6
//   Input length = 320
//   Output length= 320
//   Input base   = 0x0000_1000
//
// 穷举范围：
//   m       = 0 ~ 319
//   k_group = 0 ~ 1，ceil(Cin*Kernel/4) = ceil(7/4) = 2
//   lane    = 0 ~ 3
//
// 黄金参考公式：
//   r             = 4*k_group + lane
//   kernel_index  = r / Cin
//   channel_index = r % Cin
//   time_index    = m*stride-left_pad+kernel_index*dilation
//   byte_address  = input_base+time_index*Cin+channel_index
//
// lane有效条件：
//   1. r < Cin*Kernel，排除最后一个k_group中的K-tail；
//   2. 0 <= time_index < input_length，排除左Padding和越界位置。
//
// 本测试每组输入检查：cin_valid、valid_mask以及addr0~addr3。
//=============================================================================

module tb_conv1d_agu_initial_layer;

    localparam ADDR_WIDTH  = 32;
    localparam M_TAG_WIDTH = 9;

    localparam [ADDR_WIDTH-1:0] INPUT_BASE = 32'h0000_1000;
    localparam integer CIN           = 1;
    localparam integer KERNEL        = 7;
    localparam integer STRIDE        = 1;
    localparam integer DILATION      = 1;
    localparam integer LEFT_PAD      = 6;
    localparam integer INPUT_LENGTH  = 320;
    localparam integer OUTPUT_LENGTH = 320;
    localparam integer K_TOTAL       = CIN * KERNEL;
    localparam integer K_GROUPS      = (K_TOTAL + 3) / 4;

    // 0：只打印关键边界位置；1：打印全部640组期望值和DUT值。
    // 默认只打印m=0~6和m=319，避免日志过大。
    localparam integer PRINT_ALL_VECTORS = 0;

    //-------------------------------------------------------------------------
    // DUT输入
    //-------------------------------------------------------------------------
    reg  [ADDR_WIDTH-1:0]   input_base;
    reg  [8:0]              cin;
    reg  [3:0]              stride;
    reg  [3:0]              dilation;
    reg  [7:0]              left_pad;
    reg  [8:0]              input_length;
    reg  [11:0]             k_total;
    reg  [9:0]              k_group;
    reg  [M_TAG_WIDTH-1:0]  m;

    //-------------------------------------------------------------------------
    // DUT输出
    //-------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] addr0;
    wire [ADDR_WIDTH-1:0] addr1;
    wire [ADDR_WIDTH-1:0] addr2;
    wire [ADDR_WIDTH-1:0] addr3;
    wire [3:0]            valid_mask;
    wire                  cin_valid;

    //-------------------------------------------------------------------------
    // 参考模型和统计变量
    //-------------------------------------------------------------------------
    integer m_i;
    integer group_i;
    integer lane_i;
    integer r_i;
    integer kernel_index_i;
    integer channel_index_i;
    integer time_index_i;
    integer vector_count;
    integer lane_count;
    integer check_count;
    integer error_count;
    integer pass_vector_count;
    integer cin_error_count;
    integer mask_error_count;
    integer address_error_count;

    integer expected_r0;
    integer expected_r1;
    integer expected_r2;
    integer expected_r3;
    integer expected_time0;
    integer expected_time1;
    integer expected_time2;
    integer expected_time3;

    reg [3:0]            expected_mask;
    reg [ADDR_WIDTH-1:0] expected_addr0;
    reg [ADDR_WIDTH-1:0] expected_addr1;
    reg [ADDR_WIDTH-1:0] expected_addr2;
    reg [ADDR_WIDTH-1:0] expected_addr3;
    reg [ADDR_WIDTH-1:0] expected_lane_addr;
    reg                  vector_pass;

    conv1d_agu #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .M_TAG_WIDTH (M_TAG_WIDTH)
    ) dut (
        .input_base   (input_base),
        .cin          (cin),
        .stride       (stride),
        .dilation     (dilation),
        .left_pad     (left_pad),
        .input_length (input_length),
        .k_total      (k_total),
        .k_group      (k_group),
        .m            (m),
        .addr0        (addr0),
        .addr1        (addr1),
        .addr2        (addr2),
        .addr3        (addr3),
        .valid_mask   (valid_mask),
        .cin_valid    (cin_valid)
    );

    initial begin
        // 第一层的固定配置。
        input_base  = INPUT_BASE;
        cin         = CIN;
        stride      = STRIDE;
        dilation    = DILATION;
        left_pad    = LEFT_PAD;
        input_length = INPUT_LENGTH;
        k_total     = K_TOTAL;
        k_group     = 10'd0;
        m           = {M_TAG_WIDTH{1'b0}};

        vector_count = 0;
        lane_count   = 0;
        check_count  = 0;
        error_count  = 0;
        pass_vector_count = 0;
        cin_error_count   = 0;
        mask_error_count  = 0;
        address_error_count = 0;

        $display("============================================================");
        $display("Initial Conv AGU exhaustive test configuration");
        $display("  input_base    = 0x%08h", INPUT_BASE);
        $display("  Cin/Kernel    = %0d/%0d", CIN, KERNEL);
        $display("  stride/dilate = %0d/%0d", STRIDE, DILATION);
        $display("  left_pad      = %0d", LEFT_PAD);
        $display("  input/output  = %0d/%0d", INPUT_LENGTH, OUTPUT_LENGTH);
        $display("  K_total/groups= %0d/%0d", K_TOTAL, K_GROUPS);
        $display("  trace policy  = m=0~6 and m=319");
        $display("============================================================");

        // 穷举320个输出位置和2个K分组，共640组AGU输入。
        for (m_i = 0; m_i < OUTPUT_LENGTH; m_i = m_i + 1) begin
            for (group_i = 0; group_i < K_GROUPS;
                 group_i = group_i + 1) begin

                m       = m_i;
                k_group = group_i;

                // conv1d_agu是组合逻辑，等待1 ns使输出稳定。
                #1;

                expected_mask  = 4'b0000;
                expected_addr0 = {ADDR_WIDTH{1'b0}};
                expected_addr1 = {ADDR_WIDTH{1'b0}};
                expected_addr2 = {ADDR_WIDTH{1'b0}};
                expected_addr3 = {ADDR_WIDTH{1'b0}};
                expected_r0    = 0;
                expected_r1    = 0;
                expected_r2    = 0;
                expected_r3    = 0;
                expected_time0 = 0;
                expected_time1 = 0;
                expected_time2 = 0;
                expected_time3 = 0;

                // 对4个lane逐一计算独立于DUT的黄金参考结果。
                for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                    r_i             = 4 * group_i + lane_i;
                    kernel_index_i  = r_i / CIN;
                    channel_index_i = r_i % CIN;
                    time_index_i    = m_i * STRIDE - LEFT_PAD
                                    + kernel_index_i * DILATION;

                    expected_lane_addr = {ADDR_WIDTH{1'b0}};

                    if ((r_i < K_TOTAL) &&
                        (time_index_i >= 0) &&
                        (time_index_i < INPUT_LENGTH)) begin
                        expected_mask[lane_i] = 1'b1;
                        expected_lane_addr = INPUT_BASE
                                           + time_index_i * CIN
                                           + channel_index_i;
                    end

                    case (lane_i)
                        0: begin
                            expected_r0    = r_i;
                            expected_time0 = time_index_i;
                            expected_addr0 = expected_lane_addr;
                        end
                        1: begin
                            expected_r1    = r_i;
                            expected_time1 = time_index_i;
                            expected_addr1 = expected_lane_addr;
                        end
                        2: begin
                            expected_r2    = r_i;
                            expected_time2 = time_index_i;
                            expected_addr2 = expected_lane_addr;
                        end
                        3: begin
                            expected_r3    = r_i;
                            expected_time3 = time_index_i;
                            expected_addr3 = expected_lane_addr;
                        end
                    endcase

                    lane_count = lane_count + 1;
                end

                vector_count = vector_count + 1;
                vector_pass  = 1'b1;

                // Cin=1是当前AGU支持的合法输入通道数。
                check_count = check_count + 1;
                if (cin_valid !== 1'b1) begin
                    $display(
                        "ERROR: m=%0d k_group=%0d cin_valid expected=1 actual=%b",
                        m_i, group_i, cin_valid
                    );
                    error_count = error_count + 1;
                    cin_error_count = cin_error_count + 1;
                    vector_pass = 1'b0;
                end

                check_count = check_count + 1;
                if (valid_mask !== expected_mask) begin
                    $display(
                        "ERROR: m=%0d k_group=%0d mask expected=%b actual=%b",
                        m_i, group_i, expected_mask, valid_mask
                    );
                    error_count = error_count + 1;
                    mask_error_count = mask_error_count + 1;
                    vector_pass = 1'b0;
                end

                check_count = check_count + 4;
                if (addr0 !== expected_addr0) begin
                    $display(
                        "ERROR: m=%0d k_group=%0d lane=0 addr expected=%h actual=%h",
                        m_i, group_i, expected_addr0, addr0
                    );
                    error_count = error_count + 1;
                    address_error_count = address_error_count + 1;
                    vector_pass = 1'b0;
                end
                if (addr1 !== expected_addr1) begin
                    $display(
                        "ERROR: m=%0d k_group=%0d lane=1 addr expected=%h actual=%h",
                        m_i, group_i, expected_addr1, addr1
                    );
                    error_count = error_count + 1;
                    address_error_count = address_error_count + 1;
                    vector_pass = 1'b0;
                end
                if (addr2 !== expected_addr2) begin
                    $display(
                        "ERROR: m=%0d k_group=%0d lane=2 addr expected=%h actual=%h",
                        m_i, group_i, expected_addr2, addr2
                    );
                    error_count = error_count + 1;
                    address_error_count = address_error_count + 1;
                    vector_pass = 1'b0;
                end
                if (addr3 !== expected_addr3) begin
                    $display(
                        "ERROR: m=%0d k_group=%0d lane=3 addr expected=%h actual=%h",
                        m_i, group_i, expected_addr3, addr3
                    );
                    error_count = error_count + 1;
                    address_error_count = address_error_count + 1;
                    vector_pass = 1'b0;
                end

                if (vector_pass) begin
                    pass_vector_count = pass_vector_count + 1;
                end

                // 打印最容易观察Padding、完整窗口和末地址的关键位置。
                // 地址排列顺序统一为lane0、lane1、lane2、lane3。
                if ((PRINT_ALL_VECTORS != 0) ||
                    (m_i <= 6) ||
                    (m_i == OUTPUT_LENGTH - 1)) begin
                    $display("------------------------------------------------------------");
                    $display(
                        "TRACE m=%0d k_group=%0d vector_result=%s",
                        m_i, group_i, vector_pass ? "PASS" : "FAIL"
                    );
                    $display(
                        "  formula r    : lane0=%0d lane1=%0d lane2=%0d lane3=%0d",
                        expected_r0, expected_r1, expected_r2, expected_r3
                    );
                    $display(
                        "  formula time : lane0=%0d lane1=%0d lane2=%0d lane3=%0d",
                        expected_time0, expected_time1,
                        expected_time2, expected_time3
                    );
                    $display(
                        "  mask         : expected=%b  dut=%b",
                        expected_mask, valid_mask
                    );
                    $display(
                        "  expected addr: lane0=%08h lane1=%08h lane2=%08h lane3=%08h",
                        expected_addr0, expected_addr1,
                        expected_addr2, expected_addr3
                    );
                    $display(
                        "  dut addr     : lane0=%08h lane1=%08h lane2=%08h lane3=%08h",
                        addr0, addr1, addr2, addr3
                    );
                end
            end
        end

        $display("------------------------------------------------------------");
        $display("Initial Conv AGU exhaustive-test summary");
        $display("  vectors checked : %0d (expected 640)", vector_count);
        $display("  vectors passed  : %0d", pass_vector_count);
        $display("  vectors failed  : %0d", vector_count-pass_vector_count);
        $display("  lanes evaluated : %0d (expected 2560)", lane_count);
        $display("  output checks   : %0d (expected 3840)", check_count);
        $display("  cin_valid errors: %0d", cin_error_count);
        $display("  mask errors     : %0d", mask_error_count);
        $display("  address errors  : %0d", address_error_count);
        $display("  total errors    : %0d", error_count);

        if ((error_count == 0) &&
            (vector_count == 640) &&
            (lane_count == 2560) &&
            (check_count == 3840)) begin
            $display("AGU INITIAL-LAYER TEST PASS");
        end else begin
            $display("AGU INITIAL-LAYER TEST FAIL");
        end
        $display("------------------------------------------------------------");

        $finish;
    end

endmodule
