# OpenTitan SRAM standalone subset

Upstream: https://github.com/lowRISC/opentitan

Pinned upstream commit: `e688e72bc0d61ccc70b04bf22f64e91194b1fe4f`

Imported source paths:

- `hw/ip/prim_generic/rtl/prim_ram_1p.sv`
- `hw/ip/prim_generic/rtl/prim_ram_1p_pkg.sv`
- `hw/ip/prim_generic/rtl/prim_ram_1r1w.sv`
- `hw/ip/prim_generic/rtl/prim_ram_1r1w_pkg.sv`
- `hw/ip/prim_generic/rtl/prim_ram_2p_pkg.sv`

The two RAM modules are modified standalone ports of the upstream generic models:

- OpenTitan assertion macros are removed to avoid importing the complete primitive assertion tree.
- OpenTitan DPI backdoor helpers are removed; `MemInitFile` with `$readmemh` is retained.
- The synchronous read, write-mask merge, and one-read/one-write behavior are retained.

These are SystemVerilog files. Compile package files before module files. This directory is licensed
under Apache-2.0; see `LICENSE`.

## Integration in this Conv1d project

- `rtl/activation_buffer_pingpong.v` remains the activation-storage controller.
  Buffer A and Buffer B each contain four 16-bit single-port SRAM banks. The wrapper still
  performs byte-address decoding, ping-pong selection, valid/ready backpressure, byte strobes,
  conflict checking, and synchronous-read response assembly.
- `rtl/activation_reader_4lane.v` is still a small response/skid register between activation
  storage and the systolic-array input. It is not replaced by the SRAM model.
- `rtl/accumulator_8lane.v` remains the partial-sum controller. Its eight former register arrays
  are now eight 32-bit 1R1W SRAM banks; first K-group writes overwrite old contents and later
  K-groups use a pipelined read-modify-write operation.
- These generic models are useful for RTL simulation and SRAM-interface verification. During ASIC
  implementation they should be mapped or replaced by the target technology's SRAM macros.
