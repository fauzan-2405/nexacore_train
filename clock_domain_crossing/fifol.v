// fifol.v
// Used as a top level for clock domain crossing

module fifol #(
    parameter WIDTH = 8,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input wire wclk,
    input wire wrst_n,
    input wire winc,
    input wire [WIDTH-1:0] wdata, // Write data
    output wire wfull,

    input wire rclk,
    input wire rrst_n,
    input wire rinc,
    output wire [WIDTH-1:0] rdata, // Read data
    output wire rempty
);
    // FIFO Write
    wire fifo_write_full;
    wire [ADDR_WIDTH-1:0] fifo_write_addr;
    wire [ADDR_WIDTH:0] fifo_write_ptr;
    wire [ADDR_WIDTH:0] fifo_rq2_wptr;

    // FIFO Read
    wire fifo_read_empty;
    wire [ADDR_WIDTH-1:0] fifo_read_addr;
    wire [ADDR_WIDTH:0] fifo_read_ptr;
    wire [ADDR_WIDTH:0] fifo_wq2_rptr;

    // ================== FIFO Write Controller ================== 
    wptr_full #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) fifo_write_ctrl (
        .wclk(wclk),
        .wrst_n(wrst_n),
        .winc(winc),
        .wq2_rptr(fifo_wq2_rptr),
        
        .waddr(fifo_write_addr),
        .wptr(fifo_write_ptr),
        .wfull(fifo_write_full)
    );

    // ================== Write 2 Read Syncrhonizer ================== 
    sync_ptr #(
        .DEPTH(DEPTH)
    ) sync_w2r (
        .dest_clk   (rclk),
        .dest_rst_n (rrst_n),
        .ptr_in     (fifo_write_ptr),
        .ptr_out    (fifo_rq2_wptr)
    );

    // ================== Read 2 Write Syncrhonizer ================== 
    sync_ptr #(
        .DEPTH(DEPTH)
    ) sync_r2w (
        .dest_clk   (wclk),
        .dest_rst_n (wrst_n),
        .ptr_in     (fifo_read_ptr),
        .ptr_out    (fifo_wq2_rptr)
    );
    
    // ================== FIFO Read Controller ================== 
    rptr_empty #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) fifo_read_ctrl (
        .rclk(rclk),
        .rrst_n(rrst_n),
        .rinc(rinc),
        .rq2_wptr(fifo_rq2_wptr),
        
        .raddr(fifo_read_addr),
        .rptr(fifo_read_ptr),
        .rempty(fifo_read_empty)
    );

    // ================== FIFO Memory ==================
    fifomem #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) fifo_memory (
        .wclk(wclk),
        .wclk_en(winc & ~fifo_write_full),
        .wdata(wdata),
        .waddr(fifo_write_addr),
        .raddr(rdata)
    );

    assign wfull    = fifo_write_full;
    assign rempty   = fifo_read_empty;

endmodule