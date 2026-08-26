// sync_ptr.sv
// Safely synchronizes a multi-bit gray code poniter accross clock domain
// using a 2-stage FF chain with Vivado placement optimization

module sync_ptr #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic                 dest_clk,   // Destination clock domain
    input logic                 dest_rst_n, // Destination asynchrronous reset
    input logic [ADDR_WIDTH:0]  ptr_in,
    output logic [ADDR_WIDTH:0] ptr_out 
);
    // Apply the ASYNC_REG attribute to tell Vivado these are back-to-back CDC registers.
    // This forces Vivado to place them in the same slice/CLB to maximize metastability recovery.
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] sync_reg_0;
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] sync_reg_1;

    always_ff @(posedge dest_clk or negedge dest_rst_n) begin
        if (~dest_rst_n) begin
            sync_reg_0  <= '0;
            sync_reg_1  <= '0;
        end else begin
            sync_reg_0  <= ptr_in;
            sync_reg_1  <= sync_reg_0;
        end
    end

    assign ptr_out  = sync_reg_1;
endmodule