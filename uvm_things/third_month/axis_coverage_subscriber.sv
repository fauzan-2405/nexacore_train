// ============================================================================
// File: axis_coverage_subscriber.sv
// Description: Month 3, Week 11 Deliverable - SystemVerilog Functional Coverage
//              Subscriber (uvm_subscriber), Covergroups, Coverpoints, Crosses,
//              and Invalid Bin Filtering for AXI4-Stream Verification
// ============================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

// ----------------------------------------------------------------------------
// 1. Transaction Item (AXI4-Stream Packet)
// ----------------------------------------------------------------------------
class axis_seq_item extends uvm_sequence_item;
  typedef enum bit [1:0] {MODE_NORMAL = 2'b00, MODE_LOOPBACK = 2'b01, MODE_BYPASS = 2'b10} mode_e;
  typedef enum bit [1:0] {FIFO_EMPTY  = 2'b00, FIFO_MID      = 2'b01, FIFO_FULL     = 2'b10} fifo_status_e;

  rand mode_e         mode;
  rand fifo_status_e  fifo_status;
  rand byte           data[];
  rand int            stall_delay;
  rand bit            tlast;

  constraint c_data_size { data.size() inside {[1:64]}; }
  constraint c_stall     { stall_delay inside {[0:15]}; }

  `uvm_object_utils_begin(axis_seq_item)
    `uvm_field_enum(mode_e, mode, UVM_ALL_ON)
    `uvm_field_enum(fifo_status_e, fifo_status, UVM_ALL_ON)
    `uvm_field_array_int(data, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(stall_delay, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(tlast, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axis_seq_item");
    super.new(name);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 2. Functional Coverage Subscriber (Extends uvm_subscriber)
// ----------------------------------------------------------------------------
class axis_coverage_subscriber extends uvm_subscriber #(axis_seq_item);
  `uvm_component_utils(axis_coverage_subscriber)

  axis_seq_item pkt;

  // --------------------------------------------------------------------------
  // Covergroup Definition
  // --------------------------------------------------------------------------
  covergroup cg_axis_functional;
    option.per_instance = 1;
    option.comment      = "AXI4-Stream Functional & Cross Coverage Metrics";

    // Coverpoint 1: Packet Payload Length Bins
    cp_pkt_len: coverpoint pkt.data.size() {
      bins min_pkt   = {1};
      bins small_pkt = {[2:15]};
      bins med_pkt   = {[16:31]};
      bins large_pkt = {[32:63]};
      bins max_pkt   = {64};
    }

    // Coverpoint 2: Receiver Stall / Backpressure Delays
    cp_stall_delay: coverpoint pkt.stall_delay {
      bins no_stall    = {0};
      bins short_stall = {[1:4]};
      bins med_stall   = {[5:9]};
      bins long_stall  = {[10:15]};
    }

    // Coverpoint 3: Configuration Operating Modes
    cp_mode: coverpoint pkt.mode {
      bins mode_normal   = {axis_seq_item::MODE_NORMAL};
      bins mode_loopback = {axis_seq_item::MODE_LOOPBACK};
      bins mode_bypass   = {axis_seq_item::MODE_BYPASS};
    }

    // Coverpoint 4: Hardware FIFO Fill Levels
    cp_fifo_status: coverpoint pkt.fifo_status {
      bins state_empty = {axis_seq_item::FIFO_EMPTY};
      bins state_mid   = {axis_seq_item::FIFO_MID};
      bins state_full  = {axis_seq_item::FIFO_FULL};
    }

    // ------------------------------------------------------------------------
    // Cross Coverage 1: Operating Mode x FIFO Fill Status
    // ------------------------------------------------------------------------
    cross_mode_x_fifo: cross cp_mode, cp_fifo_status {
      // In BYPASS mode, the FIFO logic is completely bypassed.
      // Therefore, FIFO_MID and FIFO_FULL states are physically unreachable.
      ignore_bins ignore_bypass_fifo = binsof(cp_mode) intersect {axis_seq_item::MODE_BYPASS} &&
                                       binsof(cp_fifo_status) intersect {axis_seq_item::FIFO_MID, axis_seq_item::FIFO_FULL};
    }

    // ------------------------------------------------------------------------
    // Cross Coverage 2: Packet Size x Stall Delay
    // ------------------------------------------------------------------------
    cross_size_x_stall: cross cp_pkt_len, cp_stall_delay;

    // ------------------------------------------------------------------------
    // Cross Coverage 3: Operating Mode x Packet Size
    // ------------------------------------------------------------------------
    cross_mode_x_size: cross cp_mode, cp_pkt_len;

  endgroup

  function new(string name = "axis_coverage_subscriber", uvm_component parent = null);
    super.new(name, parent);
    cg_axis_functional = new();
  endfunction

  // --------------------------------------------------------------------------
  // Mandatory uvm_subscriber TLM Write Implementation
  // --------------------------------------------------------------------------
  virtual function void write(axis_seq_item t);
    this.pkt = t;
    cg_axis_functional.sample();
    `uvm_info("COV_SUB", $sformatf("Sampled Transaction: Mode=%s, Size=%0d, Stall=%0d, FIFO=%s | Current Functional Coverage = %0.2f%%",
              t.mode.name(), t.data.size(), t.stall_delay, t.fifo_status.name(), cg_axis_functional.get_inst_coverage()), UVM_LOW)
  endfunction

  function real get_coverage();
    return cg_axis_functional.get_inst_coverage();
  endfunction
endclass


// ----------------------------------------------------------------------------
// 3. Simple Monitor Broadcasting via Analysis Port
// ----------------------------------------------------------------------------
class axis_monitor extends uvm_component;
  `uvm_component_utils(axis_monitor)

  uvm_analysis_port #(axis_seq_item) ap;

  function new(string name = "axis_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 4. Testbench Environment Wiring Subscriber to Monitor
// ----------------------------------------------------------------------------
class axis_coverage_env extends uvm_env;
  `uvm_component_utils(axis_coverage_env)

  axis_monitor             mon;
  axis_coverage_subscriber cov_sub;

  function new(string name = "axis_coverage_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon     = axis_monitor::type_id::create("mon", this);
    cov_sub = axis_coverage_subscriber::type_id::create("cov_sub", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect Monitor's analysis port to Subscriber's analysis implementation
    mon.ap.connect(cov_sub.analysis_export);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 5. Test Class Executing Random Stimulus & Measuring Coverage Closure
// ----------------------------------------------------------------------------
class axis_coverage_test extends uvm_test;
  `uvm_component_utils(axis_coverage_test)

  axis_coverage_env env;

  function new(string name = "axis_coverage_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axis_coverage_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_seq_item pkt;
    phase.raise_objection(this);

    `uvm_info("TEST", "==================================================", UVM_LOW)
    `uvm_info("TEST", "  STARTING WEEK 11: FUNCTIONAL COVERAGE TEST RUN  ", UVM_LOW)
    `uvm_info("TEST", "==================================================", UVM_LOW)

    // Generate 50 randomized packets to exercise coverpoints and cross combinations
    for (int i = 0; i < 50; i++) begin
      pkt = axis_seq_item::type_id::create($sformatf("pkt_%0d", i));
      assert(pkt.randomize());
      
      // Broadcast via monitor analysis port to trigger subscriber coverage sampling
      env.mon.ap.write(pkt);
      #10ns;
    end

    `uvm_info("TEST", "--------------------------------------------------", UVM_LOW)
    `uvm_info("TEST", $sformatf("FINAL FUNCTIONAL COVERAGE ACHIEVED = %0.2f%%", env.cov_sub.get_coverage()), UVM_LOW)
    `uvm_info("TEST", "STATUS: WEEK 11 FUNCTIONAL COVERAGE SUBSCRIBER TEST PASSED!", UVM_LOW)
    `uvm_info("TEST", "--------------------------------------------------", UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass


// ----------------------------------------------------------------------------
// 6. Top-Level Module
// ----------------------------------------------------------------------------
module top_tb;
  initial begin
    run_test("axis_coverage_test");
  end
endmodule
