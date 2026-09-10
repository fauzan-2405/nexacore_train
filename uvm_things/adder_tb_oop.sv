// =========================================================================
// 1. ABSTRACT BASE TRANSACTION (Parent Contract)
// =========================================================================
virtual class transaction_base_oop #(parameter int DATA_WIDTH = 8);
    string inst_name;

    function new(string name = "trans_base");
        this. inst_name = name;
    endfunction

    function void display();
        $display("[TRANS BASE] Instance: %s", inst_name);
    endfunction

    // Pure virtual method: Mandatory contract for all child transaction classes
    pure virtual function bit [DATA_WIDTH-1:0] get_payload();

    // Virtual copy method interface for deep copy polymorphism
    pure virtual function transaction_base_oop #(DATA_WIDTH) copy();
endclass

// =========================================================================
// 2. CONCRETE DERIVED TRANSACTION (Child Implementation)
// =========================================================================
class adder_transaction #(parameter int DATA_WIDTH = 8)
    extends transaction_base_oop #(DATA_WIDTH);

    rand bit [DATA_WIDTH-1:0] operand_a;
    rand bit [DATA_WIDTH-1:0] operand_b;
    bit [DATA_WIDTH-1:0] expected_sum;
    bit [DATA_WIDTH-1:0] actual_sum;

    function new(string name = "adder_tx");
        super.new(name);
    endfunction

    // Overriden virtual method
    virtual function void display();
        $display("[%s] Operands: A=0x%0h (%0d), B=0x%0h (%0d) | Expected=0x%0h | Actual=0x%0h", 
            inst_name, operand_a, operand_a, operand_b, operand_b, expected_sum, actual_sum);
    endfunction

    // Implementation of pure virtual method contract
    virtual function bit [DATA_WIDTH-1:0] get_payload();
        return operand_a;
    endfunction

    // Deep Copy implementation
    virtual function transaction_base_oop #(DATA_WIDTH) copy();
        adder_transaction #(DATA_WIDTH) clone;
        clone = new(this.inst_name);
        clone.operand_a   = this.operand_a;
        clone.operand_b   = this.operand_b;
        clone.expected_sum = this.expected_sum;
        clone.actual_sum   = this.actual_sum;
        return clone;
    endfunction
endclass

// =========================================================================
// 3. PHYSICAL HARDWARE INTERFACE (Static Domain)
// =========================================================================
interface adder_if #(parameter int DATA_WIDTH = 8) (input logic clk);
    logic                  reset_n;
    logic                  valid_in;
    logic [DATA_WIDTH-1:0] a;
    logic [DATA_WIDTH-1:0] b;
    logic                  valid_out;
    logic [DATA_WIDTH:0]   sum;
endinterface

// =========================================================================
// 4. DESIGN UNDER TEST (DUT Module)
// =========================================================================
module adder #(parameter int DATA_WIDTH = 8) (
    input  logic                  clk,
    input  logic                  reset_n,
    input  logic                  valid_in,
    input  logic [DATA_WIDTH-1:0] a,
    input  logic [DATA_WIDTH-1:0] b,
    output logic                  valid_out,
    output logic [DATA_WIDTH:0]   sum
);
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
        sum       <= '0;
        valid_out <= 1'b0;
        end else begin
        valid_out <= valid_in;
        if (valid_in)
            sum <= a + b;
        else
            sum <= '0;
        end
    end
endmodule

// =========================================================================
// 5. CLASS COMPONENTS (Dynamic Domain)
// =========================================================================

