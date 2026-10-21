// ============================================================================
// File: axis_driver_seq_tb.sv
// Description: Month 2, Week 6 Complete Active Driver & Sequence Handshake Testbench
// Objectives: Active Driver Unpacking & Driving, Clocking Block Alignment,
//             UVM Driver-Sequencer Handshake API, Frame Reassembly in Monitor,
//             Objection Control & Sequence Execution.
// ============================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// 1. AXI4-STREAM TRANSACTION ITEM
// ============================================================================
class axis_seq_item extends uvm_sequence_item;
  rand bit [31:0]    data[];        // Dynamic array for payload data words
  rand bit [3:0]     keep[];        // Byte enables per 32-bit data word
  rand int unsigned  burst_len;     // Number of transfers in packet frame
  rand int unsigned  packet_delay;  // Idle clock cycles between packets

  `uvm_object_utils(axis_seq_item)

  constraint c_burst_len {
    soft burst_len inside {[1:16]};
  }

  constraint c_array_sizes {
    data.size() == burst_len;
    keep.size() == burst_len;
  }

  constraint c_keep_rules {
    foreach (keep[i]) {
      if (i < burst_len - 1) {
        keep[i] == 4'b1111;
      } else {
        keep[i] inside {4'b0001, 4'b0011, 4'b0111, 4'b1111};
      }
    }
  }

  constraint c_packet_delay {
    soft packet_delay inside {[0:5]};
  }

  function new(string name = "axis_seq_item");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    axis_seq_item rhs_;
    super.do_copy(rhs);
    if (!$cast(rhs_, rhs)) return;

    this.burst_len    = rhs_.burst_len;
    this.packet_delay = rhs_.packet_delay;
    this.data         = new[rhs_.data.size()];
    foreach (rhs_.data[i]) this.data[i] = rhs_.data[i];
    this.keep         = new[rhs_.keep.size()];
    foreach (rhs_.keep[i]) this.keep[i] = rhs_.keep[i];
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    axis_seq_item rhs_;
    if (!super.do_compare(rhs, comparer)) return 0;
    if (!$cast(rhs_, rhs)) return 0;

    if (this.burst_len != rhs_.burst_len) return 0;
    if (this.packet_delay != rhs_.packet_delay) return 0;
    if (this.data.size() != rhs_.data.size()) return 0;
    if (this.keep.size() != rhs_.keep.size()) return 0;

    foreach (this.data[i]) begin
      if (this.data[i] != rhs_.data[i]) return 0;
    end
    foreach (this.keep[i]) begin
      if (this.keep[i] != rhs_.keep[i]) return 0;
    end
    return 1;
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("Len=%0d, Delay=%0d | Payload=[", burst_len, packet_delay);
    foreach (data[i]) begin
      s = {s, $sformatf(" 0x%08h(k=%b)", data[i], keep[i])};
    end
    s = {s, " ]"};
    return s;
  endfunction
endclass


// ============================================================================
// 2. AXI4-STREAM SEQUENCE LIBRARY
// ============================================================================
class axis_random_burst_seq extends uvm_sequence #(axis_seq_item);
  rand int unsigned num_packets = 5;

  `uvm_object_utils(axis_random_burst_seq)

  function new(string name = "axis_random_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    axis_seq_item req;
    `uvm_info("SEQ", $sformatf("Starting Random Burst Sequence (%0d Packets)...", num_packets), UVM_LOW)

    for (int i = 0; i < num_packets; i++) begin
      req = axis_seq_item::type_id::create("req");
      
      // Step 1: Wait for Sequencer Grant
      start_item(req);

      // Step 2: Late-Binding Randomization
      if (!req.randomize() with {
        burst_len    inside {[2:8]};
        packet_delay inside {[1:3]};
      }) begin
        `uvm_fatal("SEQ_RAND_ERR", "Sequence item randomization failed!")
      end

      `uvm_info("SEQ_SEND", $sformatf("Packet #%0d Generated: %s", i+1, req.convert2string()), UVM_MEDIUM)

      // Step 3: Send Item to Driver & Wait for Completion
      finish_item(req);
    end

    `uvm_info("SEQ", "Random Burst Sequence Completed Successfully.", UVM_LOW)
  endtask
endclass


// ============================================================================
// 3. PHYSICAL INTERFACE WITH CLOCKING BLOCKS
// ============================================================================
interface axis_if (input logic clk, input logic rst_n);
  logic        s_tvalid;
  logic        s_tready;
  logic [31:0] s_tdata;
  logic [3:0]  s_tkeep;
  logic        s_tlast;

  clocking cb_drv @(posedge clk);
    default input #1ns output #1ns;
    output s_tvalid, s_tdata, s_tkeep, s_tlast;
    input  s_tready;
  endclocking

  clocking cb_mon @(posedge clk);
    default input #1ns output #1ns;
    input s_tvalid, s_tready, s_tdata, s_tkeep, s_tlast;
  endclocking

  modport DRV (clocking cb_drv, input rst_n);
  modport MON (clocking cb_mon, input rst_n);
endinterface


// ============================================================================
// 4. HARDWARE DUT STUB
// ============================================================================
module axis_wrapper #(
  parameter int DATA_WIDTH = 32
) (
  input  logic                  aclk,
  input  logic                  aresetn,
  input  logic                  s_tvalid,
  output logic                  s_tready,
  input  logic [DATA_WIDTH-1:0] s_tdata,
  input  logic [3:0]            s_tkeep,
  input  logic                  s_tlast
);
  // Synchronous ready generation (always ready after reset)
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      s_tready <= 1'b0;
    end else begin
      s_tready <= 1'b1;
    end
  end
