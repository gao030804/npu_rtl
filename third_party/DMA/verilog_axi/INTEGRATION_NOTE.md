# verilog-axi DMA integration note

- Source: https://github.com/alexforencich/verilog-axi
- Retrieved: 2026-08-27
- License: MIT; see `COPYING`
- Selected source: `rtl/axi_dma_rd.v`

`axi_dma_rd` is retained for a future memory-mapped AXI Octal controller. It is not
instantiated in the current S28 stream path because it is an AXI4 master, while the
current Weight SRAM and post-PHY interfaces are valid/ready streams. The active,
small descriptor DMA is `rtl/DMA/weight_stream_dma.v`.
