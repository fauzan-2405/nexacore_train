// axis_wrapper.sv
// Used to wrap the asynchronous FIFO (fifol.sv) to a AXI handshaking-interface

module axis_wrapper #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
) (
    // Slave Interface
    input wire s_axis_aclk,
    input wire s_axis_aresetn,
    input wire [WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready, 

    // Master Interface
    input wire m_axis_aclk,
    input wire m_axis_aresetn,
    output wire [WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready
);
    wire fifo_write_full;
    wire fifo_write_empty;

    wire winc_valid;
    wire rinc_valid;

    fifol #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) async_fifo (
        .wclk   (s_axis_aclk),
        .wrst_n (s_axis_aresetn),
        .winc   (winc_valid),
        .wdata  (s_axis_tdata),
        .wfull  (fifo_write_full),
        .rclk   (m_axis_aclk),
        .rrst_n (m_axis_aresetn),
        .rinc   (rinc_valid),
        .rdata  (m_axis_tdata),
        .rempty (fifo_write_empty)
    );

    assign winc_valid    = !fifo_write_full && s_axis_tvalid;
    assign s_axis_tready = !fifo_write_full;

    assign m_axis_tvalid = !fifo_read_empty;
    assign rinc_valid    = !m_axis_tvalid && m_axis_tready;

endmodule