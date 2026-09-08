`timescale 1ns/1ps

//=============================================================================
// Testbench：tb_conv1d_agu
//
// 依据当前 E:/lyra 编码器配置逐层验证全部 30 个 Conv1d：
//   channels       = 16
//   channel_mults  = (2, 4, 8, 16)
//   strides        = (2, 4, 5, 8)
//   dilations      = (1, 3, 9)
//   input frame    = 320 samples
//   pad_mode       = constant（左侧无效位置补 0）
//
// 对每一层穷举：m、k_group、lane，并与以下软件公式逐项比较：
//   r             = 4*k_group + lane
//   kernel_index  = r / Cin
//   channel_index = r % Cin
//   time_index    = m*stride-left_pad+kernel_index*dilation
//   address       = input_base+time_index*Cin+channel_index
//
// 检查内容：cin_valid、4-bit valid_mask、4 路地址、K-tail 和左 Padding。
//=============================================================================
module tb_conv1d_agu;

localparam ADDR_WIDTH  = 32;
localparam M_TAG_WIDTH = 9;
localparam INPUT_BASE  = 32'h0000_1000;

// TRACE_LAYER_ID=1：默认详细打印初始卷积层；设为0时打印所有层。
// PRINT_ALL_VECTORS=0：只打印目标层m=0~6和最后一个m；设为1时打印全部向量。
localparam integer TRACE_LAYER_ID    = 1;
localparam integer PRINT_ALL_VECTORS = 0;

reg  [ADDR_WIDTH-1:0]  input_base;
reg  [8:0]             cin;
reg  [3:0]             stride;
reg  [3:0]             dilation;
reg  [7:0]             left_pad;
reg  [8:0]             input_length;
reg  [11:0]            k_total;
reg  [9:0]             k_group;
reg  [M_TAG_WIDTH-1:0] m;

wire [ADDR_WIDTH-1:0] addr0;
wire [ADDR_WIDTH-1:0] addr1;
wire [ADDR_WIDTH-1:0] addr2;
wire [ADDR_WIDTH-1:0] addr3;
wire [3:0]            valid_mask;
wire                  cin_valid;

integer error_count;
integer check_count;
integer layer_count;

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

// 检查编码器中的一个实际 Conv1d 层。
task check_layer;
    input integer layer_id;
    input integer cin_i;
    input integer cout_i;
    input integer kernel_i;
    input integer stride_i;
    input integer dilation_i;
    input integer left_pad_i;
    input integer input_length_i;
    input integer output_length_i;

    integer layer_error_start;
    integer calculated_output_length;
    integer calculated_left_pad;
    integer k_total_i;
    integer k_groups_i;
    integer m_i;
    integer group_i;
    integer lane_i;
    integer r_i;
    integer kernel_index_i;
    integer channel_index_i;
    integer time_index_i;
    integer expected_r0;
    integer expected_r1;
    integer expected_r2;
    integer expected_r3;
    integer expected_time0;
    integer expected_time1;
    integer expected_time2;
    integer expected_time3;
    reg [3:0] expected_mask;
    reg [ADDR_WIDTH-1:0] expected_addr0;
    reg [ADDR_WIDTH-1:0] expected_addr1;
    reg [ADDR_WIDTH-1:0] expected_addr2;
    reg [ADDR_WIDTH-1:0] expected_addr3;
    reg [ADDR_WIDTH-1:0] expected_lane_addr;
    reg vector_pass;

    begin
        layer_count       = layer_count + 1;
        layer_error_start = error_count;
        k_total_i         = cin_i * kernel_i;
        k_groups_i        = (k_total_i + 3) / 4;

        // CausalConv1d 源码中的左 Padding 定义。
        calculated_left_pad =
            dilation_i * (kernel_i - 1) + (1 - stride_i);

        // PyTorch Conv1d 在只有左 Padding 时的输出长度。
        calculated_output_length =
            (input_length_i + left_pad_i
             - dilation_i * (kernel_i - 1) - 1) / stride_i + 1;

        if (left_pad_i != calculated_left_pad) begin
            $display(
                "META ERROR layer=%0d: left_pad expected=%0d configured=%0d",
                layer_id, calculated_left_pad, left_pad_i
            );
            error_count = error_count + 1;
        end

        if (output_length_i != calculated_output_length) begin
            $display(
                "META ERROR layer=%0d: M expected=%0d configured=%0d",
                layer_id, calculated_output_length, output_length_i
            );
            error_count = error_count + 1;
        end
        // 配置参数
        input_base  = INPUT_BASE;
        cin         = cin_i;
        stride      = stride_i;
        dilation    = dilation_i;
        left_pad    = left_pad_i;
        input_length = input_length_i;
        k_total     = k_total_i;

        if ((TRACE_LAYER_ID == 0) || (layer_id == TRACE_LAYER_ID)) begin
            $display("============================================================");
            $display("AGU TRACE CONFIG: layer=%0d", layer_id);
            $display("  input_base     = 0x%08h", INPUT_BASE);
            $display("  Cin/Cout       = %0d/%0d", cin_i, cout_i);
            $display("  Kernel/Stride  = %0d/%0d", kernel_i, stride_i);
            $display("  Dilation/Pad   = %0d/%0d", dilation_i, left_pad_i);
            $display("  input/output   = %0d/%0d", input_length_i, output_length_i);
            $display("  K_total/groups = %0d/%0d", k_total_i, k_groups_i);
            $display("============================================================");
        end
        // 逐个 m、k_group 检查。
        for (m_i = 0; m_i < output_length_i; m_i = m_i + 1) begin
            for (group_i = 0; group_i < k_groups_i;
                 group_i = group_i + 1) begin
                m       = m_i;
                k_group = group_i;
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

                for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                    r_i             = 4 * group_i + lane_i;           //展平位置
                    kernel_index_i  = r_i / cin_i;                    //卷积核位置
                    channel_index_i = r_i % cin_i;                    //通道位置
                    time_index_i    = m_i * stride_i - left_pad_i      //时间位置
                                    + kernel_index_i * dilation_i;

                    // 计算期望地址和有效掩码
                    expected_lane_addr = {ADDR_WIDTH{1'b0}};
                    if ((r_i < k_total_i) &&
                        (time_index_i >= 0) &&
                        (time_index_i < input_length_i)) begin
                        expected_mask[lane_i] = 1'b1;
                        expected_lane_addr = INPUT_BASE
                                           + time_index_i * cin_i
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
                end

                check_count = check_count + 5;

                // 当前向量只有cin_valid、mask和4路地址全部相等才算PASS。
                vector_pass = (cin_valid === 1'b1) &&
                              (valid_mask === expected_mask) &&
                              (addr0 === expected_addr0) &&
                              (addr1 === expected_addr1) &&
                              (addr2 === expected_addr2) &&
                              (addr3 === expected_addr3);

                if (cin_valid !== 1'b1) begin
                    $display(
                        "AGU ERROR layer=%0d m=%0d kg=%0d: cin_valid=0 Cin=%0d",
                        layer_id, m_i, group_i, cin_i
                    );
                    error_count = error_count + 1;
                end

                if ((valid_mask !== expected_mask) ||
                    (addr0 !== expected_addr0) ||
                    (addr1 !== expected_addr1) ||
                    (addr2 !== expected_addr2) ||
                    (addr3 !== expected_addr3)) begin
                    $display(
                        "AGU ERROR layer=%0d m=%0d kg=%0d Cin=%0d Cout=%0d K=%0d S=%0d D=%0d",
                        layer_id, m_i, group_i, cin_i, cout_i,
                        kernel_i, stride_i, dilation_i
                    );
                    $display(
                        "  mask expected=%b actual=%b",
                        expected_mask, valid_mask
                    );
                    $display(
                        "  addr expected=%h %h %h %h",
                        expected_addr3, expected_addr2,
                        expected_addr1, expected_addr0
                    );
                    $display(
                        "  addr actual  =%h %h %h %h",
                        addr3, addr2, addr1, addr0
                    );
                    error_count = error_count + 1;
                end

                // 默认只打印第1层的左Padding边界、完整窗口起点和最后位置。
                // 设置PRINT_ALL_VECTORS=1可以打印目标层的全部(m,k_group)。
                if (((TRACE_LAYER_ID == 0) ||
                     (layer_id == TRACE_LAYER_ID)) &&
                    ((PRINT_ALL_VECTORS != 0) ||
                     (m_i <= 6) ||
                     (m_i == output_length_i - 1))) begin
                    $display("------------------------------------------------------------");
                    $display(
                        "TRACE layer=%0d m=%0d k_group=%0d result=%s",
                        layer_id, m_i, group_i,
                        vector_pass ? "PASS" : "FAIL"
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
                        "  mask compare : expected=%b  dut=%b",
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

        if (error_count == layer_error_start) begin
            $display(
                "LAYER PASS %0d: Cin=%0d Cout=%0d K=%0d S=%0d D=%0d P=%0d Lin=%0d M=%0d Kg=%0d",
                layer_id, cin_i, cout_i, kernel_i, stride_i,
                dilation_i, left_pad_i, input_length_i,
                output_length_i, k_groups_i
            );
        end
    end
endtask

// 非法 Cin 应拉低 cin_valid，并禁止全部 lane。
task check_illegal_cin;
    begin
        input_base  = INPUT_BASE;
        cin         = 9'd8;
        stride      = 4'd1;
        dilation    = 4'd1;
        left_pad    = 8'd0;
        input_length = 9'd16;
        k_total     = 12'd8;
        k_group     = 10'd0;
        m           = {M_TAG_WIDTH{1'b0}};
        #1;

        check_count = check_count + 2;
        if (cin_valid !== 1'b0) begin
            $display("AGU ERROR illegal Cin: cin_valid should be 0");
            error_count = error_count + 1;
        end
        if (valid_mask !== 4'b0000) begin
            $display(
                "AGU ERROR illegal Cin: valid_mask expected=0000 actual=%b",
                valid_mask
            );
            error_count = error_count + 1;
        end
    end
endtask

initial begin
    input_base   = {ADDR_WIDTH{1'b0}};
    cin          = 9'd0;
    stride       = 4'd0;
    dilation     = 4'd0;
    left_pad     = 8'd0;
    input_length = 9'd0;
    k_total      = 12'd0;
    k_group      = 10'd0;
    m            = {M_TAG_WIDTH{1'b0}};
    error_count  = 0;
    check_count  = 0;
    layer_count  = 0;

    // Initial Conv：1 -> 16，kernel=7。
    check_layer( 1,   1,  16,  7, 1, 1,  6, 320, 320);

    // Encoder Block 1：16 -> 32，stride=2。
    check_layer( 2,  16,  16,  7, 1, 1,  6, 320, 320);
    check_layer( 3,  16,  16,  1, 1, 1,  0, 320, 320);
    check_layer( 4,  16,  16,  7, 1, 3, 18, 320, 320);
    check_layer( 5,  16,  16,  1, 1, 1,  0, 320, 320);
    check_layer( 6,  16,  16,  7, 1, 9, 54, 320, 320);
    check_layer( 7,  16,  16,  1, 1, 1,  0, 320, 320);
    check_layer( 8,  16,  32,  4, 2, 1,  2, 320, 160);

    // Encoder Block 2：32 -> 64，stride=4。
    check_layer( 9,  32,  32,  7, 1, 1,  6, 160, 160);
    check_layer(10,  32,  32,  1, 1, 1,  0, 160, 160);
    check_layer(11,  32,  32,  7, 1, 3, 18, 160, 160);
    check_layer(12,  32,  32,  1, 1, 1,  0, 160, 160);
    check_layer(13,  32,  32,  7, 1, 9, 54, 160, 160);
    check_layer(14,  32,  32,  1, 1, 1,  0, 160, 160);
    check_layer(15,  32,  64,  8, 4, 1,  4, 160,  40);

    // Encoder Block 3：64 -> 128，stride=5。
    check_layer(16,  64,  64,  7, 1, 1,  6,  40,  40);
    check_layer(17,  64,  64,  1, 1, 1,  0,  40,  40);
    check_layer(18,  64,  64,  7, 1, 3, 18,  40,  40);
    check_layer(19,  64,  64,  1, 1, 1,  0,  40,  40);
    check_layer(20,  64,  64,  7, 1, 9, 54,  40,  40);
    check_layer(21,  64,  64,  1, 1, 1,  0,  40,  40);
    check_layer(22,  64, 128, 10, 5, 1,  5,  40,   8);

    // Encoder Block 4：128 -> 256，stride=8。
    check_layer(23, 128, 128,  7, 1, 1,  6,   8,   8);
    check_layer(24, 128, 128,  1, 1, 1,  0,   8,   8);
    check_layer(25, 128, 128,  7, 1, 3, 18,   8,   8);
    check_layer(26, 128, 128,  1, 1, 1,  0,   8,   8);
    check_layer(27, 128, 128,  7, 1, 9, 54,   8,   8);
    check_layer(28, 128, 128,  1, 1, 1,  0,   8,   8);
    check_layer(29, 128, 256, 16, 8, 1,  8,   8,   1);

    // Final Conv：256 -> codebook_dim=64，kernel=3。
    check_layer(30, 256,  64,  3, 1, 1,  2,   1,   1);

    check_illegal_cin;

    if (error_count == 0) begin
        $display(
            "AGU TEST PASS: layers=%0d checks=%0d",
            layer_count, check_count
        );
    end else begin
        $display(
            "AGU TEST FAIL: layers=%0d checks=%0d errors=%0d",
            layer_count, check_count, error_count
        );
    end

    $finish;
end

endmodule
