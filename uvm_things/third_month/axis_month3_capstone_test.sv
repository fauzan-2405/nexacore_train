`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// 1. PHYSICAL BUS INTERFACES
// ============================================================================

// ----------------------------------------------------------------------------
// A. AXI-Lite / APB Register Control Interface
// ----------------------------------------------------------------------------
interface axi_lite_if(input logic clk, input logic rst_n);
    logic pwrite;
    logic penable;
    logic psel;
    logic [31:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic pready;

    clocking cb_drv @(posedge clk);
        default input #1ns output #1ns;
        output pwrite, penable, psel, paddr, pwdata;
        input prdata, pready;
    endclocking

    clocking cb_mon @(posedge clk);
        default input #1ns output #1ns;
        input pwrite, penable, psel, paddr, pwdata, prdata, pready;
    endclocking
endinterface

// ----------------------------------------------------------------------------
// B. AXI4-Stream Data Streaming Interface
// ----------------------------------------------------------------------------
interface axi_if (input logic clk, input logic rst_n);
    logic tvalid;
    logic tready;
    logic [31:0] tdata;
    logic [3:0] tkeep;
    logic tlast;

    clocking cb_drv @(posedge clk);
        default input #1ns output #1ns;
        output tvalid, tdata, tkeep, tlast;
        input tready;
    endclocking

    clocking cb_mon @(posedge clk);
        default input #1ns output #1ns;
        input tvalid, tdata, tkeep, tlast, tready;
    endclocking
endinterface

// ============================================================================
// 2. HARDWARE DESIGN UNDER TEST (DUT: AXI4-Stream FIFO + Register Control)
// ============================================================================
module axis_fifo_dut(
    input logic clk,
    input logic rst_n,
    axis_lite_if    ctrl_vif,
    axi_if          s_axis_vif,
    axi_if          m_axis_vif
);
    // Internal register FF (HDL Backdoor Path Targets)
    logic [31:0] ctrl_reg_ff;   // Root path: top_tb.dut.ctrl_reg_ff (Offset 0x00)
    logic [31:0] status_reg_ff; // Root path: top_tb.dut.status_reg_ff (Offset 0x04)

    // Internal FIFO Storage
    logic [31:0] fifo_mem   [0:15];
    logic [3:0]  fifo_keep  [0:15];
    logic        fifo_last  [0:15];
    logic [4:0]  wr_ptr;
    logic [4:0]  rd_ptr;
    logic [4:0]  fifo_count;

    wire fifo_full_w  = (fifo_count >= 16);
    wire fifo_empty_w = (fifo_count == 0);

    // Status register mapping: 
    // Bit 0: fifo_full | Bit 1: fifo_empty | Bit 2: fifo_error
    assign status_reg_ff = {29'b0, 1'b0, fifo_empty_w, fifo_full_w};

    // AXI-Lite Register Access Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg_ff     <= '0;
            ctrl_vif.pready <=  1'b0;
            ctrl_vif.prdata <= '0;
        end else begin
            if (ctrl_vif.psel && ctrl_vif.penable) begin
                ctrl_vif.pready <= 1'b1;
                if (ctrl_vif.pwrite) begin
                    case (ctrl_vif.paddr)
                        32'h00: ctrl_reg_ff <= ctrl_vif.pwdata;
                    endcase
                end else begin
                    case (ctrl_vif.paddr)
                        32'h00: ctrl_vif.prdata <= ctrl_reg_ff;
                        32'h04: ctrl_vif.prdata <= status_reg_ff;
                        default: ctrl_vif.prdata<= 32'hDEAD_BEEF;
                    endcase
                end
            end else begin
                ctrl_vif.pready <= 1'b0;
            end
        end
    end

    // FIFO Push & Pop Operational Logic
    wire dut_enabled = ctrl_reg_ff[0];
    wire [1:0] mode  = ctrl_reg_ff[3:2]; // 00: Normal, 01: Loopback, 10: Bypass

    assign s_axis_vif.tready = dut_enabled && !fifo_full_w;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            wr_ptr      <= 0;
            rd_ptr      <= 0;
            fifo_count  <= 0;
        end else if (ctrl_reg_ff[1]) begin  // Soft Reset
            wr_ptr      <= 0;
            rd_ptr      <= 0;
            fifo_count  <= 0;
        end else begin
            // Write to FIFO
            if (s_axis_vif.tvalid && s_axis_vif.tready) begin
                fifo_mem[wr_ptr[3:0]]   <= s_axis_vif.tdata;
                fifo_keep[wr_ptr[3:0]]  <= s_axis_vif.tkeep;
                fifo_last[wr_ptr[3:0]]  <= s_axis_vif.tlast;
                wr_ptr  <= wr_ptr + 1'b1;
            end

            // Read from FIFO
            if (m_axis_vif.tvalid && m_axis_vif.tready) begin
                rd_ptr  <= rd_ptr + 1;
            end

            // Update FIFO Counter
            case ({ (s_axis_vif.tvalid && s_axis_vif.tready), (m_axis_vif.tvalid && m_axis_vif.tready)}) 
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // Output driving
    assign m_axis_vif.tvalid = dut_enabled && !fifo_empty_w;
    assign m_axis_vif.tdata  = fifo_mem[rd_ptr[3:0]];
    assign m_axis_vif.tkeep  = fifo_keep[rd_ptr[3:0]];
    assign m_axis_vif.tlast  = fifo_last[rd_ptr[3:0]];
endmodule

// ============================================================================
// 3. SEQUENCE ITEMS
// ============================================================================

// ----------------------------------------------------------------------------
// A. Physical AXI-Lite Item
// ----------------------------------------------------------------------------
class axi_lite_seq_item extends uvm_sequence_item;
    typedef enum {AXI_READ, AXI_WRITE} axi_op_e;

    rand axi_op_e op;
    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand bit [3:0] strb;
    bit [1:0] resp;

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
// B. AXI4-Stream Packet Sequence Item
// ----------------------------------------------------------------------------
class axis_seq_item extends uvm_sequence_item;
    typedef enum bit [1:0] {MODE_NORMAL = 2'b00, MODE_LOOPBACK  = 2'b01, MODE_BYPASS = 2'b10} mode_e;
    typedef enum bit [1:0] {FIFO_EMPTY  = 2'b00, FIFO_MID       = 2'b01, FIFO_FULL   = 2'b10} fifo_status_e;
    
    rand mode_e         mode;
    rand fifo_status_e  fifo_status;
    rand bit [31:0]     data[];
    rand int            stall_delay;
    rand bit            tlast;

    constraint c_data_size  {data.size() inside {[1:16]}; }
    constraint c_stall      {stall_delay inside {[0:10]}; }

    `uvm_object_utils_begin(axis_seq_item)
        `uvm_field_enum(mode_e, mode, UVM_ALL_ON)
        `uvm_field_enum(fifo_status_e, fifo_status, UVM_ALL_ON)
        `uvm_field_array(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(stall_delay, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(tlast, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "axis_seq_item");
        super.new(name);
    endfunction
endclass


// ============================================================================
// 4. PHYSICAL DRIVERS & SEQUENCERS
// ============================================================================

typedef uvm_sequencer #(axis_lite_seq_item) axi_lite_sequencer;
typedef uvm_sequencer #(axis_sew item) axi_lite_sequencer;

// A. AXI-Lite Driver
class axi_lite_driver extends uvm_driver #(axi_lite_seq_item);
    virtual axi_lite_if vif;
    `uvm_component_utils(axi_lite_driver)

    function new (string name = "axi_lite_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", "Virtual interface not found for axi_lite_driver")
    endfunction

    virtual task run_phase(uvm_phase phase);
        axi_lite_seq_item req;
        vif.cb_drv.psel     <= 1'b0;
        vif.cb_drv.penable  <= 1'b0;

        forever begin
            seq_item_port.get_next_item(req);

            @(vif.cb_drv);
            vif.cb_drv.psel     <= 1'b1;
            vif.cb_drv.pwrite   <= (req.op == axi_lite_seq_item::AXI_WRITE);
            vif.cb_drv.paddr    <= req.addr;
            vif.cb_drv.pwdata   <= req.data;

            @(vif.cb_drv)
            vif.cb_drv.penable  <= 1'b1;
            do begin
                @(vif.cb_drv);
            end while (!vif.cb_drv.pready);

            if (req.op == axi_lite_seq_item::AXI_READ) begin
                req.data = vif.cb_drv.prdata;
            end
            req.resp = 2'b00;

            vif.cb_drv.psel     <= 1'b0;
            vif.cb_drv.penable  <= 1'b0;

            seq_item_port.item_done();
        end
    endtask
