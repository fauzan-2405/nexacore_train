// ============================================================================
// File: axis_self_checking_tb.sv
// Description: Month 2, Week 7 Self-Checking UVM Testbench & Dual TLM Scoreboard
// Objectives: Dual-Interface Passive Monitoring (s_axis & m_axis),
//             TLM Analysis Port Interconnects, End-to-End Golden FIFO Scoreboard,
//             Self-Checking Verification with Match/Mismatch Reporting.
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
    soft burst_len inside {[1:8]};
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
    soft packet_delay inside {[0:3]};
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
    s = $sformatf("Len=%0d | Payload=[", burst_len);
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
      start_item(req);

      if (!req.randomize() with {
        burst_len    inside {[2:6]};
        packet_delay inside {[1:2]};
      }) begin
        `uvm_fatal("SEQ_RAND_ERR", "Sequence item randomization failed!")
      end

      `uvm_info("SEQ_SEND", $sformatf("Packet #%0d Generated: %s", i+1, req.convert2string()), UVM_HIGH)
      finish_item(req);
    end

    `uvm_info("SEQ", "Random Burst Sequence Completed.", UVM_LOW)
  endtask
endclass


// ============================================================================
// 3. PHYSICAL DUAL-INTERFACE (s_axis & m_axis)
// ============================================================================
interface axis_if (input logic clk, input logic rst_n);
  // Slave Write Interface (Inputs to FIFO)
  logic        s_tvalid;
  logic        s_tready;
  logic [31:0] s_tdata;
  logic [3:0]  s_tkeep;
  logic        s_tlast;

  // Master Read Interface (Outputs from FIFO)
  logic        m_tvalid;
  logic        m_tready;
  logic [31:0] m_tdata;
  logic [3:0]  m_tkeep;
  logic        m_tlast;

  // Driver Clocking Block (Synchronous input driving & output ready control)
  clocking cb_drv @(posedge clk);
    default input #1ns output #1ns;
    output s_tvalid, s_tdata, s_tkeep, s_tlast;
    input  s_tready;
    output m_tready;
    input  m_tvalid;
  endclocking

  // Monitor Clocking Block (Synchronous passive sampling of both interfaces)
  clocking cb_mon @(posedge clk);
    default input #1ns output #1ns;
    input s_tvalid, s_tready, s_tdata, s_tkeep, s_tlast;
    input m_tvalid, m_tready, m_tdata, m_tkeep, m_tlast;
  endclocking

  modport DRV (clocking cb_drv, input rst_n);
  modport MON (clocking cb_mon, input rst_n);
endinterface


// ============================================================================
// 4. HARDWARE DUT (AXI4-Stream Asynchronous FIFO Functional Model)
// ============================================================================
module axis_wrapper #(
  parameter int DATA_WIDTH = 32
) (
  input  logic                  aclk,
  input  logic                  aresetn,

  // Slave Input Port
  input  logic                  s_axis_tvalid,
  output logic                  s_axis_tready,
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic [3:0]            s_axis_tkeep,
  input  logic                  s_axis_tlast,

  // Master Output Port
  output logic                  m_axis_tvalid,
  input  logic                  m_axis_tready,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [3:0]            m_axis_tkeep,
  output logic                  m_axis_tlast
);

  // Internal FIFO Queue for functional transfer
  typedef struct {
    logic [DATA_WIDTH-1:0] data;
    logic [3:0]            keep;
    logic                  last;
  } fifo_entry_t;

  fifo_entry_t fifo_q[$];
  localparam int FIFO_DEPTH = 16;

  assign s_axis_tready = (fifo_q.size() < FIFO_DEPTH);
  assign m_axis_tvalid = (fifo_q.size() > 0);

  assign m_axis_tdata = (fifo_q.size() > 0) ? fifo_q[0].data : '0;
  assign m_axis_tkeep = (fifo_q.size() > 0) ? fifo_q[0].keep : '0;
  assign m_axis_tlast = (fifo_q.size() > 0) ? fifo_q[0].last : 1'b0;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      fifo_q.delete();
    end else begin
      // Push into FIFO on Slave Write Handshake
      if (s_axis_tvalid && s_axis_tready) begin
        fifo_entry_t entry;
        entry.data = s_axis_tdata;
        entry.keep = s_axis_tkeep;
        entry.last = s_axis_tlast;
        fifo_q.push_back(entry);
      end

      // Pop from FIFO on Master Read Handshake
      if (m_axis_tvalid && m_axis_tready) begin
        if (fifo_q.size() > 0) begin
          void'(fifo_q.pop_front());
        end
      end
    end
  end
endmodule


// ============================================================================
// 5. VERIFICATION COMPONENTS
// ============================================================================

// --- SLAVE INPUT DRIVER (s_axis) ---
class axis_s_driver extends uvm_driver #(axis_seq_item);
  virtual axis_if vif;

  `uvm_component_utils(axis_s_driver)

  function new(string name = "axis_s_driver", uvm_component parent = null);
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

    vif.cb_drv.s_tvalid <= 1'b0;
    vif.cb_drv.s_tdata  <= '0;
    vif.cb_drv.s_tkeep  <= '0;
    vif.cb_drv.s_tlast  <= 1'b0;

    forever begin
      seq_item_port.get_next_item(req);

      foreach (req.data[i]) begin
        @(vif.cb_drv);
        vif.cb_drv.s_tvalid <= 1'b1;
        vif.cb_drv.s_tdata  <= req.data[i];
        vif.cb_drv.s_tkeep  <= req.keep[i];
        vif.cb_drv.s_tlast  <= (i == req.burst_len - 1) ? 1'b1 : 1'b0;

        do begin
          @(vif.cb_drv);
        end while (!vif.cb_drv.s_tready);
      end

      vif.cb_drv.s_tvalid <= 1'b0;
      vif.cb_drv.s_tlast  <= 1'b0;

      if (req.packet_delay > 0) begin
        repeat (req.packet_delay) @(vif.cb_drv);
      end

      seq_item_port.item_done();
    end
  endtask
