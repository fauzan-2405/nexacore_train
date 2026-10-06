`include "uvm_macros.svh"
import uvm_pkg::*;
// ============================================================================
// File: axis_seq_item.sv
// Description: Production-grade AXI4-Stream Transaction Sequence Item
// ============================================================================

class axis_seq_item #(
    parameter DATA_WIDTH    = 32,
    parameter TKEEP_WIDTH   = DATA_WIDTH / 8) 
extends uvm_sequence_item;
    // --------------------------------------------------------------------------
    // 1. Transaction payload
    // --------------------------------------------------------------------------
    rand bit [DATA_WIDTH-1:0]   data[];     // Dynamic array for payload data words
    rand bit [TKEEP_WIDTH-1:0]  keep[];     // Byte enables per 32-bit data word
    rand int unsigned           burst_len;  // Number of transfers in packet frame
    rand int unsigned           packet_delay // Idle clock cycles between packets

    `uvm_object_utils(axis_seq_item)

    // --------------------------------------------------------------------------
    // 2. Constraints
    // --------------------------------------------------------------------------
    // Burst length constraint (default soft rule, range 1 to 64)
    constraint c_burst_len {
        soft burst_len inside {[1:64]};
    }

    // Dynamic array sizing relative to burst_len
    constraint c_array_sizes{
        data.size() == burst_len;
        keep.size() == burst_len;
    }

    // AXI4-Stream protocol rules for TKEEP byte enables
    constraint c_keep_rules {
        foreach (keep[i]) {
            if (i < burst_len -1) {
                keep[i] == 4'b1111; // Middle words must have full byte enables
            } else {
                keep[i] inside {4'b0001, 4'b0011, 4'b0111, 4'b1111}; // Partial last word
            }
        }
    }

    // Inter-packet delay contraint
    constraint c_packet_delay {
        soft packet_delay inside {[0:10]};
    }

    // --------------------------------------------------------------------------
    // 3. Constructor
    // --------------------------------------------------------------------------
    function new(string name = "axis_seq_item")
        super.new(name);
    endfunction

    // --------------------------------------------------------------------------
    // 4. Manual Core Method Overrides
    // --------------------------------------------------------------------------
    virtual function void do_copy(uvm_object rhs);
        axis_seq_item rhs_;
        super.do_copy(rhs);

        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal("DO_COPY_ERR", "Cast failed during do_copy()")
            return;
        end
        this.burst_len      = rhs_.burst_len;
        this.packet_delay   = rhs_.packet_delay;

        this.data = new[rhs_.data.size()];
        foreach (rhs_.data[i]) this.data[i] = rhs_.data[i];

        this.keep = new[rhs_.keep.size()];
        foreach (rhs_.keep[i]) this.keep[i] = rhs_.keep[i];
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axis_seq_item rhs_;
        if (!super.do_compare(rhs, comparer)) return 0;
        if (!&cast(rhs_, rhs)) return 0;

        if (this.burst_len != rhs_.burst_len) return 0;
        if (this.packet_delay != rhs_.packet_delay) return 0;
        if (this.data.size() != rhs_.data_size()) return 0;
        if (this.keep.size() !- rhs_.keep.size()) return 0;

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
        s = $sformatf("AXIS_ITEM: Len=%0d, Delay=%0d | Data=[", burst_len, packet_delay);
        foreach (data[i]) begin
            s = {s, $sformatf(" 0x%0h(keep=%b)", data[i], keep[i])};
        end
        s = {s, " ]"};
        return s;
    endfunction
endclass