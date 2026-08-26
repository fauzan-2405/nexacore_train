// wptr_full.sv
// Generates the RAM write address, the Gray-code write pointer,
// and detects the registered FIFO full condition.

module wptr_full #(
    parameter WIDTH = 8, // Width of the data bus
    parameter DEPTH = 16, // Depth of the FIFO
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic wclk,
    input logic wrst_n,
    input logic winc,
    input logic [ADDR_WIDTH:0] wq2_rptr,   // Synchronized read pointer

    output logic [ADDR_WIDTH-1:0] waddr,
    output logic [ADDR_WIDTH:0] wptr,
    output logic wfull
);
    logic [ADDR_WIDTH:0] wptr_bin, wptr_gray;
    logic [ADDR_WIDTH:0] wptr_bin_next, wptr_gray_next;
    logic wfull_val;

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (~wrst_n) begin
            wptr_bin    <= '0;
            wptr_gray   <= '0;
            wfull       <= 1'b0;
        end else begin
            wptr_bin    <= wptr_bin_next;
            wptr_gray   <= wptr_gray_next;
            wfull       <= wfull_val;
        end
    end

    assign wfull_val        = wptr_gray_next == ({~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1], wq2_rptr[ADDR_WIDTH-2:0]});
    assign wptr_bin_next    = wptr_bin + (winc & ~wfull); 
    assign wptr_gray_next   = (wptr_bin_next >> 1) ^ wptr_bin_next;
    assign wptr             = wptr_gray;
    assign waddr            = wptr_bin[ADDR_WIDTH-1:0];

endmodule