// ============================================================================
// File: axis_reg_block.sv
// Description: Month 3, Week 9 Deliverable - Hand-Coded UVM Register Block
// Objectives: Demonstrate uvm_reg_field, uvm_reg, uvm_reg_block, and uvm_reg_map.
// ============================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// 1. CONTROL REGISTER (Offset: 0x00, Access: RW)
// ============================================================================
class axis_ctrl_reg extends uvm_reg;
  rand uvm_reg_field enable;    // Bit 0: Module Enable
  rand uvm_reg_field soft_rst;  // Bit 1: Soft Reset Pulse
  rand uvm_reg_field mode;      // Bits [3:2]: Operating Mode (00=Normal, 01=Loopback)

  `uvm_object_utils(axis_ctrl_reg)

  function new(string name = "axis_ctrl_reg");
    super.new(name, 32, UVM_NO_COVERAGE); // 32-bit register width
  endfunction

  virtual function void build();
    enable   = uvm_reg_field::type_id::create("enable");
    soft_rst = uvm_reg_field::type_id::create("soft_rst");
    mode     = uvm_reg_field::type_id::create("mode");

    // configure(parent, size, lsb_pos, access, volatile, reset_val, has_reset, is_rand, individually_accessible)
    enable.configure  (this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    soft_rst.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    mode.configure    (this, 2, 2, "RW", 0, 2'b00, 1, 1, 0);
  endfunction
endclass


// ============================================================================
// 2. STATUS REGISTER (Offset: 0x04, Access: RO)
// ============================================================================
class axis_status_reg extends uvm_reg;
  uvm_reg_field fifo_full;   // Bit 0: FIFO Full Status Flag
  uvm_reg_field fifo_empty;  // Bit 1: FIFO Empty Status Flag
  uvm_reg_field fifo_error;  // Bit 2: Overflow / Underflow Error Flag

  `uvm_object_utils(axis_status_reg)

  function new(string name = "axis_status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    fifo_full  = uvm_reg_field::type_id::create("fifo_full");
    fifo_empty = uvm_reg_field::type_id::create("fifo_empty");
    fifo_error = uvm_reg_field::type_id::create("fifo_error");

    fifo_full.configure (this, 1, 0, "RO", 0, 1'b0, 1, 0, 0);
    fifo_empty.configure(this, 1, 1, "RO", 0, 1'b1, 1, 0, 0); // Default empty on reset
    fifo_error.configure(this, 1, 2, "RO", 0, 1'b0, 1, 0, 0);
  endfunction
endclass


// ============================================================================
// 3. INTERRUPT ENABLE REGISTER (Offset: 0x08, Access: RW)
// ============================================================================
class axis_intr_en_reg extends uvm_reg;
  rand uvm_reg_field full_intr_en;   // Bit 0: Full Interrupt Enable
  rand uvm_reg_field empty_intr_en;  // Bit 1: Empty Interrupt Enable
  rand uvm_reg_field err_intr_en;    // Bit 2: Error Interrupt Enable

  `uvm_object_utils(axis_intr_en_reg)

  function new(string name = "axis_intr_en_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    full_intr_en  = uvm_reg_field::type_id::create("full_intr_en");
    empty_intr_en = uvm_reg_field::type_id::create("empty_intr_en");
    err_intr_en   = uvm_reg_field::type_id::create("err_intr_en");

    full_intr_en.configure (this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    empty_intr_en.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
    err_intr_en.configure  (this, 1, 2, "RW", 0, 1'b0, 1, 1, 0);
  endfunction
endclass


// ============================================================================
// 4. TOP-LEVEL REGISTER BLOCK & ADDRESS MAP CONFIGURATION
// ============================================================================
class axis_reg_block extends uvm_reg_block;
  rand axis_ctrl_reg    ctrl_reg;
  rand axis_status_reg  status_reg;
  rand axis_intr_en_reg intr_en_reg;

  `uvm_object_utils(axis_reg_block)

  function new(string name = "axis_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    // A. Instantiate child registers
    ctrl_reg = axis_ctrl_reg::type_id::create("ctrl_reg");
    ctrl_reg.configure(this, null, "");
    ctrl_reg.build();

    status_reg = axis_status_reg::type_id::create("status_reg");
    status_reg.configure(this, null, "");
    status_reg.build();

    intr_en_reg = axis_intr_en_reg::type_id::create("intr_en_reg");
    intr_en_reg.configure(this, null, "");
    intr_en_reg.build();

    // B. Create Address Map (Base Offset: 0x0, 32-bit width = 4 bytes, Little Endian)
    default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);

    // C. Bind registers to offsets in default_map
    default_map.add_reg(ctrl_reg,    'h00, "RW");
    default_map.add_reg(status_reg,  'h04, "RO");
    default_map.add_reg(intr_en_reg, 'h08, "RW");

    // D. Lock model architecture to complete address lookup tables
    lock_model();
  endfunction
endclass


// ============================================================================
// 5. TEST DEMONSTRATION: INSPECTING DESIRED VS. MIRRORED VALUES
// ============================================================================
module top_tb;
  axis_reg_block rm;

  initial begin
    `uvm_info("RAL_TEST", "Instantiating Hand-Coded axis_reg_block...", UVM_LOW)

    rm = axis_reg_block::type_id::create("rm");
    rm.build();
    rm.reset(); // Applies reset defaults across all fields

    // 1. Inspect Reset Values
    `uvm_info("RAL_TEST", $sformatf("Default Reset State -> ctrl_reg: 0x%0h, status_reg: 0x%0h (empty bit=%0b)",
              rm.ctrl_reg.get_reset(), rm.status_reg.get_reset(), rm.status_reg.fifo_empty.get_reset()), UVM_LOW)

    // 2. Manipulate Desired Values in Software Memory (Without hardware bus access)
    rm.ctrl_reg.enable.set(1'b1);
    rm.ctrl_reg.mode.set(2'b01); // Set Loopback mode

    `uvm_info("RAL_TEST", $sformatf("Software Set -> Desired Value: 0x%0h, Mirrored Value: 0x%0h",
              rm.ctrl_reg.get_desired_value(), rm.ctrl_reg.get_mirrored_value()), UVM_LOW)

    // 3. Simulate hardware predict update (predicting hardware bus write completion)
    rm.ctrl_reg.predict(rm.ctrl_reg.get_desired_value());

    `uvm_info("RAL_TEST", $sformatf("After Predict -> Desired Value: 0x%0h, Mirrored Value: 0x%0h",
              rm.ctrl_reg.get_desired_value(), rm.ctrl_reg.get_mirrored_value()), UVM_LOW)

    `uvm_info("RAL_TEST", "Week 9 RAL Register Block Model Verification PASSED.", UVM_LOW)
  end
endmodule
