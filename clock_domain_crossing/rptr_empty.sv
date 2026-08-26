// rptr_empty.sv
// Generates the RAM read address, the Gray-code read pointer,
// and detects the registered FIFO empty condition.

module rptr_empty #(
    parameter WIDTH = 8, // Width of the data bus
    parameter DEPTH = 16, // Depth of the FIFO
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic rclk,
    input logic rrst_n,
    input logic rinc,
    input logic [ADDR_WIDTH:0] rq2_wptr,   // Synchronized grey code write pointer

    output logic [ADDR_WIDTH-1:0] raddr,
    output logic [ADDR_WIDTH:0] rptr,
    output logic rempty
);
    logic [ADDR_WIDTH:0] rptr_bin, rptr_gray;
    logic [ADDR_WIDTH:0] rptr_bin_next, rptr_gray_next;
    logic rempty_val;

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (~rrst_n) begin
            rptr_bin    <= '0;
            rptr_gray   <= '0;
            rempty      <= 1'b1;
        end else begin
            rptr_bin    <= rptr_bin_next;
            rptr_gray   <= rptr_gray_next;
            rempty      <= rempty_val;
        end
    end

    assign rempty_val       = (rptr_gray_next == rq2_wptr);
    assign rptr_bin_next    = rptr_bin + (rinc & ~rempty); 
    assign rptr_gray_next   = (rptr_bin_next >> 1) ^ rptr_bin_next;
    assign rptr             = rptr_gray;
    assign raddr            = rptr_bin[ADDR_WIDTH-1:0];

endmodule