// fifomem.sv
// This is a simple FIFO memory module that can be used for clock domain crossing.

module fifomem #(
    parameter WIDTH = 8, // Width of the data bus
    parameter DEPTH = 16, // Depth of the FIFO
    paramerter ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic wclk, // Write clock
    input logic wclk_en, // Write clock enable
    input logic [WIDTH-1:0] wdata, // Write data
    input logic [ADDR_WIDTH-1:0] waddr, // Write address
    input logic [ADDR_WIDTH-1:0] raddr, // Read address
    input logic [WIDTH-1:0] rdata // Read data
);
    
endmodule