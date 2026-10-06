`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// File: axis_seq.sv
// Description: UVM Sequence Suite for AXI4-Stream Traffic Generation
// ============================================================================

// ----------------------------------------------------------------------------
// Base Sequence Class
// ----------------------------------------------------------------------------
virtual class axis_base_seq extends uvm_sequence #(axis_seq_item);
    `uvm_object_utils(axis_base_seq)

    function new(string name = "axis_base_seq");
        super.new(name);
    endfunction

    // Helper task to handle standard UVM driver-sequencer handshake
    protected task send_item_with_constraints(ref axis_seq_item);
        start_item(item);
        if (!item.randomize()) begin
            `uvm_fatal("SEQ_RAND_FAIL", "Randomization failed inside sequence!")
        end
        finish_item(item);
    endtask
endclass

// ----------------------------------------------------------------------------
// 1. Randomized Burst Sequence
// ----------------------------------------------------------------------------
class axis_random_burst_seq extends axis_base_seq;
    rand int unsigned num_packets = 10;

    `uvm_object_utils(axis_random_burst_seq)

    constraint c_num_packets {
        soft num_packets inside {[5:20]};
    }

    function new(string name = "axis_random_burst_seq");
        super.new(name);
    endfunction

    virtual task body();
        axis_seq_item req;
        `uvm_info("SEQ_START", $sformatf("Executing Random Burst Sequence (0%d packets)", num_packets), UVM_LOW)

        for (int i = 0; i < num_packets; i++) begin
            req = axis_seq_item::type_id::create("req");
            start_item(req);

            if (!req.randomize() with {
                burst_len inside {[4:32]};
                packet_delay inside {[1:5]};
            }) begin
                `uvm_fatal("SEQ_RAND_FAIL", "Randomization failed for burst item!")
            end

            `uvm_info("SEQ_ITEM", $sformatf("Sending Packet #%0d/%0d: %s", i+1, num_packets, req.convert2string()), UVM_HIGH)
            finish_item(req);
        end

        `uvm_info("SEQ_DONE", "Random Burst Sequence Complete", UVM_LOW)
    endtask
endclass

// ----------------------------------------------------------------------------
// 2. Short Back-to-Back Burst Sequence (Stress Test)
// ----------------------------------------------------------------------------
class axis_short_packet_seq extends axis_base_seq;
    rand int unsigned num_packets = 5;

    `uvm_object_utils(axis_short_packet_seq)

    function new(string name = "axis_short_packet_seq");
        super.new(name);
    endfunction

    virtual task body();
        axis_seq_item req;
        `uvm_info("SEQ_START", "Executing Short Back-to-Back Packet Sequence", UVM_LOW)

        for (int i = 0; i < num_packets; i++) begin
            req = axis_seq_item::type_id::create("req");
            start_item(req);

            // Force short 1 to 4-word transfers with zero inter-packet delay
            if (!req.randomize() with {
                burst_len    inside {[1:4]};
                packet_delay == 0;
            }) begin
                `uvm_fatal("SEQ_RAND_FAIL", "Randomization failed for short packet!")
            end
            finish_item(req);
        end
    endtask
endclass
