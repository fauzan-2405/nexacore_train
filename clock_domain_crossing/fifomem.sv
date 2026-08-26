// fifomem.sv
// This is a simple FIFO memory module that can be used for clock domain crossing.

module fifomem #(
    parameter WIDTH = 8, // Width of the data bus
    parameter DEPTH = 16, // Depth of the FIFO
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic wclk, // Write clock
    input logic wclk_en, // Write clock enable
    input logic [WIDTH-1:0] wdata, // Write data
    input logic [ADDR_WIDTH-1:0] waddr, // Write address
    input logic [ADDR_WIDTH-1:0] raddr, // Read address
    output logic [WIDTH-1:0] rdata // Read data
);
    logic [WIDTH-1:0] mem [0:DEPTH-1]; // Memory array

    always_ff @(posedge wclk) begin
        if (wclk_en) begin
            mem[waddr] <= wdata; // Write data to memory
        end
    end

    assign rdata = mem[raddr]; // Read data from memory
endmodule