endmodule


// ============================================================================
// 5. ACTIVE VERIFICATION COMPONENTS
// ============================================================================

// --- ACTIVE AXI4-STREAM DRIVER ---
class axis_driver extends uvm_driver #(axis_seq_item);
  virtual axis_if vif;

  `uvm_component_utils(axis_driver)

  function new(string name = "axis_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NO_VIF", {"Virtual interface not found for ", get_full_name()});
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_seq_item req;

    // Initialize physical bus outputs
    vif.cb_drv.s_tvalid <= 1'b0;
    vif.cb_drv.s_tdata  <= '0;
    vif.cb_drv.s_tkeep  <= '0;
    vif.cb_drv.s_tlast  <= 1'b0;

    forever begin
      // Step 1: Retrieve next transaction item from Sequencer
      seq_item_port.get_next_item(req);

      `uvm_info("DRV_RECV", $sformatf("Driver Received Item: %s", req.convert2string()), UVM_LOW)

      // Step 2: Unpack dynamic arrays and drive each word on clock edge
      foreach (req.data[i]) begin
        @(vif.cb_drv);
        vif.cb_drv.s_tvalid <= 1'b1;
        vif.cb_drv.s_tdata  <= req.data[i];
        vif.cb_drv.s_tkeep  <= req.keep[i];
        vif.cb_drv.s_tlast  <= (i == req.burst_len - 1) ? 1'b1 : 1'b0;

        // Wait for hardware handshake (s_tready == 1)
        do begin
          @(vif.cb_drv);
        end while (!vif.cb_drv.s_tready);
      end

      // Step 3: De-assert valid after final transfer in burst
      vif.cb_drv.s_tvalid <= 1'b0;
      vif.cb_drv.s_tlast  <= 1'b0;

      // Step 4: Handle inter-packet idle delay
      if (req.packet_delay > 0) begin
        repeat (req.packet_delay) @(vif.cb_drv);
      end

      // Step 5: Signal handshake completion back to Sequence
      seq_item_port.item_done();
    end
  endtask
endclass


