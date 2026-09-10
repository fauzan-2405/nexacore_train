// =====================================================================
// 1. NESTED OBJECT CLASS
// =====================================================================
class header_info;
    int stream_id;

    function new(int id);
        this.stream_id = id;
    endfunction

    // Helper method to perform deep copy of the nested object
    function header_info copy();
        header_info new_hdr = new(this.stream_id);
        return new_hdr;
    endfunction
endclass

// ======================================================================
// 2. MAIN TRANSACTION CLASS (CONTAINING NESTED OBJECT)
// ======================================================================
class packet;
    bit [31:0] data;
    header_info hdr; // Handle to a nested class object

    function new(bit [31:0] d, int id);
        this.data = d;
        this.hdr  = new(id);    // Instantiate nested object
    endfunction

    function void display(string name);
        $display("[%s] Data: 0x%8h | Header Stream ID: %0d", name, data, hdr.stream_id);
    endfunction

    // Custom Deep Copy Function
    function void copy(packet rhs);
        if (rhs == null) return;
        this.data = rhs.data;            // Copy primitive data
        this.hdr  = rhs.hdr.copy();      // Deep copy the nested object!
    endfunction
endclass

// ======================================================================
// 3. TESTBENCH TOP MODULE
// ======================================================================
module copy_demo;
    initial begin
        packet p1, p2_shallow, p3_deep;

        // Create original packet
        p1 = new(32'hDEAD_BEEF, 101);
        $$display("--- Initial Packet (p1) ---");
        p1.display("P1 Origirnal");

        // ---------------------------------------------------------------------
        // A. SHALLOW COPY DEMO (p2_shallow = new p1)
        // ---------------------------------------------------------------------
        $$display("\n--- 1. Performing Shallow Copy (p2_shallow = new p1) ---");
        p2_shallow = new p1; // SystemVerilog Shallow Copy operator

        // Modify p2_shallow
        p2_shallow.data = 32'h1111_2222;    // Modifying primitive field
        p2_shallow.hdr.stream_id = 999;     // Modifying nested object field

        // Check the result:
        p2_shallow.display("P2 Shallow");
        p1.display.display("P1 After Shallow Mod");

        // Notice that p1's primitive data (DEAD_BEEF) remained untouched,
        // BUT p1's stream_id was corrupted to 999 because both handles share the SAME header object
        
        // ---------------------------------------------------------------------
        // B. DEEP COPY DEMO (p3_deep.copy(p1))
        // ---------------------------------------------------------------------
        $display("\n--- 2. Performing Deep Copy (p3_deep.copy(p1)) ---");
        p1.hdr.stream_id = 101; // Reset p1 stream_id

        p3_deep = new(32'h8888_9999);
        p3_deep.hdr.stream_id = 555;
    
        // Check the results:
        p3_deep.display("P3 Deep");
        p1.display("P1 After Deep Mod");

        // Notice that p1's stream_id remains 101! P3 is 100% independent.
    end
endmodule
