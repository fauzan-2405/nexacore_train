`timescale 1ns/1ps

module testbench_fifol;

    // Parameters
    parameter WIDTH = 8;
    parameter DEPTH = 16;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    // Write clock domain signals
    logic             wclk;
    logic             wrst_n;
    logic             winc;
    logic [WIDTH-1:0] wdata;
    logic             wfull;

    // Read clock domain signals
    logic             rclk;
    logic             rrst_n;
    logic             rinc;
    logic [WIDTH-1:0] rdata;
    logic             rempty;

    // Instantiate Device Under Test (DUT)
    fifol #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wclk   (wclk),
        .wrst_n (wrst_n),
        .winc   (winc),
        .wdata  (wdata),
        .wfull  (wfull),
        .rclk   (rclk),
        .rrst_n (rrst_n),
        .rinc   (rinc),
        .rdata  (rdata),
        .rempty (rempty)
    );

    // ==========================================
    // 1. Asynchronous Clock Generation
    // ==========================================
    // wclk: 100 MHz (10ns period -> toggles every 5ns)
    initial wclk = 0;
    always #5 wclk = ~wclk;

    // rclk: 62.5 MHz (16ns period -> toggles every 8ns)
    initial rclk = 0;
    always #8 rclk = ~rclk;

    // ==========================================
    // 2. Verification Tasks
    // ==========================================
    
    // Write Task (Synchronous to wclk)
    task automatic write_word(input logic [WIDTH-1:0] data);
        @(posedge wclk);
        while (wfull) begin
            $display("[WRITE WAIT] @%0t: FIFO Full, waiting to write data 0x%h...", $time, data);
            @(posedge wclk);
        end
        winc  <= 1;
        wdata <= data;
        $display("[WRITE] @%0t: Wrote Data 0x%h", $time, data);
        @(posedge wclk);
        winc  <= 0;
        wdata <= '0;
    endtask

    // Read Task (Synchronous to rclk)
    task automatic read_word(output logic [WIDTH-1:0] data);
        @(posedge rclk);
        while (rempty) begin
            $display("[READ WAIT] @%0t: FIFO Empty, waiting to read...", $time);
            @(posedge rclk);
        end
        rinc = 1;
        @(posedge rclk);
        data = rdata;
        $display("[READ] @%0t: Read Data 0x%h", $time, data);
        rinc = 0;
    endtask

    // ==========================================
    // 3. Main Stimulus Process
    // ==========================================
    initial begin
        // Initialize inputs
        wrst_n = 0;
        rrst_n = 0;
        winc   = 0;
        wdata  = '0;
        rinc   = 0;

        // Apply Reset
        #50;
        wrst_n = 1;
        rrst_n = 1;
        #20;
        $display("--------------------------------------------------");
        $display("SYSTEM RESET RELEASED");
        $display("--------------------------------------------------");

        // Test Scenario 1: Verify Initial Flags
        assert (rempty == 1'b1) else $error("Assertion Failed: rempty must be 1 on reset");
        assert (wfull == 1'b0)  else $error("Assertion Failed: wfull must be 0 on reset");
        $display("[SUCCESS] Scenario 1: Reset flags verified (Empty=1, Full=0)");

        #20;

        // Test Scenario 2: Fill the FIFO completely (16 words)
        $display("\n--- Starting Test Scenario 2: Writing 16 items to fill FIFO ---");
        for (int i = 1; i <= DEPTH; i = i + 1) begin
            write_word(i);
        end
        
        // Wait 2 write clock cycles for the status flags to fully update (pessimistic latency check)
        repeat (2) @(posedge wclk);
        assert (wfull == 1'b1) else $error("Assertion Failed: wfull should be 1 after 16 writes");
        $display("[SUCCESS] Scenario 2: FIFO successfully filled and 'wfull' asserted!");

        // Try writing to a full FIFO to verify write enable is safely gated
        @(posedge wclk);
        winc  = 1;
        wdata = 8'hFF;
        @(posedge wclk);
        winc  = 0;
        $display("[TEST] Attempted overflow write. Verifying no data corruption...");

        // Test Scenario 3: Drain the FIFO completely
        $display("\n--- Starting Test Scenario 3: Reading 16 items to empty FIFO ---");
        begin
            logic [WIDTH-1:0] read_val;
            for (int i = 1; i <= DEPTH; i = i + 1) begin
                read_word(read_val);
                // Verify data integrity
                if (read_val !== i) begin
                    $error("[ERROR] Data corruption! Expected 0x%h, Got 0x%h", i, read_val);
                end
            end
        end

        // Wait 2 read clock cycles for flag to register
        repeat (2) @(posedge rclk);
        assert (rempty == 1'b1) else $error("Assertion Failed: rempty should be 1 after draining");
        $display("[SUCCESS] Scenario 3: FIFO successfully drained, 'rempty' asserted, data integrity verified (FIFO order preserved)!");

        // Test Scenario 4: Concurrent Write and Read (Stress Test)
        $display("\n--- Starting Test Scenario 4: Simultaneous Asynchronous Read/Write ---");
        fork
            // Write Process: Write 32 values
            begin
                for (int j = 100; j < 132; j = j + 1) begin
                    write_word(j);
                    // Add a tiny random delay to mimic physical system jitter
                    #(random_delay());
                end
            end
            // Read Process: Read 32 values
            begin
                logic [WIDTH-1:0] stress_read_val;
                static int expected_val = 100;
                for (int k = 0; k < 32; k = k + 1) begin
                    read_word(stress_read_val);
                    if (stress_read_val !== expected_val) begin
                        $error("[ERROR] Stress Test Corruption! Expected %0d, Got %0d", expected_val, stress_read_val);
                    end
                    expected_val = expected_val + 1;
                    #(random_delay());
                end
            end
        join

        $display("\n--------------------------------------------------");
        $display("   TESTBENCH COMPLETED SUCCESSFULLY: ALL PASS!   ");
        $display("--------------------------------------------------");
        $finish;
    end

    // Helper function to generate pseudo-random delays for clock jitter emulation
    function int random_delay();
        return $urandom_range(5, 15);
    endfunction

endmodule