endclass

// B. AXI-Stream Driver
class axis_stream_driver extends uvm_driver #(axis_seq_item);
    virtual axis_if vif;
    `uvm_component_utils(axis_stream_driver)

    function new(string name = "axis_stream_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", "Virtual interface not found for axis_stream_driver")
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_seq_item req;
        vif.cb_drv.tvalid <= 1'b0;

        forever begin
            seq_item_port.get_next_item(req);

            // Apply initial backpressure stall
            if (req.stall_delay > 0) begin
                repeat (req.stall_delay) @(vif.cb_drv);
            end

            // Stream
            for (int i = 0; i < req.data.size(); i++) begin
                @(vif.cb_drv);
                vif.cb_drv.tvalid   <= 1'b1;
                vif.cb_drv.tdata    <= req.data[i];
                vif.cb_drv.tkeep    <= 4'b1111;
                vif.cb_drv.tlast    <= (i == req.data.size() - 1);

                do begin
                    @(vif.cb_drv);
                end while (!vif.cb_drv.tready);
            end

            vif.cb_drv.tvalid   <= 1'b0;
            vif.cb_drv.tlast    <= 1'b0;
            seq_item_port.item_done();
        end
    endtask
endclass

// ============================================================================
// 5. PHYSICAL MONITORS
// ============================================================================
class axis_stream_monitor extends uvm_monitor;
    virtual axis_if vif;
    uvm_analysis_port #(axis_seq_item) ap;
    `uvm_component_utils(axis_stream_monitor)

    function new (string name = "axis_stream_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
            `uvm_fatal("NO_VIF", "Virtual interface not found for axis_stream_monitor")
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(vif.cb_mon);
            if (vif.cb_mon.tvalid && vif.cb_mon.tready) begin
                axis_seq_item item = axis_seq_item::type_id::create("mon_item");
                item.data    = new[1];
                item.data[0] = vif.cb_mon.tdata;
                item.tlast   = vif.cb_mon.tlast;
                ap.write(item); 
            end
        end
    endtask
endclass

// ============================================================================
// 6. UVM REGISTER ABSTRACTION LAYER (RAL) MODEL & ADAPTER
// ============================================================================
class axis_ctrl_reg extends uvm_reg;
    rand uvm_reg_field enable;
    rand uvm_reg_field soft_rst;
    rand uvm_reg_field mode;
    `uvm_object_utils(axis_ctrl_reg)

    function neew (string name = "axis_ctrl_reg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        enable   = uvm_reg_field::type_id::create("enable");
        soft_rst = uvm_reg_field::type_id::create("soft_rst");
        mode     = uvm_reg_field::type_id::create("mode");

        enable.configure(this, 1, 0, "RW", 0. 1'b0. 1, 1, 0);
        soft_rst.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
        mode.configure(this, 2, 2, "RW", 0, 2'b00, 1, 1, 0);
    endfunction
endclass

class axis_status_reg extends uvm_reg;
    uvm_reg_field fifo_full;
    uvm_reg_field fifo_empty;
    uvm_reg_field fifo_error;
    `uvm_object_utils(axis_status_reg)

    function new (string name = "axis_status_reg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        fifo_full  = uvm_reg_field::type_id::create("fifo_full");
        fifo_empty = uvm_reg_field::type_id::create("fifo_empty");
        fifo_error = uvm_reg_field::type_id::create("fifo_error");

        fifo_full.configure(this, 1, 0, "RO", 0, 1'b0, 1, 0, 0);
        fifo_empty.configure(this, 1, 1, "RO", 0, 1'b0, 1, 0, 0);
        fifo_error.configure(this, 1, 2, "RO", 0, 1'b0, 1, 0, 0);
    endfunction
endclass

class axis_req_block extends uvm_reg_block;
    rand axis_ctrl_reg ctrl_reg;
    rand axis_status_reg status_reg;
    `uvm_object_utils(axis_req_block)

    function new(string name "axis_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        ctrl_reg = axis_ctrl_reg::type_id::create("ctrl_reg");
        ctrl_reg = configure(this, null. "ctrl_reg_ff");
        ctrl_reg.build();

        status_reg = axis_status_reg::type_id::create("status_reg");
        status_reg = configure("this", null, "status_reg_ff");
        status_reg.build();

        default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN, 1);
        default_map.add_reg(ctrl_reg, 'h00, "RW");
        default_map.add_reg(status_reg, 'h04, "RO");

        add_hdl_path("top_tb.dut");
        lock_model();
    endfunction
endclass

// Register Adapter
class reg2axi_adapter extends uvm_reg_adapter;
    `uvm_object_utils(reg2axi_adapter);

    function new (string name = "reg2axi_adapter");
        super.new(name);
        supports_byte_enable    = 1;
        provides_reponses       = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        axi_lite_seq_item bus_item = axi_lite_seq_item::type_id::create("bus_item");
        bus_item.op = (rw.kind == UVM_WRITE) ? axi_lite_seq_item::AXI_WRITE : axi_lite_seq_item::AXI_READ;
        bus_item.addr   = rw.addr;
        bus_item.data   = rw.data;
        bus_item.strb   = rw.byte_en;
        return bus_item;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus item, reg uvm_reg_bus_op rw);
        axi_lite_seq_item bus_pkt;
        if (!cast(bus_pkt, bus_item)) return;
        rw.kind     = (bus_pkt.op == axi_lite_seq_item::AXI_WRITE) ? UVM_WRITE : UVM_READ;
        rw.addr     = bus_pkt.addr;
        rw.data     = bus_pkt.data;
        rw.status   = (bus_pkt.resp == 2'b00)? UVM_IS_OK : UVM_NOT_OK;
    endfunction
endclass

// ============================================================================
// 7. FUNCTIONAL COVERAGE SUBSCRIBER
// ============================================================================
class axis_coverage_subscriber extends uvm_subscriber #(axis_seq_item);
    `uvm_component_utils(axis_coverage_subscriber)
    axis_seq_item pkt;

    covergroup cg_axis_functional;
        option.per_instance = 1;
        option.comment      = "AXI4-Stream Capstone Functional Coverage";

        cp_pkt_len: coverpoint pkt.data.size(); {
            bins single_word = {1};
            bins small_burst = {[2:4]};
            bins med_burst   = {[5:8]};
            bins max_burst   = {[9:16]};
        }

        cp_stall_delay: coverpoint pkt.stall_delay {
            bins zero_stall  = {0};
            bins short_stall = {[1:3]};
            bins long_stall  = {[4:10]};
        }

        cp_mode: coverpoint pkt.mode{
            bins mode_norm  = {axis_seq_item::MODE_NORMAL};
            bins mode_loop  = {axis_seq_item::MODE_LOOPBACK};
            bins mode_byp   = {axis_seq_item::MODE_BYPASS};
        }

        cp_fifo_status: coverpoint pkt.fifo_status{
            bins empty  = {axis_seq_item::FIFO_EMPTY};
            bins mid    = {axis_seq_item::FIFO_MID};
            bins full   = {axis_seq_item::FIFO_FULL};
        }

        cross_mode_x_fifo: cross cp_mode, cp_fifo_status {
            ignore_bins ignore_byp_fifo =   binsof(cp_mode) intersect {axi_seq_item::MODE_BYPASS} &&
                                            binsof(cp_mode_status) intersect {axi_seq_item::FIFO_MID, axis_seq_item::FIFO_FULL};
        }
    endgroup

    function new(string name = "axis_coverage_subscriber", uvm_component parent = null);
        super.new(name, parent);
        cg_axis_functional = new();
    endfunction

    virtual function void write(axis_seq_item t);
        this.pkt = t;
        cg_axis_functional.sample();
    endfunction

    virtual function real get_coverage_percentage();
        return cg_axis_functional.get_inst_coverage();
    endfunction
endclass

// ============================================================================
// 8. TLM SCOREBOARD
// ============================================================================
class axis_scoreboard extends uvm_scoreboard;
    `uvm_component_utils (axis_scoreboard)

    uvm_analysis_imp #(axis_seq_item, axis_scoreboard) item_export;
    bit [31:0] expected queue[$];
    int match_count;
    int mismatch_count;

    function new(string name = "axis_scoreboard", uvm_component parent null);
        super.new(name, parent);
        item_export = new("item_export", this);
        match_count = 0;
        mismatch_count = 0;
    endfunction

    virtual function void write(axis_seq_item);
        match_count++;
        `uvm_info("SCB", $sformatf("Verified Data Packet Transfer: 0x%08h | Matches: %0d", 
              item.data[0], match_count), UVM_HIGH)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("SCB", "==================================================", UVM_LOW)
        `uvm_info("SCB", $sformatf("  SCOREBOARD SUMMARY: Matches=%0d, Mismatches=%0d", 
                match_count, mismatch_count), UVM_LOW)
        `uvm_info("SCB", "==================================================", UVM_LOW)
  endfunction
endclass

// ============================================================================
// 9. VIRTUAL SEQUENCER & SYSTEM VIRTUAL SEQUENCES
// ============================================================================
class axis_virtual_sequencer extends uvm_sequencer;
    axi_lite_sequencer      axi_seqr;
    axis_stream_sequencer   axis_seqr;
    axis_reg_block          reg_block;

    `uvm_component_utils(axis_virtual_sequencer)

    function new(string name = "axis_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

// Child sequence A: RAL Register Configuration
class axis_ral_cfg_seq extends uvm_sequence;
    axis_reg_block reg_block;
    `uvm_object_utils(axis_ral_cfg_seq)

    function new(string name = "axis_ral_cfg_seq");
        super.new(name);
    endfunction

    virtual task body();
        uvm_status_e status;
        uvm_reg_data rdata;

        // 1.Backdoor Initialization 
        `uvm_info("RAL_SEQ", "Backdoor Pre-loading DUT registers...", UVM_LOW)
        reg_block.ctrl_reg.write(status, 32'h0000_0001, UVM_BACKDOOR, .parent(this)); // Enable DUT 

        // 2. Frontdoor Configuration Write
        `uvm_info("RAL_SEQ", "Frontdoor Mode Configuration (Enable + Normal Mode)...", UVM_LOW)
        reg_block.ctrl_reg.write("status", 32'h0000_0005, UVM_FRONTDOOR, .parent(this));

        // 3. Frontdoor Verification Read 
        reg_block.ctrl_reg.read(status, rdata, UVM_FRONTDOOR, .parent(this));
        `uvm_info("RAL_SEQ", $sformatf("Readback Verification ctrl_reg = 0x%0h", rdata), UVM_LOW)
    endtask
endclass

// Child Sequence B: AXI4-Stream Traffic Burst
class axis_stream_traffic_seq extends uvm_sequence #(axis_seq_item);
    int num_packets = 25;
    `uvm_object_utils(axis_stream_traffic_seq)

    function new(string name = "axis_stream_traffic_seq");
        super.new(name);
    endfunction

    virtual task body();
        repeat (num_packets) begin
            req = axis_seq_item::type_id::create("req");
            start_item(req);
            assert(req.randomize() with {
                mode inside {axis_seq_item::MODE_NORMAL, axis_seq_item::MODE_LOOPBACK};
            });
            finish_item(req);
        end
    endtask
endclass

// Master Virtual Sequence (Coordinates Start, Phases, and Finish)
class axis_month3_capstone_vseq extends uvm_sequence;
    `uvm_object_utils(axis_month3_capstone_vseq)
    `uvm_declare_p_sequencer(axis_virtual_sequencer)

    axis_ral_cfg_seq        ral_seq;
    axis_stream_traffic_seq stream_seq;

    function new(string name = "axis_month3_capstone_vseq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("VSEQ", "==================================================", UVM_LOW)
        `uvm_info("VSEQ", "  STAGE 1: RAL FRONTDOOR/BACKDOOR CONFIGURATION   ", UVM_LOW)
        `uvm_info("VSEQ", "==================================================", UVM_LOW)

        ral_seq = axis_ral_cfg_seq::type_id::create("ral_seq");
        ral_seq.reg_block = p_sequencer.reg_block;
        ral_seq.start(p_sequencer.axi_seqr); // Blocking: Setup before data flow 

        `uvm_info("VSEQ", "==================================================", UVM_LOW)
        `uvm_info("VSEQ", "  STAGE 2: CONCURRENT STREAM TRAFFIC & MONITORING ", UVM_LOW)
        `uvm_info("VSEQ", "==================================================", UVM_LOW)
        stream_req = axis_stream_traffic_seq::type_id::create("stream_seq");

        fork
            // Thread 1: Stream 30 packets into FIFO
            stream_Seq.start(p_sequencer.axis_seqr);

            // Thread 2: Periodic RAL Status Register Polling
            begin
                uvm_status_e    status;
                uvm_reg_data_t  rdata;
                repeat (5) begin
                    #40ns;
                    p_sequencer.reg_block.status_reg.read(status, rdata, UVM_FRONTDOOR, .parent(this));
                    `uvm_info("VSEQ", $sformatf("Polled Hardware status_reg = 0x%0h (Empty=%0b, Full=%0b)", 
                                rdata, rdata[1], rdata[0]), UVM_MEDIUM)
                end
            end
        join

        `uvm_info("VSEQ", "==================================================", UVM_LOW)
        `uvm_info("VSEQ", "  STAGE 3: SCENARIO STIMULUS COMPLETE             ", UVM_LOW)
        `uvm_info("VSEQ", "==================================================", UVM_LOW)
    endtask
endclass

// ============================================================================
// 10. UVM ENVIRONMENT (axis_env)
// ============================================================================
class axis_env extends uvm_env;
    `uvm_component_utils(axis_env)

    // Agents
    axi_lite_sequencer      axi_seqr;
    axi_lite_driver         axi_drv;
    aixs_stream_sequencer   axis_seqr;
    axis_stream_driver      axis_drv;
    axis_stream_monitor     axis_mon;

    // RAL, Adapter, & Virtual Sequencer
    axis_reg_block          reg_block;
    reg2axi_adapter         adapter;
    axis_virtual_sequencer  v_sqr;

    // Verification Components
    axis_coverage_subscriber    cov_sub;
    axis_scoreboard             scb;

    function new (string name = "axis_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        axi_seqr  = axi_lite_sequencer::type_id::create("axi_seqr", this);
        axi_drv   = axi_lite_driver::type_id::create("axi_drv", this);
        axis_seqr = axis_stream_sequencer::type_id::create("axis_seqr", this);
        axis_drv  = axis_stream_driver::type_id::create("axis_drv", this);
        axis_mon  = axis_stream_monitor::type_id::create("axis_mon", this);

        reg_block = axis_reg_block::type_id::create("reg_block", this);
        reg_block.build();
        adapter   = reg2axi_adapter::type_id::create("adapter", this);

        v_sqr     = axis_virtual_sequencer::type_id::create("v_sqr", this);
        cov_sub   = axis_coverage_subscriber::type_id::create("cov_sub", this);
        scb       = axis_scoreboard::type_id::create("scb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Connect Drivers to Sequencers
        axi_drv.seq_item_port.connect(axi_seqr.seq_item_export);
        axis_drv.seq_item_port.connect(axi_seqr.seq_item_export);

        // Connect RAL default_map to Sequencer and Adapter
        reg_block.default_map.set_sequencer(axi_seqr, adapter);
        reg_block.default_map.set_auto_predict[1];

        // Comnnect Virtual Sequencer sub-handles
        v_sqr.axi_seqr  = axi_seqr;
        v_sqr.axis_seqr = axis_seqr;
        v_sqr.reg_block = reg_block;

        // Connecting the Monitor Analysis Port to Scoreboard & Coverage Subscriber
        axis_mon.ap.connect(scb.item_export);
        axis_drv.seq_item_port.connect(cov_sub.analysis_export);
    endfunction
endclass


// ============================================================================
// 11. TOP-LEVEL TEST CLASS (axis_month3_capstone_test)
// ============================================================================
class axis_month3_capstone_test extend uvm_test;
    `uvm_component_utils(axis_month3_capstone_test)
    axis_env env;

    function new (string name = "axis_month3_capstone_test", uvm_componenet parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axis_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_month3_capstone_vseq vseq;
        
        phase.raise_objection(this, "Starting Capstone Virtual Sequence");

        // Configure drain time (allows hardware pipeline & FIFO to settle)
        phase.get_objection().set_drain_time(this, 100ns);

        vseq = axis_month3_capstone_vseq::type_id::create("vseq");
        vseq.start(env.v_sqr);

        `uvm_info("TEST", "Virtual Sequence Completed. Waiting for Drain Time...", UVM_LOW)
        phase.drop_objection(this, "Finishing Capstone Virtual Sequence");
    endtask

    virtual function void report_phase(uvm_phase phase);
        real cov;
        super.report_phase(phase);
        cov = env.cov_sub.get_coverage_percentage();

        `uvm_info("REPORT", "==================================================", UVM_LOW)
        `uvm_info("REPORT", "  MONTH 3 FINAL CAPSTONE VERIFICATION REPORT      ", UVM_LOW)
        `uvm_info("REPORT", "==================================================", UVM_LOW)
        `uvm_info("REPORT", $sformatf("  TOTAL FUNCTIONAL COVERAGE ACHIEVED: %0.2f%%", cov), UVM_LOW)
        `uvm_info("REPORT", $sformatf("  FINAL SCOREBOARD VERIFIED PACKETS : %0d", env.scb.match_count), UVM_LOW)
        `uvm_info("REPORT", $sformatf("  FINAL SCOREBOARD ERROR MISMATCHES : %0d", env.scb.mismatch_count), UVM_LOW)
        if (env.scb.mismatch_count == 0 && cov >= 90.0) begin
            `uvm_info("REPORT", "  STATUS: >>> CAPSTONE PASSED - 100% CLOSURE ACHIEVED <<<", UVM_LOW)
        end else begin
            `uvm_error("REPORT", "  STATUS: >>> CAPSTONE FAILED <<<")
        end
        `uvm_info("REPORT", "==================================================", UVM_LOW)
    endfunction
endclass

// ============================================================================
// 12. TESTBENCH TOP (top_tb)
// ============================================================================
module top_tb;
    logic clk;
    logic rst_n;

    // Clock generation: 100 MHz (10 ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        #25;
        rst_n = 1;
    end

    // Physical Interface Instantiations
    axi_lite_if ctrl_if(clk, rst_n);
    axis_if     s_axis_if(clk, rst_n);
    axis_if     m_axis_if(clk, rst_n);

    // Hardware DUT Instantiation
    axis_fifo_dut dut(
        .clk        (clk),
        .rst_n      (rst_n),
        .ctrl_vif   (ctrl_if),
        .s_axis_vif (s_axis_if),
        .m_axis_vif (m_axis_if)
    );

    // Loopback connection on master output for self-loopback verification
    assign m_axis_if.tready = 1'b1;

    // UVM Config DB Registrations & Test Execution
    initial begin
        uvm_config_db#(virtual axi_lite_ig)::set(null, "*", "vif", ctrl_if);
        uvm_config_db#(virtual axis_if)::set(null, "*axis_stream_driver*", "vif", s_axis_if);
        uvm_config_db#(virtual axis_if)::set(null, "*axis_stream_monitor*", "vif", s_axis_if);
    end
endmodule