//=============================================================================
// OpenTitan prim_ram_1p adapter
// - 将按组写掩码扩展为OpenTitan要求的逐bit写掩码
// - 补充同步读响应rvalid_o
//=============================================================================
module opentitan_sram_1p_adapter #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 128,
    parameter int DATA_BITS_PER_MASK = 8,
    parameter MEM_INIT_FILE = "",
    localparam int ADDR_WIDTH = $clog2(DEPTH),
    localparam int MASK_WIDTH = WIDTH / DATA_BITS_PER_MASK
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  req_i,
    input  logic                  write_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,
    input  logic [WIDTH-1:0]      wdata_i,
    input  logic [MASK_WIDTH-1:0] wmask_i,
    output logic [WIDTH-1:0]      rdata_o,
    output logic                  rvalid_o
);

logic [WIDTH-1:0] bit_wmask;
prim_ram_1p_pkg::ram_1p_cfg_rsp_t unused_cfg_rsp;

for (genvar lane = 0; lane < MASK_WIDTH; lane++) begin : gen_mask_expand
    assign bit_wmask[lane*DATA_BITS_PER_MASK +: DATA_BITS_PER_MASK] =
        {DATA_BITS_PER_MASK{wmask_i[lane]}};
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        rvalid_o <= 1'b0;
    else
        rvalid_o <= req_i && !write_i;
end

prim_ram_1p #(
    .Width           (WIDTH),
    .Depth           (DEPTH),
    .DataBitsPerMask (DATA_BITS_PER_MASK),
    .MemInitFile     (MEM_INIT_FILE)
) u_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .req_i   (req_i),
    .write_i (write_i),
    .addr_i  (addr_i),
    .wdata_i (wdata_i),
    .wmask_i (bit_wmask),
    .rdata_o (rdata_o),
    .cfg_i   (prim_ram_1p_pkg::RAM_1P_CFG_REQ_DEFAULT),
    .cfg_o   (unused_cfg_rsp)
);

endmodule
