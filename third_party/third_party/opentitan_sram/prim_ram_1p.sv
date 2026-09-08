// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for this project: removed OpenTitan-wide assertion and DPI include dependencies.
// The upstream synchronous single-port SRAM behavior and masked write merge are retained.

module prim_ram_1p import prim_ram_1p_pkg::*; #(
  parameter  int Width           = 32,
  parameter  int Depth           = 128,
  parameter  int DataBitsPerMask = 1,
  parameter      MemInitFile     = "",
  localparam int Aw              = $clog2(Depth)
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             req_i,
  input  logic             write_i,
  input  logic [Aw-1:0]    addr_i,
  input  logic [Width-1:0] wdata_i,
  input  logic [Width-1:0] wmask_i,
  output logic [Width-1:0] rdata_o,
  input  ram_1p_cfg_req_t  cfg_i,
  output ram_1p_cfg_rsp_t  cfg_o
);

  logic unused_signals;
  assign unused_signals = ^{cfg_i, rst_ni};
  assign cfg_o = RAM_1P_CFG_RSP_DEFAULT;

  logic [Width-1:0] mem [Depth];
  logic [Width-1:0] wdata;
  assign wdata = (wdata_i & wmask_i) | (mem[addr_i] & ~wmask_i);

  always @(posedge clk_i) begin
    if (req_i) begin
      if (write_i) begin
        mem[addr_i] <= wdata;
      end else begin
        rdata_o <= mem[addr_i];
      end
    end
  end

  initial begin
    if (MemInitFile != "") begin
      $display("Initializing memory %m from file '%s'.", MemInitFile);
      $readmemh(MemInitFile, mem);
    end
  end

endmodule
