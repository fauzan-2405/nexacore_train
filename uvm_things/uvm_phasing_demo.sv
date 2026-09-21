`include "uvm_macros.svh"
import uvm_package::*;

// ====================================================================
// 1. LEAF COMPONENTS (Level 4: Driver & Monitor)
// ====================================================================

// DRIVER
class my_driver extends uvm_driver;
    function new (string name = "my_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    `uvm_component_utils(my_driver)

    virtual function void build_phase (uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BUILD_PHASE", " [DRIVER] 1. Executing build_phase (Top-Down)", UVM_LOW)
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("CONN_PHASE", " [DRIVER] 2. Executing connect_phase (Bottom-Up)", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        `uvm_info("RUN_PHASE", " [DRIVER] 3. Executing run_phase (Parallel Task)", UVM_LOW)
    endtask

    virtual function void report_phase (uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("RPT_PHASE", "[DRIVER] 4. Executing report_phase (Bottom-Up)", UVM_LOW)
    endfunction
endclass


// MONITOR
class my_monitor extends uvm_monitor;
    function new(string name = "my_monitor", uvm_component parent = null);
        super.new(name);
    endfunction
    `uvm_component_utils(my_monitor)

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BUILD_PHASE", " [MONITOR] 1. Executing build_phase (Top-Down)", UVM_LOW)
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("CONN_PHASE", " [MONITOR] 2. Executing connect_phase (Bottom-Up)", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        `uvm_info("RUN_PHASE" , " [MONITOR] 3. Executing run_phase (Parallel Task)", UVM_LOW)
    endtask

    virtual function report_phase(uvm_phase phase);
        `uvm_info("RPT_PHASE" , " [MONITOR] 4. Executing report_phase (Bottom-Up)", UVM_LOW)
    endfunction
endclass


// ====================================================================
// 2. AGENT CONTAINER (Level 3: Parent to Driver & Monitor)
// ====================================================================

// MY_AGENT
class my_agent extends uvm_agent;
    my_driver   drv;
    my_monitor  mon;
    
    function new(string name ="my_agent", uvm_componenet parent = null);
        super.new(name, parent);
    endfunction
    `uvm_component_utils(my_agent)

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BUILD_PHASE", " [AGENT] 1. Executing build_phase (Top-Down)", UVM_LOW)
        // Instantiate leaf components
        drv = my_driver::type_id::create("drv", this);
        mon = my_monitor::type_id::create("mon", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("CONN_PHASE", " [MONITOR] 2. Executing connect_phase (Bottom-Up)", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        `uvm_info("RUN_PHASE" , " [MONITOR] 3. Executing run_phase (Parallel Task)", UVM_LOW)
    endtask

    virtual function report_phase(uvm_phase phase);
        `uvm_info("RPT_PHASE" , " [MONITOR] 4. Executing report_phase (Bottom-Up)", UVM_LOW)
    endfunction
endclass

// ====================================================================
// 3. ENVIRONMENT CONTAINER (Level 2: Parent to Agent)
// ====================================================================

// ENVIRONMENT
class my_env extends uvm_env;
    my_agent agent;

    function new(string name ="my_env", uvm_componenet parent = null);
        super.new(name, parent);
    endfunction
    `uvm_component_utils(my_env)

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BUILD_PHASE", " [ENV] 1. Executing build_phase (Top-Down)", UVM_LOW)
        // Instantiate leaf components
        agent = my_agent::type_id::create("agent", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("CONN_PHASE", " [ENV] 2. Executing connect_phase (Bottom-Up)", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        `uvm_info("RUN_PHASE" , " [ENV] 3. Executing run_phase (Parallel Task)", UVM_LOW)
    endtask

    virtual function report_phase(uvm_phase phase);
        `uvm_info("RPT_PHASE" , " [ENV] 4. Executing report_phase (Bottom-Up)", UVM_LOW)
    endfunction
endclass


// ====================================================================
// 4. TOP TEST (Level 1: ROOT COMPONENT)
// ====================================================================
class phasing_test extends uvm_tst;
my_env env;

    function new(string name ="phasing test", uvm_componenet parent = null);
        super.new(name, parent);
    endfunction
    `uvm_component_utils(phasing_test)

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BUILD_PHASE", " [TEST_TOP] 1. Executing build_phase (Top-Down)", UVM_LOW)
        // Instantiate leaf components
        env = my_env::type_id::create("agent", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("CONN_PHASE", " [TEST_TOP] 2. Executing connect_phase (Bottom-Up)", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        `uvm_info("RUN_PHASE" , " [TEST_TOP] 3. Executing run_phase (Parallel Task)", UVM_LOW)
    endtask

    virtual function report_phase(uvm_phase phase);
        `uvm_info("RPT_PHASE" , " [TEST_TOP] 4. Executing report_phase (Bottom-Up)", UVM_LOW)
    endfunction
endclass


// ====================================================================
// 5. TESTBENCH TOP MODULE
// ====================================================================
module uvm_phasing_demo;
    initial begin
        run_test("phasing_test");
    end
endmodule