// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for this project: removed OpenTitan-wide assertion and DPI include dependencies.
// The upstream synchronous 1-read/1-write SRAM behavior and masked write merge are retained.

module prim_ram_1r1w import prim_ram_1r1w_pkg::*; #(
  parameter  int Width           = 32,
  parameter  int Depth           = 128,
  parameter  int DataBitsPerMask = 1,
  parameter      MemInitFile     = "",
  localparam int Aw              = $clog2(Depth)
) (
  input  logic              clk_a_i,
  input  logic              clk_b_i,
  input  logic              rst_a_ni,
  input  logic              rst_b_ni,
  input                     a_req_i,
  input        [Aw-1:0]     a_addr_i,
  input        [Width-1:0]  a_wdata_i,
  input  logic [Width-1:0]  a_wmask_i,
  input                     b_req_i,
  input        [Aw-1:0]     b_addr_i,
  output logic [Width-1:0]  b_rdata_o,
  input  ram_1r1w_cfg_req_t cfg_i,
  output ram_1r1w_cfg_rsp_t cfg_o
);

  logic unused_signals;
  assign unused_signals = ^{cfg_i, rst_a_ni, rst_b_ni};
  assign cfg_o = RAM_1R1W_CFG_RSP_DEFAULT;

  logic [Width-1:0] mem [Depth];
  logic [Width-1:0] wdata;
  assign wdata = (a_wdata_i & a_wmask_i) | (mem[a_addr_i] & ~a_wmask_i);

  always @(posedge clk_a_i) begin
    if (a_req_i) begin
      mem[a_addr_i] <= wdata;
    end
  end

  always @(posedge clk_b_i) begin
    if (b_req_i) begin
      b_rdata_o <= mem[b_addr_i];
    end
  end

  initial begin
    if (MemInitFile != "") begin
      $display("Initializing memory %m from file '%s'.", MemInitFile);
      $readmemh(MemInitFile, mem);
    end
  end

endmodule
