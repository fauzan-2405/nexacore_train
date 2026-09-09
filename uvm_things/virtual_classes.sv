// =========================================================================
// 1. THE ABSTRACT BASE CLASS
// =========================================================================
// The 'virtual' keyword makes this class abstract.
virtual class transaction_base;
    string inst_name;

    // We cannot directly instantiate 'transaction_base' (i.e. 'new' will fail).
    // It exists only to act as a common contract/blueprint for derived classes
    function new(string name);
        this.inst_name = name;
    endfunction

    // A standard virtual method. Subclasses can choose to override this.
    // It provides a default implemenation
    virtual function void display();
        $display("[BASE] Transaction Instance: %s", inst_name);
    endfunction

    // A 'pure virtual' method. There is NO function's body here
    // It will force any concrete child class to implement its own version
    pure virtual function bit [31:0] get_payload(); 
endclass


// =========================================================================
// 2. THE CONCRETE SUBCLASS
// =========================================================================
// We can extend the virtual base class to implement specific behavior we need.
class write_transaction extends transaction_base;
    bit [31:0] addr;
    bit [31:0] data;

    function new(string name, bit [31:0] a, bit [31:0] d);
        super.name(name);   // Call parent class constructor
        this.addr = a;
        this.data = d;
    endfunction

    // Overriding the base display() method
    virtual function void display();
        $display("[WRITE] Name: %s | Addr: 0x%8h | Data: 0x%8h", inst_name, addr, data);
    endfunction

    // Implementing the pure virtual method required by the parent class contract
    virtual function bit [31:0] get_payload();
        return data;
    endfunction
endclass 

// =========================================================================
// 3. THE POLYMORPHIC EXECUTION ENGINE
// =========================================================================
module virtual_classes;
    initial begin
        // transaction_base base_obj;
        // base_obj = new("base_inst"); <-- COMPILER ERROR: Cannot instantiate virtual class

        transaction_base base_h;    // Declare a base class handle (a generic pointer)
        write_transaction write_h;  // Declare a derived class handle

        // 1. Create the concrete child object
        write_h = new("Write_Tx_0", 32'h0000_A000, 32'hDEAD_BEEF);

        // 2. Point the base handle to the subclass subject
        // This is legal because a write_transaction "is a" transaction_base.
        base_h = write_h;

        // 3. Dynamic Dispatch (Polymorphism)
        // Even though 'base_h' is a base handle, calling display() will call the derived subclass
        // instead because we already overwrote the display() function
        $display("\n--- Calling display() via parent class handle ---");
        base_h.display();

        // Calling the implemented pure virtual function
        $display("Payload returned: 0x%8h\n", base_h.get_payload())
    end
endmodule