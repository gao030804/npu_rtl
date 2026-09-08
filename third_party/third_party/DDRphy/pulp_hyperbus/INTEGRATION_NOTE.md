# PULP HyperBus integration note

- Source: https://github.com/pulp-platform/hyperbus
- Retrieved: 2026-08-27
- License: Solderpad Hardware License 0.51 / Apache-2.0 option; see `LICENSE`

The upstream `src/` files are preserved for PHY and DDR-I/O reference. Upstream
depends on `common_cells`, `axi`, `tech_cells_generic`, and `register_interface`.

Important compatibility boundary: S28HS512T uses Octal SPI (OPI), whereas this
repository generates HyperBus command/address transactions. The upstream README
states that only HyperRAM was tested and flash support is work in progress.
Therefore these files are not placed in the active synthesis list for the S28 path.
The active NPU boundary is the post-PHY 16-bit stream defined by
`rtl/DDRphy/octal_ddr_16to256_packer.v`.