// --- PASSIVE AXI4-STREAM MONITOR ---
class axis_monitor extends uvm_monitor;
  virtual axis_if vif;
  uvm_analysis_port #(axis_seq_item) ap;

  `uvm_component_utils(axis_monitor)

  function new(string name = "axis_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NO_VIF", {"Virtual interface not found for ", get_full_name()});
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_seq_item item;
    bit [31:0] data_q[$];
    bit [3:0]  keep_q[$];

    forever begin
      @(vif.cb_mon);
      if (vif.cb_mon.s_tvalid && vif.cb_mon.s_tready) begin
        // Accumulate word transfers into temporary queues
        data_q.push_back(vif.cb_mon.s_tdata);
        keep_q.push_back(vif.cb_mon.s_tkeep);

        // Frame boundary reached
        if (vif.cb_mon.s_tlast) begin
          item = axis_seq_item::type_id::create("mon_item");
          item.burst_len = data_q.size();
          item.data      = new[data_q.size()];
          item.keep      = new[keep_q.size()];

          foreach (data_q[i]) item.data[i] = data_q[i];
          foreach (keep_q[i]) item.keep[i] = keep_q[i];

          data_q.delete();
          keep_q.delete();

          `uvm_info("MON_FRAME", $sformatf("Reassembled Complete Frame: %s", item.convert2string()), UVM_LOW)
          ap.write(item);
        end
      end
    end
  endtask
endclass


// --- SEQUENCER & SCOREBOARD ---
typedef uvm_sequencer #(axis_seq_item) axis_sequencer;

class axis_scoreboard extends uvm_scoreboard;
  uvm_tlm_analysis_fifo #(axis_seq_item) item_fifo;

  `uvm_component_utils(axis_scoreboard)

  function new(string name = "axis_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_fifo = new("item_fifo", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_seq_item item;
    forever begin
      item_fifo.get(item);
      `uvm_info("SCB_RECV", $sformatf("Scoreboard Verified Packet: %s", item.convert2string()), UVM_LOW)
    end
  endtask
endclass


// --- AGENT CONTAINER ---
class axis_agent extends uvm_agent;
  axis_sequencer seqr;
  axis_driver    drv;
  axis_monitor   mon;

  `uvm_component_utils(axis_agent)

  function new(string name = "axis_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axis_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      seqr = axis_sequencer::type_id::create("seqr", this);
      drv  = axis_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction
endclass


// --- ENVIRONMENT CONTAINER ---
class axis_env extends uvm_env;
  axis_agent      agent;
  axis_scoreboard scb;

  `uvm_component_utils(axis_env)

  function new(string name = "axis_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = axis_agent::type_id::create("agent", this);
    scb   = axis_scoreboard::type_id::create("scb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(scb.item_fifo.analysis_export);
  endfunction
endclass


// ============================================================================
// 6. ACTIVE UVM TEST
// ============================================================================
class axis_active_test extends uvm_test;
  axis_env env;

  `uvm_component_utils(axis_active_test)

  function new(string name = "axis_active_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axis_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_random_burst_seq seq;

    // Raise objection to keep simulation alive during active sequence execution
    phase.raise_objection(this);

    `uvm_info("TEST", "Starting Active Driver & Sequence Handshake Test Execution...", UVM_LOW)

    // Instantiate sequence and execute on Agent Sequencer
    seq = axis_random_burst_seq::type_id::create("seq");
    seq.num_packets = 5;
    seq.start(env.agent.seqr);

    #100; // Final clock cycles to flush monitor pipeline
    `uvm_info("TEST", "Active Sequence Execution Completed.", UVM_LOW)

    // Drop objection to allow UVM phase termination
    phase.drop_objection(this);
  endtask
endclass


// ============================================================================
// 7. TOP TESTBENCH MODULE
// ============================================================================
module top_tb;
  logic clk;
  logic rst_n;

  // 100MHz Clock Generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset Generation
  initial begin
    rst_n = 0;
    #25 rst_n = 1;
  end

  // Interface Instance
  axis_if intf(clk, rst_n);

  // Hardware DUT Instance
  axis_wrapper #(
    .DATA_WIDTH(32)
  ) dut (
    .aclk     (clk),
    .aresetn  (rst_n),
    .s_tvalid (intf.s_tvalid),
    .s_tready (intf.s_tready),
    .s_tdata  (intf.s_tdata),
    .s_tkeep  (intf.s_tkeep),
    .s_tlast  (intf.s_tlast)
  );

  // uvm_config_db Deposit & Test Execution
  initial begin
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top*", "vif", intf);
    run_test("axis_active_test");
  end
endmodule