endclass


// --- MASTER READ BACKPRESSURE DRIVER (m_axis) ---
class axis_m_driver extends uvm_component;
  virtual axis_if vif;

  `uvm_component_utils(axis_m_driver)

  function new(string name = "axis_m_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NO_VIF", {"Virtual interface not found for ", get_full_name()});
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.cb_drv.m_tready <= 1'b1; // Default: Always ready to drain FIFO

    forever begin
      @(vif.cb_drv);
      // Continuous readiness (can be randomized for backpressure testing)
      vif.cb_drv.m_tready <= 1'b1;
    end
  endtask
endclass


// --- SLAVE INPUT MONITOR (s_axis) ---
class axis_s_monitor extends uvm_monitor;
  virtual axis_if vif;
  uvm_analysis_port #(axis_seq_item) ap;

  `uvm_component_utils(axis_s_monitor)

  function new(string name = "axis_s_monitor", uvm_component parent = null);
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
        data_q.push_back(vif.cb_mon.s_tdata);
        keep_q.push_back(vif.cb_mon.s_tkeep);

        if (vif.cb_mon.s_tlast) begin
          item           = axis_seq_item::type_id::create("s_mon_item");
          item.burst_len = data_q.size();
          item.data      = new[data_q.size()];
          item.keep      = new[keep_q.size()];

          foreach (data_q[i]) item.data[i] = data_q[i];
          foreach (keep_q[i]) item.keep[i] = keep_q[i];

          data_q.delete();
          keep_q.delete();

          `uvm_info("S_MON", $sformatf("Captured Input Frame: %s", item.convert2string()), UVM_HIGH)
          ap.write(item);
        end
      end
    end
  endtask
endclass


// --- MASTER OUTPUT MONITOR (m_axis) ---
class axis_m_monitor extends uvm_monitor;
  virtual axis_if vif;
  uvm_analysis_port #(axis_seq_item) ap;

  `uvm_component_utils(axis_m_monitor)

  function new(string name = "axis_m_monitor", uvm_component parent = null);
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
      if (vif.cb_mon.m_tvalid && vif.cb_mon.m_tready) begin
        data_q.push_back(vif.cb_mon.m_tdata);
        keep_q.push_back(vif.cb_mon.m_tkeep);

        if (vif.cb_mon.m_tlast) begin
          item           = axis_seq_item::type_id::create("m_mon_item");
          item.burst_len = data_q.size();
          item.data      = new[data_q.size()];
          item.keep      = new[keep_q.size()];

          foreach (data_q[i]) item.data[i] = data_q[i];
          foreach (keep_q[i]) item.keep[i] = keep_q[i];

          data_q.delete();
          keep_q.delete();

          `uvm_info("M_MON", $sformatf("Captured Output Frame: %s", item.convert2string()), UVM_HIGH)
          ap.write(item);
        end
      end
    end
  endtask
endclass


// --- SEQUENCER ---
typedef uvm_sequencer #(axis_seq_item) axis_sequencer;


// --- END-TO-END SELF-CHECKING SCOREBOARD ---
class axis_scoreboard extends uvm_scoreboard;
  uvm_tlm_analysis_fifo #(axis_seq_item) in_tlm_fifo;
  uvm_tlm_analysis_fifo #(axis_seq_item) out_tlm_fifo;

  axis_seq_item exp_q[$];

  int match_count    = 0;
  int mismatch_count = 0;

  `uvm_component_utils(axis_scoreboard)

  function new(string name = "axis_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    in_tlm_fifo  = new("in_tlm_fifo", this);
    out_tlm_fifo = new("out_tlm_fifo", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_seq_item exp_item;
    axis_seq_item act_item;

    fork
      // Thread 1: Process incoming expected transactions
      forever begin
        in_tlm_fifo.get(exp_item);
        exp_q.push_back(exp_item);
        `uvm_info("SCB_IN", $sformatf("Queued Expected Packet into Golden FIFO (Queue Size=%0d)", exp_q.size()), UVM_MEDIUM)
      end

      // Thread 2: Process outgoing actual transactions & check equality
      forever begin
        out_tlm_fifo.get(act_item);

        if (exp_q.size() == 0) begin
          `uvm_error("SCB_UNDERFLOW", "DUT produced output frame, but Expected Golden FIFO is empty!")
          mismatch_count++;
        end else begin
          exp_item = exp_q.pop_front();

          if (exp_item.compare(act_item)) begin
            `uvm_info("SCB_MATCH", $sformatf("MATCH! Frame Verified: %s", act_item.convert2string()), UVM_LOW)
            match_count++;
          end else begin
            `uvm_error("SCB_MISMATCH", $sformatf("MISMATCH DETECTED!\n Expected: %s\n Actual:   %s",
                                       exp_item.convert2string(), act_item.convert2string()))
            mismatch_count++;
          end
        end
      end
    join_none
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", "==================================================", UVM_LOW)
    `uvm_info("SCB_SUMMARY", $sformatf(" SCOREBOARD SUMMARY REPORT:"), UVM_LOW)
    `uvm_info("SCB_SUMMARY", $sformatf(" - Total Packets Matched : %0d", match_count), UVM_LOW)
    `uvm_info("SCB_SUMMARY", $sformatf(" - Total Mismatches      : %0d", mismatch_count), UVM_LOW)
    `uvm_info("SCB_SUMMARY", $sformatf(" - Pending Packets in FIFO: %0d", exp_q.size()), UVM_LOW)
    `uvm_info("SCB_SUMMARY", "==================================================", UVM_LOW)

    if (mismatch_count == 0 && exp_q.size() == 0 && match_count > 0) begin
      `uvm_info("SCB_PASSED", "STATUS: VERIFICATION PASSED (100% Data Integrity Verified)", UVM_LOW)
    end else begin
      `uvm_error("SCB_FAILED", "STATUS: VERIFICATION FAILED (Errors detected or unread packets remain)")
    end
  endfunction
endclass


// --- SLAVE INPUT AGENT ---
class axis_s_agent extends uvm_agent;
  axis_sequencer seqr;
  axis_s_driver  drv;
  axis_s_monitor mon;

  `uvm_component_utils(axis_s_agent)

  function new(string name = "axis_s_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axis_s_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      seqr = axis_sequencer::type_id::create("seqr", this);
      drv  = axis_s_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction
endclass


// --- MASTER OUTPUT AGENT ---
class axis_m_agent extends uvm_agent;
  axis_m_driver  drv;
  axis_m_monitor mon;

  `uvm_component_utils(axis_m_agent)

  function new(string name = "axis_m_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axis_m_monitor::type_id::create("mon", this);
    drv = axis_m_driver::type_id::create("drv", this);
  endfunction
endclass


// --- ENVIRONMENT CONTAINER ---
class axis_env extends uvm_env;
  axis_s_agent    s_agent;
  axis_m_agent    m_agent;
  axis_scoreboard scb;

  `uvm_component_utils(axis_env)

  function new(string name = "axis_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    s_agent = axis_s_agent::type_id::create("s_agent", this);
    m_agent = axis_m_agent::type_id::create("m_agent", this);
    scb     = axis_scoreboard::type_id::create("scb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Wire Input Monitor -> Scoreboard Input TLM FIFO
    s_agent.mon.ap.connect(scb.in_tlm_fifo.analysis_export);

    // Wire Output Monitor -> Scoreboard Output TLM FIFO
    m_agent.mon.ap.connect(scb.out_tlm_fifo.analysis_export);
  endfunction
endclass


// ============================================================================
// 6. SELF-CHECKING UVM TEST
// ============================================================================
class axis_self_checking_test extends uvm_test;
  axis_env env;

  `uvm_component_utils(axis_self_checking_test)

  function new(string name = "axis_self_checking_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axis_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_random_burst_seq seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "Starting Self-Checking End-to-End Verification Test...", UVM_LOW)

    seq = axis_random_burst_seq::type_id::create("seq");
    seq.num_packets = 10;
    seq.start(env.s_agent.seqr);

    #100; // Allow final FIFO drain cycles before completing
    `uvm_info("TEST", "Active Stimulus Generation Finished. Finishing Test...", UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass


// ============================================================================
// 7. TOP TESTBENCH MODULE
// ============================================================================
module top_tb;
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

  axis_if intf(clk, rst_n);

  axis_wrapper #(
    .DATA_WIDTH(32)
  ) dut (
    .aclk          (clk),
    .aresetn       (rst_n),

    // Slave Write Interface
    .s_axis_tvalid (intf.s_tvalid),
    .s_axis_tready (intf.s_tready),
    .s_axis_tdata  (intf.s_tdata),
    .s_axis_tkeep  (intf.s_tkeep),
    .s_axis_tlast  (intf.s_tlast),

    // Master Read Interface
    .m_axis_tvalid (intf.m_tvalid),
    .m_axis_tready (intf.m_tready),
    .m_axis_tdata  (intf.m_tdata),
    .m_axis_tkeep  (intf.m_tkeep),
    .m_axis_tlast  (intf.m_tlast)
  );

  initial begin
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top*", "vif", intf);
    run_test("axis_self_checking_test");
  end
endmodule