// A. GENERATOR
class adder_generator #(parameter int DATA_WIDTH = 8);
    mailbox #(transaction_base_oop #(DATA_WIDTH)) gen2drv;
    int num_transactions;

    function new(mailbox #(transaction_base_oop #(DATA_WIDTH)) mb, int count);
        this.gen2drv          = mb;
        this.num_transactions = count;
    endfunction

    task run();
        adder_transaction #(DATA_WIDTH) tx;
        for (int i = 0; i < num_transactions; i++) begin
        tx = new($sformatf("Tx_%0d", i));
        if (!tx.randomize())
            $fatal(1, "[GEN] Randomization failed!");
        tx.expected_sum = tx.operand_a + tx.operand_b;
        
        // Upcasting implicit: adder_transaction passed into generic mailbox handle
        gen2drv.put(tx);
        $display("[GEN] Created & Put: A=%0d, B=%0d", tx.operand_a, tx.operand_b);
        end
    endtask
endclass

// B. DRIVER (Demonstrating $cast and Virtual Interface driving)
class adder_driver #(parameter int DATA_WIDTH = 8);
    virtual adder_if #(DATA_WIDTH)           vif;
    mailbox #(transaction_base_oop #(DATA_WIDTH)) gen2drv;

    function new(virtual adder_if #(DATA_WIDTH) vif, mailbox #(transaction_base_oop #(DATA_WIDTH)) mb);
        this.vif     = vif;
        this.gen2drv = mb;
    endfunction

    task run();
        transaction_base_oop #(DATA_WIDTH)  base_tx;
        adder_transaction #(DATA_WIDTH) adder_tx;

        forever begin
            gen2drv.get(base_tx); // Received as generic parent handle

            // DYNAMIC DOWNCASTING ($cast): Required to access child-specific fields (operand_a, operand_b)
            if (!$cast(adder_tx, base_tx)) begin
                $fatal(1, "[DRIVER] Critical Error: Received object is not an adder_transaction!");
            end

            @(posedge vif.clk);
            vif.valid_in <= 1'b1;
            vif.a        <= adder_tx.operand_a;
            vif.b        <= adder_tx.operand_b;

            @(posedge vif.clk);
            vif.valid_in <= 1'b0;
            vif.a        <= '0;
            vif.b        <= '0;
        end
    endtask
endclass


// C. MONITOR
class adder_monitor #(parameter int DATA_WIDTH = 8);
    virtual adder_if #(DATA_WIDTH)            vif;
    mailbox #(adder_transaction #(DATA_WIDTH)) mon2scb;

    function new(virtual adder_if #(DATA_WIDTH) vif, mailbox #(adder_transaction #(DATA_WIDTH)) mb);
        this.vif     = vif;
        this.mon2scb = mb;
    endfunction

    task run();
        adder_transaction #(DATA_WIDTH) tx;

        forever begin
            @(posedge vif.clk);
            if (vif.valid_out) begin
                tx = new("Monitored_Tx");
                tx.operand_a  = vif.a; // Note: Sampled from bus or synchronized pipeline
                tx.operand_b  = vif.b;
                tx.actual_sum = vif.sum;

                mon2scb.put(tx);
            end
        end
    endtask
endclass


// D. SCOREBOARD
class adder_scoreboard #(parameter int DATA_WIDTH = 8);
    mailbox #(adder_transaction #(DATA_WIDTH)) mon2scb;
    int match_count;
    int mismatch_count;

    function new(mailbox #(adder_transaction #(DATA_WIDTH)) mb);
        this.mon2scb        = mb;
        this.match_count    = 0;
        this.mismatch_count = 0;
    endfunction

    task run(int expected_count);
        adder_transaction #(DATA_WIDTH) tx;

        for (int i = 0; i < expected_count; i++) begin
        mon2scb.get(tx);
        
        // Perform Verification Check
        if (tx.actual_sum == (tx.operand_a + tx.operand_b)) begin
            $display("[SCOREBOARD] [PASS] Operands: %0d + %0d = Result: %0d", 
                    tx.operand_a, tx.operand_b, tx.actual_sum);
            match_count++;
        end else begin
            $error("[SCOREBOARD] [FAIL] Operands: %0d + %0d | Expected: %0d | Got: %0d", 
                tx.operand_a, tx.operand_b, (tx.operand_a + tx.operand_b), tx.actual_sum);
            mismatch_count++;
        end
        end

        $display("\n==================================================");
        $display("   FINAL TESTBENCH SUMMARY");
        $display("   TOTAL MATCHES    : %0d", match_count);
        $display("   TOTAL MISMATCHES : %0d", mismatch_count);
        $display("==================================================\n");
    endtask
endclass


// E. ENVIRONMENT CONTAINER
class environment #(parameter int DATA_WIDTH = 8);
    adder_generator  #(DATA_WIDTH) gen;
    adder_driver     #(DATA_WIDTH) drv;
    adder_monitor    #(DATA_WIDTH) mon;
    adder_scoreboard #(DATA_WIDTH) scb;

    mailbox #(transaction_base_oop #(DATA_WIDTH))  gen2drv_mb;
    mailbox #(adder_transaction #(DATA_WIDTH)) mon2scb_mb;

    virtual adder_if #(DATA_WIDTH) vif;

    function new(virtual adder_if #(DATA_WIDTH) vif);
        this.vif        = vif;
        this.gen2drv_mb = new();
        this.mon2scb_mb = new();

        gen = new(gen2drv_mb, 5); // Generate 5 test vectors
        drv = new(vif, gen2drv_mb);
        mon = new(vif, mon2scb_mb);
        scb = new(mon2scb_mb);
    endfunction

    task run();
        fork
        gen.run();
        drv.run();
        mon.run();
        scb.run(5);
        join_any
        #50;
    endtask
endclass


// =========================================================================
// 6. TOP TESTBENCH MODULE
// =========================================================================
module adder_top_oop;
    localparam int DW = 12; // Testbench configured for 12-bit Adder

    logic clk;

    // Clock Generation (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // A. Instantiate Physical Interface
    adder_if #(DW) intf(clk);

    // B. Instantiate Physical DUT
    adder #(DW) dut (
        .clk       (intf.clk),
        .reset_n   (intf.reset_n),
        .valid_in  (intf.valid_in),
        .a         (intf.a),
        .b         (intf.b),
        .valid_out (intf.valid_out),
        .sum       (intf.sum)
    );

    // C. Environment Handle
    environment #(DW) env;

    initial begin
        // Initialize Interface
        intf.reset_n  = 0;
        intf.valid_in = 0;
        intf.a        = 0;
        intf.b        = 0;

        // Release Reset
        #20;
        intf.reset_n  = 1;
        $display("--- Reset Released. Starting Class-Based OOP Testbench ---");

        // D. Construct Environment & Bind Physical Interface Handle
        env = new(intf);

        // E. Execute Test Run
        env.run();
        $finish;
    end
endmodule