`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// 1. TRANSACTIONS (uvm_object branch)
// ============================================================================

// Base Sequence Item
class packet_seq_item extends uvm_sequence_item;
    rand bit [7:0] data;
    rand bit       has_error;

    `uvm_object_utils_begin(packet_seq_item)
        `uvm_field_int(data, UVM_DEFAULT)
        `uvm_field_int(has_error, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "packet_seq_item");
        super.new(name);
    endfunction

    virtual function void print_packet();
        `uvm_info("ITEM", $sformatf("[NORMAL PACKET] Data: 0x%0h | Error Flag: %0b", data, has_error), UVM_LOW)
  endfunction
endclass

// Derived Subtype for Error-Injection Override
class corrupted_packet_seq_item extends packet_seq_item;
    `uvm_object_utils(corrupted_packet_seq_item)

    function new(string name = "corrupted_packet_seq_item");
        super.new(name);
    endfunction

    // Override behavior to force corrupted data
    constraint force_error_c {
        has_error == 1'b1;
    }

    virtual function void print_packet();
        `uvm_info("ITEM", $sformatf("[CORRUPTED PACKET] Data: 0x%0h | Error Flag: %0b (FORCED ERROR)", data, has_error), UVM_LOW)
    endfunction
endclass

// ============================================================================
// 2. STRUCTURAL COMPONENTS (uvm_component branch)
// ============================================================================

// Driver: Demonstrates Dynamic Factory Creation
class packet_driver extends uvm_driver #(packet_seq_item);
    `uvm_component_utils(packet_driver)

    function new(string name = "packet_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        packet_seq_item item;
        phase.raise_objection(this);

        for (int i = 0; i < 3; i++) begin
        // Instantiation using the UVM Factory pattern (No raw new() calls)
        item = packet_seq_item::type_id::create("item", this);
        
        void'(item.randomize());
        item.print_packet();
        #10;
        end

        phase.drop_objection(this);
    endtask
endclass

// Environment Component
class packet_env extends uvm_env;
        `uvm_component_utils(packet_env)

        packet_driver drv;

        function new(string name = "packet_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            drv = packet_driver::type_id::create("drv", this);
    endfunction
endclass

// ============================================================================
// 3. TESTS
// ============================================================================

// Base Test (Standard Operation)
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    packet_env env;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = packet_env::type_id::create("env", this);
    endfunction
endclass

// Factory Override Test (Injects Corrupted Packets Dynamically)
class factory_override_test extends base_test;
    `uvm_component_utils(factory_override_test)

    function new(string name = "factory_override_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        // Execute global factory type override before creating components
        packet_seq_item::type_id::set_type_override(corrupted_packet_seq_item::get_type());
        
        `uvm_info("FACTORY_OVERRIDE", "Registered type override: packet_seq_item -> corrupted_packet_seq_item", UVM_LOW)
        super.build_phase(phase);
    endfunction
endclass

// ============================================================================
// 4. TOP MODULE RUNNER
// ============================================================================
module tb_uvm_factory_override;
    initial begin
        // Run the override test to demonstrate dynamic type replacement
        run_test("factory_override_test");
    end
endmodule 