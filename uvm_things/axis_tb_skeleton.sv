`include "uvm_macros.svh"
import uvm_pkg::*;

// ========================================================================
// 1. AXI4-STREAM PHYSICAL INTERFACE (Static Domain)
// ========================================================================
interface axis_if #(
    parameter int DATA_WIDTH = 32
) (
    input logic clk
);
    logic                   reset_n;
    logic                   tvalid;
    logic                   tready;
    logic [DATA_WIDTH-1:0]  tdata;
    logic                   tlast;
endinterface

// ========================================================================
// 2. TRANSACTION ITEM (uvm_object)
// ========================================================================
class axis_seq_item #(
    parameter int DATA_WIDTH = 32
) extends uvm_sequence_item;
    rand bit [DATA_WIDTH-1:0]   tdata;
    rand bit                    tlast;
    bit                         tready;

    function new(string name = "axis_seq_item");
        super.new(name);
    endfunction

    `uvm_object_utils(axis_seq_item)
        `uvm_field_int(tdata, UVM_ALL_ON)
        `uvm_field_int(tlast, UVM_ALL_ON)
        `uvm_field_int(tready, UVM_ALL_ON)
    `uvm_object_utils_end

    virtual function string convert2string();
        return $sformatf("TDATA=0x%8h | TLAST=%0b | TREADY=%0b", tdata, tlast, tready);
    endfunction
endclass

// ========================================================================
// 3. SEQUENCER COMPONENT (uvm_sequencer)
// ========================================================================
class axis_sequencer #(parameter int DATA_WIDTH = 32)
    extends uvm_sequencer #(axis_seq_item #(DATA_WIDTH));
    
    function new(string name = "axis_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_sequencer #(DATA_WIDTH))
endclass

// ========================================================================
// 4. DRIVER COMPONENT (uvm_driver)
// ========================================================================
class axis_driver #(parameter int DATA_WIDTH = 32)
    extends uvm_driver #(axis_seq_item #(DATA_WIDTH));

    virtual axis_if #(DATA_WIDTH) vif;

    function new(string name = "axis_Driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_sequencer #(DATA_WIDTH))

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
        vif.tvalid  <= 1'b0;
        vif.tdata   <= '0;
        vif.tlast   <= 1'b0;

        forever begin
            // Handshake with Sequencer
            seq_item_port.get_next_item(req_item);

            // Pin-level driving protocol on AXI-Stream interface
            @(posedge vif.clk);
            vif.tvalid  <= 1'b1;
            vif.tdata   <= req_item.tdata;
            vif.tlast   <= req_item.tlast;

            // Wait for slave TREADY handshake
            do begin
                @(posedge vif.clk);
            end while (!vif.tready);

            vif.tvalid  <= 1'b0;
            vif.tlast   <= 1'b0;

            seq_item_port.item_done();
        end
    endtask
endclass

// ========================================================================
// 5. MONITOR COMPONENT (uvm_monitor + uvm_analysis_port)
// ========================================================================
class axis_monitor #(parameter int DATA_WIDTH = 32) extends uvm_monitor;
    virtual axis_if #(DATA_WIDTH) vif;
    // TLM Analysis Port for non-blocking 1-to-many transaction broadcasting
    uvm_analysis_port #(axis_seq_item #(DATA_WIDTH)) ap;

    function new (string name = "axis_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_monitor #(DATA_WIDTH))

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this); // Instantiate TLM Analysis Port

        if (!uvm_config_db#(virtual axis_if #(DATA_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal_("MON_NO_VIF", "Virtual interference handle 'vif' not found in uvm_config_db!")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_seq_item #(DATA_WIDTH) observed_item;
        `uvm_info("MON_RUN", "AXI-Stream Monitor run_phase started", UVM_LOW)
        
        forever begin
            @(posedge vif.clk);
            // Sample physical pin handshake
            if (vif.tvalid && vif.tready) begin
                observed_item.tdata = vif.tdata;
                observed_item.tlast = vif.tlast;
                observed_item.teready = vif.tready;

                `uvm_info("MON_SAMPLED", $sformat("Sampled Transaction: %s", observed_item.convert2sting()), UVM_HIGH)

                // Broadcast to Scoreboard / Coverage via TLM Analysis Port
                ap.write(observed_item);
            end
        end
    endtask
endclass


// ========================================================================
// 6. AGENT CONTAINER (uvm_agent - Active/Passive Handling)
// ========================================================================
class axis_agent #(parameter int DATA_WIDTH = 32 ) extends uvm_agent;
    axis_sequencer  #(DATA_WIDTH) seqr;
    axis_driver     #(DATA_WIDTH) drv;
    axis_monitor    #(DATA_WIDTH) mon;

    function new (string name = "axis_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    `uvm_component_utils(axis_monitor #(DATA_WIDTH))

    // TOP-DOWN BUILD_PHASE
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Monitor is AWLAYS built (whenever active or passiv)
        mon = axis_monitor #(DATA_WIDTH)::type_id::create("mon", this);

        // Driver and Sequencer are ONLY built if agent is ACTIVE
        if (get_is_active() == UVM_ACTIVE) begin
            seqr = axis_sequencer #(DATA_WIDTH::type_id::create("seqr", this));
            drv  = axis_drover    #(DATA_WIDTH::type_id::create("drv", this));
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


// ========================================================================
// 7. SCOREBOARD COMPONENT (uvm_score_board + uvm_tlm_analysis_fifo)
// ========================================================================
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


// ========================================================================
// 8 . ENVIRONMENT CONTAINER (uvm_env)
// ========================================================================
class axis_env #(parameter int DATA_WIDTH = 32) extends uv,_env;
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

// ========================================================================
// 9 . BASE_TEST (uvm_test)
// ========================================================================
class axis_base_test extends uvm_test;
    axis_env #(32) env;

    function new (string new = "axis_base_test", uvm_component parent = null);
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
        #100;
        `uvm_info("TEST_RUN", "Completing AXI-Stream Base Test Run Phase", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// ========================================================================
// 10. TOP TESTBENCH MODULE (Static Domain)
// ========================================================================
module top_axis_tb_skeleton;
    logic clk;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Initiate Physical Interface
    axis_if #(32) intf(clk);

    // Tie off DUT signals for skeleton simulation
    initial begin
        intf.reset_n = 0;
        intf.ready = 1'b1;
        #20 intf.reset_n = 1;
    end

    initial begin
        // Store physical interface handle in uvm_config_db
        uvm_config_db #(virtual axis_if #(32))::set(null, "*", "vif", intf);

        `uvm_info("TOP_TB", "Starting UVM Structural Skeleton Simulation", UVM_LOW)
        run_test("axis_base_test");
    end
endmodule



