// testbench_axis_wrapper.sv
// Advanced self-checking testbench for AXI4-Stream Asynchronous FIFO Wrapper (axis_wrapper.sv)
// Simulates independent clock domains, randomized source stalls, and downstream backpressure.

`timescale 1ns/1ps

module testbench_axis_wrapper;

    parameter WIDTH = 8;
    parameter DEPTH = 16;
    
    // Clock and Reset Signals
    logic s_axis_aclk;
    logic s_axis_aresetn;
    logic m_axis_aclk;
    logic m_axis_aresetn;

    // AXI-Stream Slave Interface (Write Domain)
    logic [WIDTH-1:0] s_axis_tdata;
    logic             s_axis_tvalid;
    logic             s_axis_tready;

    // AXI-Stream Master Interface (Read Domain)
    logic [WIDTH-1:0] m_axis_tdata;
    logic             m_axis_tvalid;
    logic             m_axis_tready;

    // Testbench tracking queues for golden verification
    int expected_queue[$];
    int actual_queue[$];
    int total_writes = 0;
    int total_reads = 0;

    // =========================================================================
    // 1. Clock Generation (100 MHz vs 62.5 MHz to emulate drift/CDC)
    // =========================================================================
    initial s_axis_aclk = 0;
    always #5 s_axis_aclk = ~s_axis_aclk; // 10ns period (100 MHz)

    initial m_axis_aclk = 0;
    always #8 m_axis_aclk = ~m_axis_aclk; // 16ns period (62.5 MHz)

    // =========================================================================
    // 2. Device Under Test (DUT) Instantiation
    // =========================================================================
    axis_wrapper #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .s_axis_aclk    (s_axis_aclk),
        .s_axis_aresetn (s_axis_aresetn),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),

        .m_axis_aclk    (m_axis_aclk),
        .m_axis_aresetn (m_axis_aresetn),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready)
    );

    // =========================================================================
    // 3. Helper Functions & Tasks
    // =========================================================================
    
    // Generates a random delay to simulate timing jitter
    function int random_delay();
        return $urandom_range(1, 15);
    endfunction

    // AXI-Stream Master Task (Write Domain)
    // Simulates an upstream master that can randomly stall/jitter by dropping TVALID
    task automatic axis_write(input logic [WIDTH-1:0] data, input bit random_stall = 0);
        // If random stall is enabled, occasionally introduce idle cycles before driving TVALID
        if (random_stall && ($urandom_range(0, 9) < 3)) begin
            int stall_cycles = $urandom_range(1, 4);
            repeat (stall_cycles) @(posedge s_axis_aclk);
        end

        @(posedge s_axis_aclk);
        s_axis_tvalid <= 1'b1;
        s_axis_tdata  <= data;

        // Wait here until the handshake actually occurs (both VALID and READY high at clock edge)
        do begin
            @(posedge s_axis_aclk);
        end while (!s_axis_tready);

        // De-assert VALID to prevent double writing unless another transfer starts immediately
        s_axis_tvalid <= 1'b0;
        s_axis_tdata  <= 'x;
        
        expected_queue.push_back(data);
        total_writes++;
        $display("[MASTER WRITE] Time=%0t | Transferred Data=0x%h | Total Writes=%0d", $time, data, total_writes);
    endtask

    // AXI-Stream Slave Task (Read Domain)
    // Simulates a downstream receiver that can randomly apply backpressure by dropping TREADY
    task automatic axis_read(output logic [WIDTH-1:0] data_out, input bit random_stall = 0);
        // If random stall is enabled, occasionally introduce backpressure cycles before driving TREADY
        if (random_stall && ($urandom_range(0, 9) < 4)) begin
            int backpressure_cycles = $urandom_range(1, 3);
            m_axis_tready <= 1'b0;
            repeat (backpressure_cycles) @(posedge m_axis_aclk);
        end

        @(posedge m_axis_aclk);
        m_axis_tready <= 1'b1;

        // Wait until a valid handshake occurs
        do begin
            @(posedge m_axis_aclk);
        end while (!m_axis_tvalid);

        data_out = m_axis_tdata;
        m_axis_tready <= 1'b0; // Release ready after capture

        actual_queue.push_back(data_out);
        total_reads++;
        $display("[SLAVE READ]   Time=%0t | Captured Data=0x%h    | Total Reads=%0d", $time, data_out, total_reads);
    endtask

    // =========================================================================
    // 4. Main Test Sequence
    // =========================================================================
    initial begin
        s_axis_aresetn = 1'b0;
        m_axis_aresetn = 1'b0;
        s_axis_tvalid  = 1'b0;
        s_axis_tdata   = '0;
        m_axis_tready  = 1'b0;

        $display("======================================================================");
        $display("Starting AXI4-Stream Asynchronous FIFO Wrapper Simulation...");
        $display("======================================================================");

        // ---------------------------------------------------------------------
        // Test Case 1: Power-On Reset & Initialization Verification
        // ---------------------------------------------------------------------
        #50;
        @(posedge s_axis_aclk);
        s_axis_aresetn <= 1'b1;
        $display("[TEST SYSTEM] Write reset released.");

        #30;
        @(posedge m_axis_aclk);
        m_axis_aresetn <= 1'b1;
        $display("[TEST SYSTEM] Read reset released.");

        // Verify startup flag states
        @(posedge s_axis_aclk);
        assert(s_axis_tready === 1'b1) else $error("[ERROR] At startup, s_axis_tready should be asserted!");
        
        @(posedge m_axis_aclk);
        assert(m_axis_tvalid === 1'b0) else $error("[ERROR] At startup, m_axis_tvalid should be de-asserted!");

        #20;

        // ---------------------------------------------------------------------
        // Test Case 2: Standard Write-Burst to Full (Full Throttling Test)
        // ---------------------------------------------------------------------
        $display("\n--- Starting Test Case 2: Writing until full (16 items) ---");
        for (int i = 1; i <= DEPTH; i++) begin
            axis_write(i);
        end

        // Ensure that the FIFO is full and s_axis_tready is de-asserted
        @(posedge s_axis_aclk);
        assert(s_axis_tready === 1'b0) else $error("[ERROR] FIFO is full, s_axis_tready must go LOW!");
        $display("[TEST VERIFIED] FIFO successfully throttled the Master! s_axis_tready is LOW.");

        // Attempt a 17th write (overflow prevention)
        fork
            begin
                // This process will wait indefinitely because s_axis_tready is low
                axis_write(8'hFF); 
                $display("[TEST VERIFIED] Ahoy");
            end
            begin
                // Timeout monitor to prove the write was blocked
                #100;
                $display("[TEST VERIFIED] 17th write was successfully blocked (backpressured) as expected.");
                // Clean up the stalled valid line
                s_axis_tvalid <= 1'b0;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // Test Case 3: Standard Read-Burst to Empty (Empty Stalling Test)
        // ---------------------------------------------------------------------
        $display("\n--- Starting Test Case 3: Reading until empty (16 items) ---");
        for (int i = 0; i < DEPTH; i++) begin
            logic [WIDTH-1:0] read_val;
            axis_read(read_val);
        end

        // Verify that empty de-asserts m_axis_tvalid
        @(posedge m_axis_aclk);
        assert(m_axis_tvalid === 1'b0) else $error("[ERROR] FIFO is empty, m_axis_tvalid must go LOW!");
        $display("[TEST VERIFIED] FIFO successfully stalled the Slave! m_axis_tvalid is LOW.");

        #100;

        // ---------------------------------------------------------------------
        // Test Case 4: Concurrent Randomized Read/Write (Stress Test)
        // ---------------------------------------------------------------------
        $display("\n--- Starting Test Case 4: Concurrent Read/Write Stress Test ---");
        
        fork
            // Write Thread: Drives 32 data frames with randomized source delays
            begin
                for (int val = 100; val < 132; val++) begin
                    axis_write(val, 1); // Enable random master stalls
                    #(random_delay());
                end
            end

            // Read Thread: Receives 32 data frames with randomized destination backpressure
            begin
                for (int count = 0; count < 32; count++) begin
                    logic [WIDTH-1:0] val_read;
                    axis_read(val_read, 1); // Enable random slave backpressure
                    #(random_delay());
                end
            end
        join

        // ---------------------------------------------------------------------
        // Test Case 5: Self-Checking Data Integrity Verification
        // ---------------------------------------------------------------------
        $display("\n--- Starting Test Case 5: Verification and Post-Run Integrity Checks ---");
        
        // Let the remaining CDC sync lines settle
        #200;

        // Check if queues match
        if (expected_queue.size() != actual_queue.size()) begin
            $error("[FAIL] Size mismatch! Expected %0d items, but captured %0d items.", 
                    expected_queue.size(), actual_queue.size());
        end else begin
            static bit pass = 1;
            static int size = expected_queue.size();
            for (int idx = 0; idx < size; idx++) begin
                if (expected_queue[idx] !== actual_queue[idx]) begin
                    $error("[FAIL] Data mismatch at index %0d! Sent=0x%h, Recv=0x%h", 
                            idx, expected_queue[idx], actual_queue[idx]);
                    pass = 0;
                end
            end
            if (pass) begin
                $display("======================================================================");
                $display("  [SUCCESS] All %0d transactions passed self-checking assertions!  ", size);
                $display("  No data loss, no duplication, and 100%% correct packet ordering. ");
                $display("======================================================================");
            end
        end

        $finish;
    end

endmodule
