`include "uvm_macros.svh"
import uvm_pkg::*;

// ========================================================================= 
// 1. ORIGINAL TRANSIENT DATA OBJECT (Base Packet) 
// =========================================================================
class packet_base extends uvm_object;
    rand bit [31:0] addr;
    rand bit [31:0] data;

    // Constructor for uvm_object: exactly 1 argument 'name'
    function new(string name = "packet_base")
        super.new(name);
    endfunction

    // Register with the UVM factory
    `uvm_object_utils(packet_base)

    virtual function void print_pkt();
        `uvm_info("PKT_BASE", $sformatf("Standard Packet -> Addr: 0x%8h | Data: 0x%8h", addr, data), UVM_LOW)
    endfunction
endclass

// ========================================================================= 
// 2. EXTENDED / CORRUPTED DATA OBJECT (Derived Packet)
// =========================================================================
// Let's say we want to test error injection. You create a child packet class
class packet_corrupted extends packet_base;
    bit inject_error = 1'b1;

    function new (string name = "packet_corrupted")
        super.new(name);
    endfunction

    // Register with the UVM factory
    `uvm_object_utils(packet_corrupted)

    virtual function void print_pkt();
        `uvm_info("PKT_ERR", $sformatf("[CORRUPTED] Addr: 0x%8h | Data: 0x%8h | BAD PARITY", addr, data), UVM_LOW)
    endfunction
endclass

// ========================================================================= 
// 3. STRUCTURAL COMPONENT
// =========================================================================
class my_driver extends uvm_component;
    // Constructor for uvm\_component: 2 arguments ('name' and 'parent')
    function new(string name = "my_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Register with the UVM factory
    `uvm_component_utils(my_driver)

    task run_phase(uvm_phase phase)
        packet_base pkt;

        phase.raise_objection(this);

        // CRITICAL FACTORY CONCEPT: 
        // Notice we do NOT use: pkt = new("pkt"); 
        // Instead, we ask the UVM Factory to instantiate the object!
        pkt = packet_base::type_id::create("pkt");

        if (!pkt.randomize()) begin
            `uvm_error("DRV", "Randomization failed!")
        end

        // Process packet
        pkt.print_pkt();

        phase.drop_objection(this);
    endtask
endclass

// ========================================================================= 
// 4. UVM TEST
// =========================================================================
class base_test extends uvm_test;
    my_driver drv;
    
    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(base_test)

    function void build_phase(uvm_phase phase);
        // Standard component instantiation via factory
        drv = my_driver::type_id::create("drv", this);
    endfunction
endclass

// Derived Test: Applying Factory Override
class error_test extends base_test;
    function new(string_name = "error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(error_test)

    function void build_phase(uvm_phase phase);
        // FACTORY OVERRIDE:
        // Tell the global UVM factory to whenever anyone requests a 'packet_base' 
        // return a 'packet_corrupted' object instead
        packet_base::set_type_override(packet_corrupted::get_type());
    endfunction

    super.build_phase(phase); // Builds driver
endclass

// ========================================================================= 
// 5. TESTBENCH TOP
// =========================================================================
module tb_error_Test_uvm;
    initial begin
        run_test("error_test");
    end
endmodule