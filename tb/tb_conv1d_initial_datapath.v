`timescale 1ns/1ps

//=============================================================================
// 模块名称：tb_conv1d_initial_datapath
//
// 验证范围：SoundStream编码器初始卷积层
//   Cin=1, Cout=16, Kernel=7, Stride=1, Dilation=1
//   Left_pad=6, Input_length=320, Output_length=320
//
// 使用的RTL/模型：
//   conv1d_agu、Activation SRAM模型、conv1d_weight_agu、Weight SRAM模型、
//   mesh_adapter + Systolic_Array、postprocess_8lane、output_writer_8lane、
//   Output SRAM模型。
//
// 本testbench不使用完整controller。跨两个k_group的累加由testbench数组完成，
// 目的是隔离验证用户指定的数据通路模块，而不是替代最终硬件Accumulator。
//=============================================================================
module tb_conv1d_initial_datapath;

localparam ADDR_WIDTH  = 32;
localparam M_TAG_WIDTH = 9;
localparam CIN         = 1;
localparam COUT        = 16;
localparam KERNEL      = 7;
localparam STRIDE      = 1;
localparam DILATION    = 1;
localparam LEFT_PAD    = 6;
localparam INPUT_LEN   = 320;
localparam OUTPUT_LEN  = 320;
localparam K_TOTAL     = 7;
localparam K_GROUPS    = 2;
localparam N_GROUPS    = 2;

// 是否打印全部最终输出：
//   1：打印 320 x 16 = 5120 条结果；
//   0：只打印错误信息和最终 PASS/FAIL 汇总。
localparam PRINT_ALL_FINAL_RESULTS = 1;

localparam [31:0] INPUT_BASE  = 32'h0000_1000;
localparam [31:0] WEIGHT_BASE = 32'h0000_2000;
localparam [31:0] OUTPUT_BASE = 32'h0000_4000;

reg clk;
reg rst_n;
integer error_count;
integer i;
integer m_i;
integer kg_i;
integer og_i;
integer oc_i;
integer lane_i;
integer ki_i;
integer time_i;
integer block_i;
integer base_weight_block;
integer expected_i;
integer actual_i;
integer golden_i;
integer scaled_i;
integer pre_elu_i;
integer saturation_count;
integer timeout_i;
integer hw_acc [0:OUTPUT_LEN*COUT-1];
integer expected_output [0:OUTPUT_LEN*COUT-1];
reg [7:0] expected_elu_lut [0:127];

//-------------------------------------------------------------------------
// 激活AGU
//-------------------------------------------------------------------------
reg  [9:0] agu_k_group;
reg  [M_TAG_WIDTH-1:0] agu_m;
wire [31:0] agu_addr0;
wire [31:0] agu_addr1;
wire [31:0] agu_addr2;
wire [31:0] agu_addr3;
wire [3:0]  agu_mask;
wire        agu_cin_valid;

conv1d_agu u_agu (
    .input_base   (INPUT_BASE),
    .cin          (9'd1),
    .stride       (4'd1),
    .dilation     (4'd1),
    .left_pad     (8'd6),
    .input_length (9'd320),
    .k_total      (12'd7),
    .k_group      (agu_k_group),
    .m            (agu_m),
    .addr0        (agu_addr0),
    .addr1        (agu_addr1),
    .addr2        (agu_addr2),
    .addr3        (agu_addr3),
    .valid_mask   (agu_mask),
    .cin_valid    (agu_cin_valid)
);

//-------------------------------------------------------------------------
// Activation SRAM模型接口
//-------------------------------------------------------------------------
reg         act_req_valid;
wire        act_req_ready;
reg  [31:0] act_req_addr0;
reg  [31:0] act_req_addr1;
reg  [31:0] act_req_addr2;
reg  [31:0] act_req_addr3;
reg  [3:0]  act_req_mask;
wire        act_rsp_valid;
wire [31:0] act_rsp_data;
reg         act_read_buffer_select;
reg         act_write_buffer_select;
reg  [31:0] act_read_buffer_base;
reg  [31:0] act_write_buffer_base;
wire        activation_buffer_error;

// PCM16 输入前端：量化为 INT8 后，每 8 个样本打包写入 Buffer A。
reg                 pcm_start;
reg                 pcm_valid;
wire                pcm_ready;
reg signed [15:0]   pcm_data;
wire                pcm_frontend_busy;
wire                pcm_frontend_done;
wire                pcm_wr_valid;
wire                pcm_wr_ready;
wire [31:0]         pcm_wr_addr;
wire [63:0]         pcm_wr_data;
wire [7:0]          pcm_wr_strb;
reg                 pcm_load_mode;
wire                buffer_wr_valid;
wire                buffer_wr_ready;
wire [31:0]         buffer_wr_addr;
wire [63:0]         buffer_wr_data;
wire [7:0]          buffer_wr_strb;

pcm16_input_frontend u_pcm_frontend (
    .clk                (clk),
    .rst_n              (rst_n),
    .start              (pcm_start),
    .cfg_output_base    (INPUT_BASE),
    .cfg_sample_count   (16'd320),
    .cfg_multiplier     (32'sd1),
    .cfg_shift          (6'd8),
    .cfg_zero_point     (8'sd0),
    .busy               (pcm_frontend_busy),
    .done               (pcm_frontend_done),
    .pcm_valid          (pcm_valid),
    .pcm_ready          (pcm_ready),
    .pcm_data           (pcm_data),
    .wr_valid           (pcm_wr_valid),
    .wr_ready           (pcm_wr_ready),
    .wr_addr            (pcm_wr_addr),
    .wr_data            (pcm_wr_data),
    .wr_strb            (pcm_wr_strb)
);

//-------------------------------------------------------------------------
// 权重地址生成和Weight SRAM模型
//-------------------------------------------------------------------------
reg  [5:0]  weight_output_group;
reg  [9:0]  weight_k_group;
wire [31:0] weight_addr;
reg         weight_req_valid;
wire        weight_req_ready;
reg  [31:0] weight_req_addr;
wire        weight_rsp_valid;
wire [255:0] weight_rsp_data;

conv1d_weight_agu u_weight_agu (
    .weight_base  (WEIGHT_BASE),
    .output_group (weight_output_group),
    .k_group      (weight_k_group),
    .k_groups     (10'd2),
    .weight_addr  (weight_addr)
);

weight_sram_model u_weight_sram (
    .clk           (clk),
    .rst_n         (rst_n),
    .random_enable (1'b0),
    .req_valid     (weight_req_valid),
    .req_ready     (weight_req_ready),
    .req_addr      (weight_req_addr),
    .rsp_valid     (weight_rsp_valid),
    .rsp_ready     (1'b1),
    .rsp_data      (weight_rsp_data)
);

//-------------------------------------------------------------------------
// 真实Systolic_Array数据通路
//-------------------------------------------------------------------------
reg          mesh_weight_load;
reg  [255:0] mesh_weight_data;
reg          mesh_act_valid;
reg  [31:0]  mesh_act_data;
reg  [M_TAG_WIDTH-1:0] mesh_act_tag;
wire         mesh_psum_valid;
wire [159:0] mesh_psum_data;
wire [M_TAG_WIDTH-1:0] mesh_psum_tag;

mesh_adapter u_mesh_adapter (
    .clk         (clk),
    .rst_n       (rst_n),
    .ce          (1'b1),
    .weight_load (mesh_weight_load),
    .weight_data (mesh_weight_data),
    .act_valid   (mesh_act_valid),
    .act_data    (mesh_act_data),
    .act_m_tag   (mesh_act_tag),
    .psum_valid  (mesh_psum_valid),
    .psum_data   (mesh_psum_data),
    .psum_m_tag  (mesh_psum_tag)
);

//-------------------------------------------------------------------------
// 后处理、写缓冲和Output SRAM
//-------------------------------------------------------------------------
reg          post_in_valid;
wire         post_in_ready;
reg  [255:0] post_acc_data;
reg  [255:0] post_bias_data;
reg  [255:0] post_mult_data;
reg  [47:0]  post_shift_data;
reg  [63:0]  post_zero_point_data;
wire         post_valid;
wire         post_ready;
wire [63:0]  post_data;
reg  [31:0]  post_addr;
wire         writer_in_ready;
wire         out_wr_valid;
wire         out_wr_ready;
wire [31:0]  out_wr_addr;
wire [63:0]  out_wr_data;
wire [7:0]   out_wr_strb;
reg          elu_cfg_valid;
wire         elu_cfg_ready;
reg  [6:0]   elu_cfg_addr;
reg  [7:0]   elu_cfg_wdata;
wire         elu_in_ready;
wire         elu_out_valid;
wire [63:0]  elu_out_data;

assign buffer_wr_valid = pcm_load_mode ? pcm_wr_valid : out_wr_valid;
assign buffer_wr_addr  = pcm_load_mode ? pcm_wr_addr  : out_wr_addr;
assign buffer_wr_data  = pcm_load_mode ? pcm_wr_data  : out_wr_data;
assign buffer_wr_strb  = pcm_load_mode ? pcm_wr_strb  : out_wr_strb;
assign pcm_wr_ready    = pcm_load_mode  ? buffer_wr_ready : 1'b0;
assign out_wr_ready    = pcm_load_mode  ? 1'b0 : buffer_wr_ready;

// ELU 位于量化后处理和写回之间。写回端暂停时，ready 会穿过 ELU
// 返回给 postprocess，从而保持整条通路的数据和地址稳定。
assign post_ready = elu_in_ready;

postprocess_8lane u_postprocess (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_valid   (post_in_valid),
    .in_ready   (post_in_ready),
    .acc_data   (post_acc_data),
    .bias_data  (post_bias_data),
    .mult_data  (post_mult_data),
    .shift_data (post_shift_data),
    .zero_point_data (post_zero_point_data),
    .post_valid (post_valid),
    .post_ready (post_ready),
    .post_data  (post_data)
);

elu_8lane u_elu (
    .clk        (clk),
    .rst_n      (rst_n),
    .cfg_valid  (elu_cfg_valid),
    .cfg_ready  (elu_cfg_ready),
    .cfg_addr   (elu_cfg_addr),
    .cfg_wdata  (elu_cfg_wdata),
    .elu_enable (1'b1),
    .relu_enable(1'b0),
    .in_valid   (post_valid),
    .in_ready   (elu_in_ready),
    .in_data    (post_data),
    .out_valid  (elu_out_valid),
    .out_ready  (writer_in_ready),
    .out_data   (elu_out_data)
);

output_writer_8lane u_output_writer (
    .clk          (clk),
    .rst_n        (rst_n),
    .in_valid     (elu_out_valid),
    .in_ready     (writer_in_ready),
    .in_addr      (post_addr),
    .in_data      (elu_out_data),
    .in_strb      (8'hff),
    .out_wr_valid (out_wr_valid),
    .out_wr_ready (out_wr_ready),
    .out_wr_addr  (out_wr_addr),
    .out_wr_data  (out_wr_data),
    .out_wr_strb  (out_wr_strb)
);

activation_buffer_pingpong #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .ROW_WIDTH  (10),
    .ROWS       (1024)
) u_activation_buffers (
    .clk              (clk),
    .rst_n            (rst_n),
    .rd_buffer_select (act_read_buffer_select),
    .rd_buffer_base   (act_read_buffer_base),
    .rd_req_valid     (act_req_valid),
    .rd_req_ready     (act_req_ready),
    .rd_addr0         (act_req_addr0),
    .rd_addr1         (act_req_addr1),
    .rd_addr2         (act_req_addr2),
    .rd_addr3         (act_req_addr3),
    .rd_mask          (act_req_mask),
    .rd_rsp_valid     (act_rsp_valid),
    .rd_rsp_ready     (1'b1),
    .rd_rsp_data      (act_rsp_data),
    .wr_buffer_select (act_write_buffer_select),
    .wr_buffer_base   (act_write_buffer_base),
    .wr_valid         (buffer_wr_valid),
    .wr_ready         (buffer_wr_ready),
    .wr_addr          (buffer_wr_addr),
    .wr_data          (buffer_wr_data),
    .wr_strb          (buffer_wr_strb),
    .access_error     (activation_buffer_error)
);

//-------------------------------------------------------------------------
// 确定性测试数据和黄金函数
//-------------------------------------------------------------------------
function integer input_value;
    input integer t;
    begin
        input_value = ((t * 3) % 17) - 8;
    end
endfunction

// 原始 PCM16 测试数据。主值为目标 INT8 的 256 倍，并叠加小于半个
// 量化步长的残差，用来确认量化器执行舍入，而不是简单截取字节。
function integer pcm16_value;
    input integer t;
    begin
        pcm16_value = input_value(t) * 256 + ((t % 5) - 2) * 32;
    end
endfunction

function integer weight_value;
    input integer oc;
    input integer ki;
    begin
        weight_value = ((oc * 5 + ki * 2) % 11) - 5;
    end
endfunction

function integer bias_value;
    input integer oc;
    begin
        bias_value = oc - 4;
    end
endfunction

// 为了覆盖真正的重新量化路径，测试中给不同输出通道不同的参数。
function integer mult_value;
    input integer oc;
    begin
        mult_value = (oc % 3) + 1;
    end
endfunction

function integer shift_value;
    input integer oc;
    begin
        shift_value = (oc % 3) + 2;
    end
endfunction

function integer zero_point_value;
    input integer oc;
    begin
        zero_point_value = (oc % 5) - 2;
    end
endfunction

// 软件参考模型与 RTL 一致：按绝对值对称舍入，再加 zero point。
function integer requant_pre_sat;
    input integer acc_value;
    input integer oc;
    integer value;
    integer magnitude_value;
    begin
        value = (acc_value + bias_value(oc)) * mult_value(oc);
        if (shift_value(oc) != 0) begin
            if (value >= 0) begin
                value = (value + (1 << (shift_value(oc)-1)))
                      >>> shift_value(oc);
            end else begin
                magnitude_value = -value;
                value = -((magnitude_value + (1 << (shift_value(oc)-1)))
                        >>> shift_value(oc));
            end
        end
        requant_pre_sat = value + zero_point_value(oc);
    end
endfunction

function integer sat8;
    input integer value;
    begin
        if (value > 127)
            sat8 = 127;
        else if (value < -128)
            sat8 = -128;
        else
            sat8 = value;
    end
endfunction

// ELU 软件参考模型：输入已经是 postprocess 输出的 signed INT8 编码。
// 正数原样通过；负数使用与 DUT 完全相同的 -1...-128 地址映射。
function integer elu_expected_value;
    input integer quantized_value;
    reg [7:0] quantized_byte;
    reg [6:0] lut_index;
    begin
        quantized_byte = quantized_value[7:0];
        if (quantized_byte[7]) begin
            lut_index = ~quantized_byte[6:0];
            elu_expected_value = $signed(expected_elu_lut[lut_index]);
        end else begin
            elu_expected_value = $signed(quantized_byte);
        end
    end
endfunction

// 在数据通路启动前，通过配置握手逐项装载 128 项 ELU LUT。
task load_elu_lut;
    integer lut_i;
    begin
        for (lut_i = 0; lut_i < 128; lut_i = lut_i + 1) begin
            @(negedge clk);
            elu_cfg_addr  = lut_i[6:0];
            elu_cfg_wdata = expected_elu_lut[lut_i];
            elu_cfg_valid = 1'b1;
            while (!elu_cfg_ready)
                @(negedge clk);
            @(posedge clk);
        end
        @(negedge clk);
        elu_cfg_valid = 1'b0;
        $display("[ELU_CFG] loaded 128 LUT entries, input/output scale=1/32");
    end
endtask

//-------------------------------------------------------------------------
// Testbench专用的物理Bank初始化/观察函数。
// 激活缓冲RTL本身不复位存储阵列，以便综合为真实SRAM/BRAM。
//-------------------------------------------------------------------------
task initialize_activation_byte;
    input integer buffer_id;
    input integer byte_offset;
    input integer byte_value;
    integer local_row;
    integer local_bank;
    begin
        local_row  = byte_offset >> 3;
        local_bank = (byte_offset >> 1) & 3;

        if (buffer_id == 0) begin
            case (local_bank)
                0: if (byte_offset & 1)
                       u_activation_buffers.u_a_bank0.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_a_bank0.u_ram.mem[local_row][7:0] = byte_value;
                1: if (byte_offset & 1)
                       u_activation_buffers.u_a_bank1.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_a_bank1.u_ram.mem[local_row][7:0] = byte_value;
                2: if (byte_offset & 1)
                       u_activation_buffers.u_a_bank2.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_a_bank2.u_ram.mem[local_row][7:0] = byte_value;
                default: if (byte_offset & 1)
                       u_activation_buffers.u_a_bank3.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_a_bank3.u_ram.mem[local_row][7:0] = byte_value;
            endcase
        end else begin
            case (local_bank)
                0: if (byte_offset & 1)
                       u_activation_buffers.u_b_bank0.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_b_bank0.u_ram.mem[local_row][7:0] = byte_value;
                1: if (byte_offset & 1)
                       u_activation_buffers.u_b_bank1.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_b_bank1.u_ram.mem[local_row][7:0] = byte_value;
                2: if (byte_offset & 1)
                       u_activation_buffers.u_b_bank2.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_b_bank2.u_ram.mem[local_row][7:0] = byte_value;
                default: if (byte_offset & 1)
                       u_activation_buffers.u_b_bank3.u_ram.mem[local_row][15:8] = byte_value;
                   else
                       u_activation_buffers.u_b_bank3.u_ram.mem[local_row][7:0] = byte_value;
            endcase
        end
    end
endtask

function [7:0] observe_activation_byte;
    input integer buffer_id;
    input integer byte_offset;
    integer local_row;
    integer local_bank;
    begin
        local_row  = byte_offset >> 3;
        local_bank = (byte_offset >> 1) & 3;
        observe_activation_byte = 8'd0;

        if (buffer_id == 0) begin
            case (local_bank)
                0: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_a_bank0.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_a_bank0.u_ram.mem[local_row][7:0];
                1: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_a_bank1.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_a_bank1.u_ram.mem[local_row][7:0];
                2: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_a_bank2.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_a_bank2.u_ram.mem[local_row][7:0];
                default: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_a_bank3.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_a_bank3.u_ram.mem[local_row][7:0];
            endcase
        end else begin
            case (local_bank)
                0: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_b_bank0.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_b_bank0.u_ram.mem[local_row][7:0];
                1: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_b_bank1.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_b_bank1.u_ram.mem[local_row][7:0];
                2: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_b_bank2.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_b_bank2.u_ram.mem[local_row][7:0];
                default: observe_activation_byte = (byte_offset & 1) ?
                       u_activation_buffers.u_b_bank3.u_ram.mem[local_row][15:8] :
                       u_activation_buffers.u_b_bank3.u_ram.mem[local_row][7:0];
            endcase
        end
    end
endfunction

// 通过正式 valid/ready 和 64-bit SRAM 写口装入一帧 320-sample PCM。
task load_pcm16_frame;
    integer sample_index;
    integer load_timeout;
    integer loaded_value;
    begin
        pcm_load_mode          = 1'b1;
        act_write_buffer_select = 1'b0;
        act_write_buffer_base   = INPUT_BASE;

        @(negedge clk);
        pcm_start = 1'b1;
        @(negedge clk);
        pcm_start = 1'b0;

        for (sample_index = 0; sample_index < INPUT_LEN;
             sample_index = sample_index + 1) begin
            pcm_data  = pcm16_value(sample_index);
            pcm_valid = 1'b1;
            while (!pcm_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            pcm_valid = 1'b0;
        end

        load_timeout = 0;
        while (!pcm_frontend_done && load_timeout < 2000) begin
            @(negedge clk);
            load_timeout = load_timeout + 1;
        end
        if (!pcm_frontend_done) begin
            $display("[ERROR][PCM] PCM16 frontend load timeout");
            error_count = error_count + 1;
        end

        // 检查量化后的320字节确实进入 Buffer A。
        for (sample_index = 0; sample_index < INPUT_LEN;
             sample_index = sample_index + 1) begin
            loaded_value = $signed(observe_activation_byte(0,sample_index));
            if (loaded_value !== input_value(sample_index)) begin
                if (error_count < 40) begin
                    $display(
                        "[ERROR][PCM] sample=%0d pcm16=%0d expected_int8=%0d actual_int8=%0d",
                        sample_index,
                        pcm16_value(sample_index),
                        input_value(sample_index),
                        loaded_value
                    );
                end
                error_count = error_count + 1;
            end
        end

        $display(
            "[PCM_QUANT] samples=%0d multiplier=1 shift=8 zero_point=0 load_complete",
            INPUT_LEN
        );

        // 卷积阶段改为读 Buffer A、写 Buffer B。
        pcm_load_mode           = 1'b0;
        act_write_buffer_select = 1'b1;
        act_write_buffer_base   = OUTPUT_BASE;
    end
endtask

//-------------------------------------------------------------------------
// 从Weight SRAM读取并装载一个4×8权重块。
//-------------------------------------------------------------------------
task load_weight_block;
    input integer og;
    input integer kg;
    reg [255:0] returned_weight;
    reg [31:0] expected_weight_addr;
    begin
        weight_output_group = og;
        weight_k_group      = kg;
        #1;

        expected_weight_addr = WEIGHT_BASE + ((og*K_GROUPS+kg) << 5);
        if (weight_addr !== expected_weight_addr) begin
            $display(
                "[ERROR][WAGU] og=%0d kg=%0d expected=%08h actual=%08h",
                og, kg, expected_weight_addr, weight_addr
            );
            error_count = error_count + 1;
        end

        @(negedge clk);
        weight_req_addr  = weight_addr;
        weight_req_valid = 1'b1;
        while (!weight_req_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        weight_req_valid = 1'b0;

        timeout_i = 0;
        while (!weight_rsp_valid && timeout_i < 100) begin
            @(negedge clk);
            timeout_i = timeout_i + 1;
        end
        if (!weight_rsp_valid) begin
            $display("[ERROR][WEIGHT_SRAM] timeout og=%0d kg=%0d", og, kg);
            error_count = error_count + 1;
            returned_weight = 256'd0;
        end else begin
            returned_weight = weight_rsp_data;
            if (returned_weight !== u_weight_sram.mem[weight_addr >> 5]) begin
                $display("[ERROR][WEIGHT_SRAM] data mismatch og=%0d kg=%0d",og,kg);
                error_count = error_count + 1;
            end
        end

        @(negedge clk);
        mesh_weight_data = returned_weight;
        mesh_weight_load = 1'b1;
        @(posedge clk);
        @(negedge clk);
        mesh_weight_load = 1'b0;

        $display(
            "[INFO][WEIGHT] og=%0d kg=%0d addr=%08h loaded",
            og, kg, weight_addr
        );
    end
endtask

//-------------------------------------------------------------------------
// 使用AGU读取一个4-lane激活向量，并检查地址、mask和SRAM返回值。
//-------------------------------------------------------------------------
task read_activation_vector;
    input integer m_value;
    input integer kg_value;
    output [31:0] returned_activation;
    integer local_lane;
    integer local_r;
    integer local_time;
    reg [3:0] expected_mask;
    reg [31:0] expected_addr0;
    reg [31:0] expected_addr1;
    reg [31:0] expected_addr2;
    reg [31:0] expected_addr3;
    reg [31:0] expected_lane_addr;
    reg [31:0] expected_data;
    begin
        agu_m       = m_value;
        agu_k_group = kg_value;
        #1;

        expected_mask  = 4'b0000;
        expected_addr0 = 32'd0;
        expected_addr1 = 32'd0;
        expected_addr2 = 32'd0;
        expected_addr3 = 32'd0;
        expected_data  = 32'd0;

        for (local_lane = 0; local_lane < 4;
             local_lane = local_lane + 1) begin
            local_r    = 4*kg_value + local_lane;
            local_time = m_value - LEFT_PAD + local_r;
            expected_lane_addr = 32'd0;

            if ((local_r < K_TOTAL) &&
                (local_time >= 0) &&
                (local_time < INPUT_LEN)) begin
                expected_mask[local_lane] = 1'b1;
                expected_lane_addr = INPUT_BASE + local_time;
                expected_data[8*local_lane +: 8] = input_value(local_time);
            end

            case (local_lane)
                0: expected_addr0 = expected_lane_addr;
                1: expected_addr1 = expected_lane_addr;
                2: expected_addr2 = expected_lane_addr;
                3: expected_addr3 = expected_lane_addr;
            endcase
        end

        if (!agu_cin_valid ||
            (agu_mask !== expected_mask) ||
            (agu_addr0 !== expected_addr0) ||
            (agu_addr1 !== expected_addr1) ||
            (agu_addr2 !== expected_addr2) ||
            (agu_addr3 !== expected_addr3)) begin
            $display("[ERROR][AGU] m=%0d kg=%0d",m_value,kg_value);
            $display("  mask expected=%b actual=%b",expected_mask,agu_mask);
            $display("  addr expected=%08h %08h %08h %08h",
                     expected_addr0,expected_addr1,expected_addr2,expected_addr3);
            $display("  addr actual  =%08h %08h %08h %08h",
                     agu_addr0,agu_addr1,agu_addr2,agu_addr3);
            error_count = error_count + 1;
        end

        @(negedge clk);
        act_req_addr0 = agu_addr0;
        act_req_addr1 = agu_addr1;
        act_req_addr2 = agu_addr2;
        act_req_addr3 = agu_addr3;
        act_req_mask  = agu_mask;
        act_req_valid = 1'b1;
        while (!act_req_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        act_req_valid = 1'b0;

        timeout_i = 0;
        while (!act_rsp_valid && timeout_i < 100) begin
            @(negedge clk);
            timeout_i = timeout_i + 1;
        end
        if (!act_rsp_valid) begin
            $display("[ERROR][ACT_SRAM] timeout m=%0d kg=%0d",m_value,kg_value);
            error_count = error_count + 1;
            returned_activation = 32'd0;
        end else begin
            returned_activation = act_rsp_data;
            if (returned_activation !== expected_data) begin
                $display(
                    "[ERROR][ACT_SRAM] m=%0d kg=%0d expected=%08h actual=%08h",
                    m_value,kg_value,expected_data,returned_activation
                );
                error_count = error_count + 1;
            end
        end
    end
endtask

//-------------------------------------------------------------------------
// 向Systolic Array发送一个向量并等待8路部分和。
//-------------------------------------------------------------------------
//-------------------------------------------------------------------------
// 层结束后交换A/B角色，并通过正式4-lane读接口回读上一层结果。
// 每次检查4个连续Byte，证明Buffer B中的结果可直接作为下一层输入。
//-------------------------------------------------------------------------
task verify_next_layer_read;
    input integer linear_offset;
    reg [31:0] expected_vector;
    integer local_lane;
    begin
        expected_vector = 32'd0;
        for (local_lane = 0; local_lane < 4;
             local_lane = local_lane + 1) begin
            expected_vector[8*local_lane +: 8] =
                expected_output[linear_offset+local_lane];
        end

        @(negedge clk);
        act_req_addr0 = OUTPUT_BASE + linear_offset;
        act_req_addr1 = OUTPUT_BASE + linear_offset + 1;
        act_req_addr2 = OUTPUT_BASE + linear_offset + 2;
        act_req_addr3 = OUTPUT_BASE + linear_offset + 3;
        act_req_mask  = 4'b1111;
        act_req_valid = 1'b1;

        while (!act_req_ready)
            @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        act_req_valid = 1'b0;

        timeout_i = 0;
        while (!act_rsp_valid && timeout_i < 100) begin
            @(negedge clk);
            timeout_i = timeout_i + 1;
        end

        if (!act_rsp_valid) begin
            $display(
                "[ERROR][PINGPONG_READ] timeout offset=%0d",
                linear_offset
            );
            error_count = error_count + 1;
        end else if (act_rsp_data !== expected_vector) begin
            $display(
                "[ERROR][PINGPONG_READ] offset=%0d expected=%08h actual=%08h",
                linear_offset, expected_vector, act_rsp_data
            );
            error_count = error_count + 1;
        end
    end
endtask

task run_systolic_vector;
    input integer m_value;
    input [31:0] activation_vector;
    output [159:0] psum_vector;
    begin
        @(negedge clk);
        mesh_act_data  = activation_vector;
        mesh_act_tag   = m_value;
        mesh_act_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        mesh_act_valid = 1'b0;
        mesh_act_data  = 32'd0;

        timeout_i = 0;
        while (!mesh_psum_valid && timeout_i < 100) begin
            @(negedge clk);
            timeout_i = timeout_i + 1;
        end

        if (!mesh_psum_valid) begin
            $display("[ERROR][MESH] timeout m=%0d",m_value);
            error_count = error_count + 1;
            psum_vector = 160'd0;
        end else begin
            psum_vector = mesh_psum_data;
            if (mesh_psum_tag !== m_value[M_TAG_WIDTH-1:0]) begin
                $display(
                    "[ERROR][MESH] tag expected=%0d actual=%0d",
                    m_value,mesh_psum_tag
                );
                error_count = error_count + 1;
            end
        end
    end
endtask

//-------------------------------------------------------------------------
// 对一个output_group的8路INT32结果执行后处理并写入Output SRAM。
//-------------------------------------------------------------------------
task postprocess_and_write;
    input integer m_value;
    input integer og_value;
    integer local_n;
    begin
        post_acc_data   = 256'd0;
        post_bias_data  = 256'd0;
        post_mult_data  = 256'd0;
        post_shift_data = 48'd0;
        post_zero_point_data = 64'd0;

        for (local_n = 0; local_n < 8; local_n = local_n + 1) begin
            post_acc_data[32*local_n +: 32] =
                hw_acc[m_value*COUT + og_value*8 + local_n];
            post_bias_data[32*local_n +: 32] =
                bias_value(og_value*8 + local_n);
            post_mult_data[32*local_n +: 32] =
                mult_value(og_value*8 + local_n);
            post_shift_data[6*local_n +: 6] =
                shift_value(og_value*8 + local_n);
            post_zero_point_data[8*local_n +: 8] =
                zero_point_value(og_value*8 + local_n);
        end

        post_addr = OUTPUT_BASE + m_value*COUT + og_value*8;
        @(negedge clk);
        while (!post_in_ready)
            @(negedge clk);
        post_in_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        post_in_valid = 1'b0;

        timeout_i = 0;
        while (!out_wr_valid && timeout_i < 100) begin
            @(negedge clk);
            timeout_i = timeout_i + 1;
        end
        if (!out_wr_valid) begin
            $display("[ERROR][OUTPUT] timeout m=%0d og=%0d",m_value,og_value);
            error_count = error_count + 1;
        end else if (out_wr_addr !== post_addr) begin
            $display(
                "[ERROR][OUTPUT] addr expected=%08h actual=%08h",
                post_addr,out_wr_addr
            );
            error_count = error_count + 1;
        end

        // Output SRAM在下一个posedge完成写入。
        @(posedge clk);
        @(negedge clk);
    end
endtask

reg [31:0] activation_vector_q;
reg [159:0] psum_vector_q;

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    rst_n              = 1'b0;
    error_count        = 0;
    agu_k_group        = 10'd0;
    agu_m              = 9'd0;
    act_req_valid      = 1'b0;
    act_req_addr0      = 32'd0;
    act_req_addr1      = 32'd0;
    act_req_addr2      = 32'd0;
    act_req_addr3      = 32'd0;
    act_req_mask       = 4'd0;
    weight_output_group= 6'd0;
    weight_k_group     = 10'd0;
    weight_req_valid   = 1'b0;
    weight_req_addr    = 32'd0;
    mesh_weight_load   = 1'b0;
    mesh_weight_data   = 256'd0;
    mesh_act_valid     = 1'b0;
    mesh_act_data      = 32'd0;
    mesh_act_tag       = 9'd0;
    post_in_valid      = 1'b0;
    post_acc_data      = 256'd0;
    post_bias_data     = 256'd0;
    post_mult_data     = 256'd0;
    post_shift_data    = 48'd0;
    post_zero_point_data = 64'd0;
    post_addr          = 32'd0;
    elu_cfg_valid      = 1'b0;
    elu_cfg_addr       = 7'd0;
    elu_cfg_wdata      = 8'd0;
    pcm_start          = 1'b0;
    pcm_valid          = 1'b0;
    pcm_data           = 16'sd0;
    pcm_load_mode      = 1'b1;
    act_read_buffer_select  = 1'b0;       // 第一层从Buffer A读取。
    act_write_buffer_select = 1'b1;       // 第一层结果写入Buffer B。
    act_read_buffer_base    = INPUT_BASE;
    act_write_buffer_base   = OUTPUT_BASE;

    base_weight_block = WEIGHT_BASE >> 5;
    saturation_count = 0;

    // 当前文件对应演示 scale=1/32；正式部署时应由各层校准 scale 重新生成。
    $readmemh("tb/data/elu_lut_s1_32.hex",expected_elu_lut);

    // 初始化输入、权重、累加数组和输出哨兵值。
    for (i = 0; i < N_GROUPS*K_GROUPS; i = i + 1)
        u_weight_sram.mem[base_weight_block+i] = 256'd0;

    for (oc_i = 0; oc_i < COUT; oc_i = oc_i + 1) begin
        for (ki_i = 0; ki_i < KERNEL; ki_i = ki_i + 1) begin
            block_i = (oc_i/8)*K_GROUPS + ki_i/4;
            u_weight_sram.mem[base_weight_block+block_i]
                [8*((ki_i%4)*8+(oc_i%8)) +: 8] =
                weight_value(oc_i,ki_i);
        end
    end

    for (i = 0; i < OUTPUT_LEN*COUT; i = i + 1) begin
        hw_acc[i] = 0;
        expected_output[i] = 0;
        initialize_activation_byte(1,i,8'h5a);
    end

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    load_elu_lut;
    load_pcm16_frame;

    $display("============================================================");
    $display("Initial Conv lightweight datapath test starts");
    $display("  Activation: base=%08h bytes=%0d",INPUT_BASE,INPUT_LEN);
    $display("  Weight    : base=%08h blocks=%0d",WEIGHT_BASE,N_GROUPS*K_GROUPS);
    $display("  Output    : base=%08h bytes=%0d",OUTPUT_BASE,OUTPUT_LEN*COUT);
    $display("============================================================");

    // output_group -> k_group -> m；每个权重块在320个m上复用。
    for (og_i = 0; og_i < N_GROUPS; og_i = og_i + 1) begin
        for (kg_i = 0; kg_i < K_GROUPS; kg_i = kg_i + 1) begin
            load_weight_block(og_i,kg_i);

            for (m_i = 0; m_i < OUTPUT_LEN; m_i = m_i + 1) begin
                read_activation_vector(m_i,kg_i,activation_vector_q);
                run_systolic_vector(m_i,activation_vector_q,psum_vector_q);

                for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1) begin
                    actual_i = $signed(psum_vector_q[20*lane_i +: 20]);
                    if (kg_i == 0)
                        hw_acc[m_i*COUT+og_i*8+lane_i] = actual_i;
                    else
                        hw_acc[m_i*COUT+og_i*8+lane_i] =
                            hw_acc[m_i*COUT+og_i*8+lane_i] + actual_i;
                end
            end
        end

        for (m_i = 0; m_i < OUTPUT_LEN; m_i = m_i + 1)
            postprocess_and_write(m_i,og_i);
    end

    // 独立黄金模型逐点比较320×16个最终INT8输出。
    $display("============================================================");
    $display("Final output comparison starts: pos=(m, output_channel)");
    $display("Fields: pos, SRAM address, golden_acc, dut_acc, quantized, ELU expected, actual, status");
    $display("============================================================");
    for (m_i = 0; m_i < OUTPUT_LEN; m_i = m_i + 1) begin
        for (oc_i = 0; oc_i < COUT; oc_i = oc_i + 1) begin
            golden_i = 0;
            for (ki_i = 0; ki_i < KERNEL; ki_i = ki_i + 1) begin
                time_i = m_i - LEFT_PAD + ki_i;
                if ((time_i >= 0) && (time_i < INPUT_LEN)) begin
                    golden_i = golden_i
                             + input_value(time_i)
                             * weight_value(oc_i,ki_i);
                end
            end

            scaled_i = requant_pre_sat(golden_i,oc_i);
            pre_elu_i = sat8(scaled_i);
            expected_i = elu_expected_value(pre_elu_i);
            if ((scaled_i > 127) || (scaled_i < -128))
                saturation_count = saturation_count + 1;
            expected_output[m_i*COUT+oc_i] = expected_i;
            actual_i = $signed(observe_activation_byte(
                1,m_i*COUT+oc_i
            ));

            // pos=(m, oc)：输出矩阵的时间位置和输出通道。
            // golden_acc：软件公式计算的卷积累加值。
            // dut_acc   ：脉动阵列部分和在 Testbench 中合并后的累加值。
            // expected  ：golden_acc 加偏置并饱和到 INT8 后的期望值。
            // actual    ：后处理、写回后，从 Output SRAM 读出的实际值。
            if (PRINT_ALL_FINAL_RESULTS != 0) begin
                if (actual_i === expected_i) begin
                    $display(
                        "[RESULT] pos=(%0d,%0d) addr=%08h golden_acc=%0d dut_acc=%0d bias=%0d mult=%0d shift=%0d zp=%0d pre_sat=%0d quantized=%0d elu_expected=%0d actual=%0d status=PASS",
                        m_i,
                        oc_i,
                        OUTPUT_BASE+m_i*COUT+oc_i,
                        golden_i,
                        hw_acc[m_i*COUT+oc_i],
                        bias_value(oc_i),
                        mult_value(oc_i),
                        shift_value(oc_i),
                        zero_point_value(oc_i),
                        scaled_i,
                        pre_elu_i,
                        expected_i,
                        actual_i
                    );
                end else begin
                    $display(
                        "[RESULT] pos=(%0d,%0d) addr=%08h golden_acc=%0d dut_acc=%0d bias=%0d mult=%0d shift=%0d zp=%0d pre_sat=%0d quantized=%0d elu_expected=%0d actual=%0d status=FAIL",
                        m_i,
                        oc_i,
                        OUTPUT_BASE+m_i*COUT+oc_i,
                        golden_i,
                        hw_acc[m_i*COUT+oc_i],
                        bias_value(oc_i),
                        mult_value(oc_i),
                        shift_value(oc_i),
                        zero_point_value(oc_i),
                        scaled_i,
                        pre_elu_i,
                        expected_i,
                        actual_i
                    );
                end
            end
            if (actual_i !== expected_i) begin
                if (error_count < 40) begin
                    $display(
                        "[ERROR][GOLDEN] m=%0d oc=%0d expected=%0d actual=%0d acc=%0d",
                        m_i,oc_i,expected_i,actual_i,
                        hw_acc[m_i*COUT+oc_i]
                    );
                end
                error_count = error_count + 1;
            end
        end
    end

    $display(
        "[QUANT_STATS] outputs=%0d saturated=%0d saturation_rate=%0d/10000",
        OUTPUT_LEN*COUT,
        saturation_count,
        (saturation_count*10000)/(OUTPUT_LEN*COUT)
    );

    // 层间角色交换：上一层输出Buffer B成为下一层输入，Buffer A成为写Buffer。
    act_read_buffer_select  = 1'b1;
    act_write_buffer_select = 1'b0;
    act_read_buffer_base    = OUTPUT_BASE;
    act_write_buffer_base   = INPUT_BASE;
    $display("============================================================");
    $display("Ping-Pong swap: read=Buffer B, write=Buffer A");
    $display("Next-layer input readback starts: 1280 vectors x 4 bytes");

    for (i = 0; i < OUTPUT_LEN*COUT; i = i + 4)
        verify_next_layer_read(i);

    if (activation_buffer_error) begin
        $display("[ERROR][PINGPONG] activation buffer access_error=1");
        error_count = error_count + 1;
    end

    if (error_count == 0)
        $display("[TB_PASS] Initial Conv + Ping-Pong handoff: 5120 outputs correct");
    else
        $display("[TB_FAIL] Initial Conv + Ping-Pong handoff errors=%0d",error_count);

    $finish;
end

endmodule
