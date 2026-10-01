// ========================================================================= 
// MONTH 1 CAPSTONE DELIVERABLE: FULLY INTEGRATED AXI4-STREAM UVM TESTBENCH 
// File: axis_tb_full_uvm.sv 
// Objectives: Hardware DUT Binding, uvm_config_db, Clocking Blocks, 
//              TLM Analysis Ports, Component Hierarchy & Phasing. 
// =========================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

// =========================================================================
// 1. TRANSACTION ITEM (uvm_object)
// =========================================================================
class axis_seq_item #(
    parameter int DATA_WIDTH = 32
) extends uvm_sequence_item;
    rand bit [DATA_WIDTH-1:0]   data;
    rand bit [3:0]              keep;
    rand bit                    last;

    function new(string name = "axis_seq_item");
        super.new(name);
    endfunction

    `uvm_object_utils_begin(axis_seq_item)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(keep, UVM_ALL_ON)
        `uvm_field_int(last, UVM_ALL_ON)
    `uvm_object_utils_end

    virtual function string convert2string();
        return $sformatf("DATA=0x%8h | KEEP=0x%1h | LAST=%0b", data, keep, last);
    endfunction
endclass


// =========================================================================
// 2. PHYSICAL INTERFACE WITH CLOCKING BLOCKS
// =========================================================================
interface axis_if #(
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    logic                   s_tvalid;
    logic                   s_tready;
    logic [DATA_WIDTH-1:0]  s_tdata;
    logic [3:0]             s_tkeep;
    logic                   s_tlast; 

    // Driver Clocking Block (synchronous driving to eliminate race conditions)
    clocking cb_drv @(posedge clk);
        default input #1ns output #1ns;
        output  s_tvalid, s_tdata, s_tkeep, s_tlast;
        input   s_tready;
    endclocking

    // Monitor Clocking Block (synchronous passive sampling)
    clocking cb_mon @(posedge clk);
        default input #1ns output #1ns;
        input s_tvalid, s_tready, s_tdata, s_tkeep, s_tlast;
    endclocking

    modport DRV (clocking cb_drv, input rst_n);
    modport MON (clocking cb_mon, input rst_n);
endinterface


// =========================================================================
// 3. HARDWARE DUT STUB (AXI4-Stream Asynchronous FIFO Wrapper)
// =========================================================================
module dut_axis_wrapper #(
    parameter int DATA_WIDTH = 32
) (
    input   logic aclk,
    input   logic aresetn,
    input   logic s_tvalid,
    output  logic s_tready,
    input   logic [DATA_WIDTH-1:0] s_tdata,
    input   logic [3:0] s_tkeep,
    input   logic s_tlast 
);
    // Simple synchronous handshake behavior for top-level elaboration check
    always_ff @( posedge clk ) begin
        if (!aresetn) begin
            s_tready <= 1'b0;
        end else begin
            s_tready <= 1'b1;
        end
    end
endmodule


// =========================================================================
// 4. VERIFICATION COMPONENTS
// =========================================================================

// ---- AXI4-STREAM DRIVER ----
class axis_driver #(parameter int DATA_WIDTH = 32)
    extends uvm_driver #(axis_seq_item #(DATA_WIDTH));

    virtual axis_if #(DATA_WIDTH) vif;

    function new(string name = "axis_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_driver #(DATA_WIDTH))

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("DRV_BUILD", "Building AXI-Stream Driver", UVM_LOW);
        if (!uvm_config_db#(virtual axis_if #(DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV\_NO\_VIF", "Virtual interface handle 'vif' not found in uvm config_db!")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_seq_item #(DATA_WIDTH) req_item;

        `uvm_info("DRV_RUN", "AXI-Stream Driver run_phase started", UVM_LOW)

        // Drive default inactive states
        vif.cb_drv.s_tvalid  <= 1'b0;
        vif.cb_drv.s_tdata   <= '0;
        vif.cb_drv.s_tkeep   <= '0;
        vif.cb_drv.s_tlast   <= 1'b0;

        forever begin
            // Handshake with Sequencer
            seq_item_port.get_next_item(req_item);

            // Pin-level driving protocol on AXI-Stream interface
            @(posedge vif.cb_drv);
            vif.cb_drv.s_tvalid  <= 1'b1;
            vif.cb_drv.s_tdata   <= req_item.data;
            vif.cb_drv.s_tkeep   <= req_item.keep
            vif.cb_drv.s_tlast   <= req_item.last;

            `uvm_info("DRV_DRIVE", $sformatf("Driving transaction: %s", req.convert2string()), UVM_LOW)

            // Wait for slave TREADY handshake
            do begin
                @(vif.cb_drv.clk);
            end while (!vif.cb_drv.s_tready);

            vif.cb_drv.s_tvalid <= 1 me;
            vif.cb_drv.s_tvalid <= 1'b0;

            seq_item_port.item_done();
        end
    endtask
endclass


// ---- AXI4-STREAM MONITOR ----
class axis_monitor #(parameter int DATA_WIDTH = 32)
    extends uvm_monitor #(axis_seq_item #(DATA_WIDTH));
    virtual axis_if vif;
    uvm_analysis_port #(axis_seq_item) ap;

    `uvm_component_utils(axis_monitor)

    function new (string name = "axis_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);

        if (!uvm_config_db#(virtual axis_if #(DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON_NO_VIF", "Virtual interference handle 'vif' not found in uvm_config_db!")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_seq_item #(DATA_WIDTH) observed_item;
        `uvm_info("MON_RUN", "AXI-Stream Monitor run_phase started", UVM_LOW)
        
        forever begin
            @(posedge vif.cb_mon);
            // Sample physical pin handshake
            if (vif.cb_mon.s_tvalid && vif.cb_mon.s_tready) begin
                observed_item       = axis_seq_item::type_id::create("mon_item");
                observed_item.data  = vif.cb_mon.s_data;
                observed_item.last  = vif.cb_mon.s_tlast;
                observed_item.keep  = vif.cb_mon.s_tkeep;

                `uvm_info("MON_SAMPLED", $sformat("Sampled Transaction: %s", observed_item.convert2sting()), UVM_HIGH)

                // Broadcast to Scoreboard / Coverage via TLM Analysis Port
                ap.write(observed_item);
            end
        end
    endtask
endclass


// ---- SEQUENCER & SCOREBOARD ----
class axis_sequencer #(parameter int DATA_WIDTH = 32)
    extends uvm_sequencer #(axis_seq_item #(DATA_WIDTH));
    
    function new(string name = "axis_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_sequencer #(DATA_WIDTH))
endclass

class axis_scoreboard #(parameter int DATA_WIDTH = 32) extends uvm_scoreboard;
    // TLM Analysis FIFO buffers incoming transactions from Monitor's write() calls
    uvm_tlm_analysis_fifo #(axis_seq_item #(DATA_WIDTH)) item_fifo;

    function new (string name = "axis_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_scoreboard #(DATA_WIDTH))

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_fifo = new("item_fifo", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_seq_item #(DATA_WIDTH) tx;
        forever begin
            // Non-blocking write from monitor lands in FIFO; scoreboard pops it via blocking get()
            item_fifo.get(tx);
            `uvm_info("SCB_EVAL", $sformatf("Scoreboard Evaluated: %s", tx.convert2string()), UVM_LOW)
        end
    endtask
endclass


// ---- AGENT CONTAINER ----
class axis_agent #(parameter int DATA_WIDTH = 32 ) extends uvm_agent;
    axis_sequencer  #(DATA_WIDTH) seqr;
    axis_driver     #(DATA_WIDTH) drv;
    axis_monitor    #(DATA_WIDTH) mon;

    function new (string name = "axis_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_agent #(DATA_WIDTH))

    // TOP-DOWN BUILD_PHASE
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Monitor is AWLAYS built (whenever active or passiv)
        mon = axis_monitor #(DATA_WIDTH)::type_id::create("mon", this);

        // Driver and Sequencer are ONLY built if agent is ACTIVE
        if (get_is_active() == UVM_ACTIVE) begin
            seqr = axis_sequencer #(DATA_WIDTH)::type_id::create("seqr", this);
            drv  = axis_driver    #(DATA_WIDTH)::type_id::create("drv", this);
        end
    endfunction

    // BOTTOM-UP CONNECT PHASE
    virtual function void connect_phase (uvm_phase phase);
        super.connect_phase(phase);

        // Connect driver TLM seq_item_port -> Sequencer TLM seq_item_export
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
            `uvm_info("AGT_CONN", "Connected driver seq_item_port to the Sequencer seq_item_export", UVM_LOW)
        end
    endfunction
endclass

// ---- ENVIRONMENT CONTAINER ----
class axis_env #(parameter int DATA_WIDTH = 32) extends uvm_env;
    axis_agent      #(DATA_WIDTH) agent;
    axis_scoreboard #(DATA_WIDTH) scb;

    function new (string name = "axis_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_env #(DATA_WIDTH))

    // TOP-DOWN BUILD PHASE
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent   = axis_agent        #(DATA_WIDTH)::type_id::create("agent", this);
        scb     = axis_scoreboard   #(DATA_WIDTH)::type_id::create("scb", this);
    endfunction

    // BOTTOM-UP CONNECT PHASE
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // CONNECT MONITOR ANALYSIS PORT -> SCOREBOARD ANALYSIS FIFO EXPORT
        agent.mon.ap.connect(scb.item_fifo.analysis_export);
        `uvm_info("ENV_CONN", "Connected Agent Monitor Analysis Port to Scoreboard TLM FIFO", UVM_LOW)
    endfunction
endclass

// =========================================================================
// 5. BASE TEST
// =========================================================================
class axis_base_test extends uvm_test;
    axis_env #(32) env;

    function new(string name = "axis_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_base_test)

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axis_env #(32)::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info("TEST_TOP", "Displaying Complete UVM Testbench Hierarchy Topology:", UVM_LOW)
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("TEST_RUN", "Starting AXI-Stream Base Test Run Phase", UVM_LOW)
        #200;
        `uvm_info("TEST_RUN", "Completing AXI-Stream Base Test Run Phase", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass


// =========================================================================
// 6. TESTBENCH MODULE
// =========================================================================
module axis_full_uvm;
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #25 rst_n = 1;
    end

    // Initiate Physical Interface
    axis_if #(32) intf(clk, rst_n);

    // Physical Hardware DUT
    axis_wrapper #(
        .DATA_WIDTH(32)
    ) dut (
        .aclk   (aclk),
        .aresetn(rst_n),
        .s_tvalid   (intf.s_tvalid),
        .s_tready   (intf.s_tready),
        .s_tdata    (intf.s_tdata),
        .s_tkeep    (intf.s_tkeep),
        .s_tlast    (intf.s_tlast),
    );

    initial begin
        // Store physical interface handle in uvm_config_db
        uvm_config_db #(virtual axis_if #(32))::set(null, "*", "vif", intf);

        `uvm_info("TOP_TB", "Starting UVM Structural Skeleton Simulation", UVM_LOW)
        run_test("axis_base_test");
    end
endmodule