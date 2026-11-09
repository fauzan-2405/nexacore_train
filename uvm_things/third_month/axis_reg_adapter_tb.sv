// ============================================================================
// File: axis_reg_adapter_tb.sv
// Description: Month 3, Week 10 Deliverable - UVM Register Adapter (uvm_reg_adapter)
//              & Frontdoor vs. Backdoor Access Verification Environment
// ============================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

// ----------------------------------------------------------------------------
// 1. Physical Bus Sequence Item (AXI-Lite Style)
// ----------------------------------------------------------------------------
class axi_lite_seq_item extends uvm_sequence_item;
  typedef enum {AXI_READ, AXI_WRITE} axi_op_e;

  rand axi_op_e       op;
  rand bit [31:0]     addr;
  rand bit [31:0]     data;
  rand bit [3:0]      strb;
  bit [1:0]           resp; // 2'b00 = OKAY

  `uvm_object_utils_begin(axi_lite_seq_item)
    `uvm_field_enum(axi_op_e, op, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(strb, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(resp, UVM_ALL_ON | UVM_HEX)
  `uvm_object_utils_end

  function new(string name = "axi_lite_seq_item");
    super.new(name);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 2. Physical AXI-Lite Interface & Dummy DUT Module with HDL Backdoor Path
// ----------------------------------------------------------------------------
interface axi_lite_if(input logic clk, input logic rst_n);
  logic        pwrite;
  logic        penable;
  logic        psel;
  logic [31:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;

  clocking cb_drv @(posedge clk);
    default input #1ns output #1ns;
    output pwrite, penable, psel, paddr, pwdata;
    input  prdata, pready;
  endclocking

  clocking cb_mon @(posedge clk);
    default input #1ns output #1ns;
    input pwrite, penable, psel, paddr, pwdata, prdata, pready;
  endclocking
endinterface


// Dummy DUT holding internal register flip-flops accessible via HDL path
module dut_wrapper(
  input logic clk,
  input logic rst_n,
  axi_lite_if vif
);
  // Internal Register Flip-Flops (HDL Backdoor Path targets)
  (* keep = "true" *) logic [31:0] ctrl_reg_ff;    
  (* keep = "true" *) logic [31:0] status_reg_ff;

  // Simple APB/AXI-Lite register decoder logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_reg_ff   <= 32'h0000_0000;
      status_reg_ff <= 32'h0000_0002; // Default empty
      vif.pready    <= 1'b0;
      vif.prdata    <= 32'h0;
    end else begin
      if (vif.psel && vif.penable) begin
        vif.pready <= 1'b1;
        if (vif.pwrite) begin
          case (vif.paddr)
            32'h00: ctrl_reg_ff   <= vif.pwdata;
            32'h04: status_reg_ff <= vif.pwdata;
          endcase
        end else begin
          case (vif.paddr)
            32'h00: vif.prdata <= ctrl_reg_ff;
            32'h04: vif.prdata <= status_reg_ff;
            default: vif.prdata <= 32'hDEAD_BEEF;
          endcase
        end
      end else begin
        vif.pready <= 1'b0;
      end
    end
  end
endmodule


// ----------------------------------------------------------------------------
// 3. Physical AXI-Lite Driver & Sequencer
// ----------------------------------------------------------------------------
typedef uvm_sequencer #(axi_lite_seq_item) axi_lite_sequencer;

class axi_lite_driver extends uvm_driver #(axi_lite_seq_item);
  virtual axi_lite_if vif;

  `uvm_component_utils(axi_lite_driver)

  function new(string name = "axi_lite_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NO_VIF", "Virtual interface not found for axi_lite_driver")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_lite_seq_item req;
    vif.cb_drv.psel    <= 1'b0;
    vif.cb_drv.penable <= 1'b0;

    forever begin
      seq_item_port.get_next_item(req);

      @(vif.cb_drv);
      vif.cb_drv.psel   <= 1'b1;
      vif.cb_drv.pwrite <= (req.op == axi_lite_seq_item::AXI_WRITE);
      vif.cb_drv.paddr  <= req.addr;
      vif.cb_drv.pwdata <= req.data;

      @(vif.cb_drv);
      vif.cb_drv.penable <= 1'b1;

      do begin
        @(vif.cb_drv);
      end while (!vif.cb_drv.pready);

      if (req.op == axi_lite_seq_item::AXI_READ) begin
        req.data = vif.cb_drv.prdata;
      end
      req.resp = 2'b00;

      vif.cb_drv.psel    <= 1'b0;
      vif.cb_drv.penable <= 1'b0;

      seq_item_port.item_done();
    end
  endtask
endclass


// ----------------------------------------------------------------------------
// 4. Physical Agent
// ----------------------------------------------------------------------------
class axi_lite_agent extends uvm_agent;
  axi_lite_sequencer seqr;
  axi_lite_driver    drv;

  `uvm_component_utils(axi_lite_agent)

  function new(string name = "axi_lite_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seqr = axi_lite_sequencer::type_id::create("seqr", this);
    drv  = axi_lite_driver::type_id::create("drv", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 5. UVM Register Adapter Implementation (reg2axi_adapter)
// ----------------------------------------------------------------------------
class reg2axi_adapter extends uvm_reg_adapter;
  `uvm_object_utils(reg2axi_adapter)

  function new(string name = "reg2axi_adapter");
    super.new(name);
    supports_byte_enable = 1;
    provides_responses   = 0;
  endfunction

  // A. reg2bus: Converts RAL Abstract Operation to Physical Bus Sequence Item
  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    axi_lite_seq_item bus_item;
    bus_item = axi_lite_seq_item::type_id::create("bus_item");

    bus_item.op   = (rw.kind == UVM_WRITE) ? axi_lite_seq_item::AXI_WRITE : axi_lite_seq_item::AXI_READ;
    bus_item.addr = rw.addr;
    bus_item.data = rw.data;
    bus_item.strb = rw.byte_en;

    `uvm_info("ADAPTER_REG2BUS", $sformatf("Converted RAL %s @ 0x%0h (Data=0x%0h) -> Bus Item", 
              rw.kind.name(), rw.addr, rw.data), UVM_HIGH)
    return bus_item;
  endfunction

  // B. bus2reg: Converts Physical Bus Response Item back to RAL Operation
  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    axi_lite_seq_item bus_pkt;

    if (!$cast(bus_pkt, bus_item)) begin
      `uvm_fatal("NOT_AXI_TYPE", "Received bus_item is not of type axi_lite_seq_item!")
      return;
    end

    rw.kind   = (bus_pkt.op == axi_lite_seq_item::AXI_WRITE) ? UVM_WRITE : UVM_READ;
    rw.addr   = bus_pkt.addr;
    rw.data   = bus_pkt.data;
    rw.status = (bus_pkt.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;

    `uvm_info("ADAPTER_BUS2REG", $sformatf("Converted Bus Item -> RAL %s @ 0x%0h (Data=0x%0h, Status=%s)", 
              rw.kind.name(), rw.addr, rw.data, rw.status.name()), UVM_HIGH)
  endfunction
endclass


// ----------------------------------------------------------------------------
// 6. UVM RAL Registers with HDL Path Declarations
// ----------------------------------------------------------------------------
class axis_ctrl_reg extends uvm_reg;
  rand uvm_reg_field enable;
  rand uvm_reg_field soft_rst;
  rand uvm_reg_field mode;

  `uvm_object_utils(axis_ctrl_reg)

  function new(string name = "axis_ctrl_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    enable   = uvm_reg_field::type_id::create("enable");
    soft_rst = uvm_reg_field::type_id::create("soft_rst");
    mode     = uvm_reg_field::type_id::create("mode");

    enable.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    soft_rst.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    mode.configure(this, 2, 2, "RW", 0, 2'b00, 1, 1, 0);
  endfunction
endclass

class axis_status_reg extends uvm_reg;
  uvm_reg_field fifo_full;
  uvm_reg_field fifo_empty;
  uvm_reg_field fifo_error;

  `uvm_object_utils(axis_status_reg)

  function new(string name = "axis_status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    fifo_full  = uvm_reg_field::type_id::create("fifo_full");
    fifo_empty = uvm_reg_field::type_id::create("fifo_empty");
    fifo_error = uvm_reg_field::type_id::create("fifo_error");

    fifo_full.configure(this, 1, 0, "RO", 0, 1'b0, 1, 0, 0);
    fifo_empty.configure(this, 1, 1, "RO", 0, 1'b1, 1, 0, 0);
    fifo_error.configure(this, 1, 2, "RO", 0, 1'b0, 1, 0, 0);
  endfunction
endclass

class axis_reg_block extends uvm_reg_block;
  rand axis_ctrl_reg   ctrl_reg;
  rand axis_status_reg status_reg;

  `uvm_object_utils(axis_reg_block)

  function new(string name = "axis_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    ctrl_reg = axis_ctrl_reg::type_id::create("ctrl_reg");
    ctrl_reg.configure(this, null, "");
    ctrl_reg.build();
    ctrl_reg.add_hdl_path_slice("ctrl_reg_ff", 0, 32);

    status_reg = axis_status_reg::type_id::create("status_reg");
    status_reg.configure(this, null, "");
    status_reg.build();
    status_reg.add_hdl_path_slice("status_reg_ff", 0, 32);

    default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);
    default_map.add_reg(ctrl_reg,   'h00, "RW");
    default_map.add_reg(status_reg, 'h04, "RO");

    set_hdl_path_root("top_tb.dut");
    lock_model();
  endfunction
endclass


// ----------------------------------------------------------------------------
// 7. Environment & Testbench Environment
// ----------------------------------------------------------------------------
class axis_env extends uvm_env;
  axis_reg_block  reg_block;
  reg2axi_adapter adapter;
  axi_lite_agent  axi_agent;

  `uvm_component_utils(axis_env)

  function new(string name = "axis_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reg_block = axis_reg_block::type_id::create("reg_block", this);
    reg_block.configure(null, ""); // Initialize root block hierarchy
    reg_block.build();

    adapter   = reg2axi_adapter::type_id::create("adapter", this);
    axi_agent = axi_lite_agent::type_id::create("axi_agent", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect Adapter & Sequencer to RAL Address Map
    reg_block.default_map.set_sequencer(axi_agent.seqr, adapter);
    reg_block.default_map.set_auto_predict(1);
  endfunction
endclass


// ----------------------------------------------------------------------------
// 8. Test Sequence Demonstrating Frontdoor vs. Backdoor Access
// ----------------------------------------------------------------------------
class axis_frontdoor_vs_backdoor_seq extends uvm_sequence;
  axis_reg_block reg_block;

  `uvm_object_utils(axis_frontdoor_vs_backdoor_seq)

  function new(string name = "axis_frontdoor_vs_backdoor_seq");
    super.new(name);
  endfunction

  virtual task body();
    uvm_status_e   status;
    uvm_reg_data_t rdata;

    `uvm_info("RAL_DEMO", "==================================================", UVM_LOW)
    `uvm_info("RAL_DEMO", "  STARTING WEEK 10: FRONTDOOR VS. BACKDOOR DEMO   ", UVM_LOW)
    `uvm_info("RAL_DEMO", "==================================================", UVM_LOW)

    // ------------------------------------------------------------------------
    // TEST 1: FRONTDOOR WRITE & READ (Drives Bus Interface)
    // ------------------------------------------------------------------------
    `uvm_info("RAL_DEMO", "1. Executing FRONTDOOR WRITE (0x0000_0005 to ctrl_reg)...", UVM_LOW)
    reg_block.ctrl_reg.write(status, 32'h0000_0005, UVM_FRONTDOOR, .parent(this));

    `uvm_info("RAL_DEMO", "2. Executing FRONTDOOR READ from ctrl_reg...", UVM_LOW)
    reg_block.ctrl_reg.read(status, rdata, UVM_FRONTDOOR, .parent(this ));
    `uvm_info("RAL_DEMO", $sformatf("   -> Frontdoor Read Returned: 0x%0h (Mirrored: 0x%0h)", 
              rdata, reg_block.ctrl_reg.get_mirrored_value()), UVM_LOW)

    // ------------------------------------------------------------------------
    // TEST 2: BACKDOOR WRITE & READ (Bypasses Bus Interface, 0-time deposit)
    // ------------------------------------------------------------------------
    `uvm_info("RAL_DEMO", "3. Executing BACKDOOR WRITE (0x0000_000F directly to RTL flip-flops)...", UVM_LOW)
    reg_block.ctrl_reg.write(status, 32'h0000_000F, UVM_BACKDOOR, .parent(this));
    if (status != UVM_IS_OK) begin
        `uvm_error("RAL_DEMO", "Backdoor WRITE Failed! Check HDL path and simulator debug flags")
    end

    `uvm_info("RAL_DEMO", "4. Executing BACKDOOR READ from ctrl_reg...", UVM_LOW)
    reg_block.ctrl_reg.read(status, rdata, UVM_BACKDOOR, .parent(this));
    if (status != UVM_IS_OK) begin
        `uvm_error("RAL_DEMO", "Backdoor READ Failed! Check HDL path and simulator debug flags")
    end
    `uvm_info("RAL_DEMO", $sformatf("   -> Backdoor Read Returned: 0x%0h (Mirrored: 0x%0h)", 
              rdata, reg_block.ctrl_reg.get_mirrored_value()), UVM_LOW)

    // ------------------------------------------------------------------------
    // TEST 3: CROSS-CHECK (Read Frontdoor after Backdoor Write)
    // ------------------------------------------------------------------------
    `uvm_info("RAL_DEMO", "5. Executing FRONTDOOR READ to verify hardware RTL flip-flop state...", UVM_LOW)
    reg_block.ctrl_reg.read(status, rdata, UVM_FRONTDOOR, .parent(this));
    `uvm_info("RAL_DEMO", $sformatf("   -> Frontdoor Verification Read Returned: 0x%0h", rdata), UVM_LOW)

    if (rdata == 32'h0000_000F) begin
      `uvm_info("RAL_DEMO", "STATUS: WEEK 10 RAL ADAPTER & ACCESS TEST PASSED!", UVM_LOW)
    end else begin
      `uvm_error("RAL_DEMO", $sformatf("STATUS: MISMATCH! Expected 0x0F, Got 0x%0h", rdata))
    end
  endtask
endclass


// ----------------------------------------------------------------------------
// 9. UVM Test
// ----------------------------------------------------------------------------
class axis_reg_adapter_test extends uvm_test;
  axis_env env;

  `uvm_component_utils(axis_reg_adapter_test)

  function new(string name = "axis_reg_adapter_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axis_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axis_frontdoor_vs_backdoor_seq seq;
    phase.raise_objection(this);

    seq = axis_frontdoor_vs_backdoor_seq::type_id::create("seq");
    seq.reg_block = env.reg_block;
    seq.start(null);

    #50ns;
    phase.drop_objection(this);
  endtask
endclass


// ----------------------------------------------------------------------------
// 10. Top-Level Testbench Module
// ----------------------------------------------------------------------------
module top_tb;
  logic clk;
  logic rst_n;

  // Clock generation
  initial begin
    clk = 0;
    forever #5ns clk = ~clk;
  end

  // Reset generation
  initial begin
    rst_n = 0;
    #20ns rst_n = 1;
  end

  // Physical interface & DUT
  axi_lite_if vif(clk, rst_n);
  dut_wrapper dut(clk, rst_n, vif);

  initial begin
    uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.axi_agent.drv", "vif", vif);
    run_test("axis_reg_adapter_test");
  end
endmodule
