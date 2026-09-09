// =========================================================================
// 1. BASE CLASS AND DERIVED CLASSES
// =========================================================================
virtual class transaction_base_casting;
  string inst_name;
  function new(string name);
    this.inst_name = name;
  endfunction
endclass

class write_transaction_casting extends transaction_base_casting;
  bit [31:0] addr;
  bit [31:0] data;

  function new(string name, bit [31:0] a, bit [31:0] d);
    super.new(name);
    this.addr = a;
    this.data = d;
  endfunction

  // Subclass-specific method (NOT in transaction_base)
  function void print_write_details();
    $display("[WRITE TX] Addr: 0x%8h | Data: 0x%8h", addr, data);
  endfunction
endclass

class read_transaction_casting extends transaction_base_casting;
  bit [31:0] addr;

  function new(string name, bit [31:0] a);
    super.new(name);
    this.addr = a;
  endfunction
endclass

// =========================================================================
// 2. DEMONSTRATING UPCASTING vs DOWNCASTING ($cast)
// =========================================================================
module casting;
  initial begin
    transaction_base_casting base_h;       // Base class handle
    write_transaction_casting write_orig;  // Original child object handle
    write_transaction_casting write_cast;  // Target child handle for downcasting
    read_transaction_casting  read_orig;   // Different child object type

    // Step 1: Create a concrete write_transaction_casting object
    write_orig = new("Write_0", 32'h0000_1000, 32'hAAAA_BBBB);

    // ---------------------------------------------------------------------
    // UPCASTING (Implicit & Safe)
    // ---------------------------------------------------------------------
    // Assigning a child handle to a parent handle is always allowed.
    base_h = write_orig; 
    $display("Upcasting successful! Base handle now points to Write_0.");

    // Question: Can we access 'addr' or 'print_write_details()' using base_h?
    // base_h.print_write_details(); 
    // ^ COMPILER ERROR: 'print_write_details' is not a member of 'transaction_base'.
    // Even though the underlying object in memory is a write_transaction_casting,
    // the compiler only sees the transaction_base type of base_h.

    // ---------------------------------------------------------------------
    // DOWNCASTING WITHOUT $cast (Illegal)
    // ---------------------------------------------------------------------
    // write_cast = base_h; 
    // ^ COMPILER ERROR: Assignment to type 'write_transaction_casting' from type 
    // 'transaction_base' is illegal without a dynamic cast ($cast).

    // ---------------------------------------------------------------------
    // DOWNCASTING WITH $cast (Legal & Safe)
    // ---------------------------------------------------------------------
    // Syntax: $cast(destination_handle, source_handle)
    // Returns 1 on success, 0 on failure.
    if ($cast(write_cast, base_h)) begin
      $display("\n[SUCCESS] $cast succeeded!");
      // Now we can access write_transaction_casting-specific methods and properties!
      write_cast.print_write_details();
    end else begin
      $error("[FAILED] $cast failed!");
    end

    // ---------------------------------------------------------------------
    // DEMONSTRATING A FAILED $cast (Runtime Safety Check)
    // ---------------------------------------------------------------------
    read_orig = new("Read_0", 32'h0000_2000);
    base_h = read_orig; // Upcast read_transaction_casting into base handle

    // Try downcasting a handle holding a read_transaction_casting into a write_transaction_casting handle
    $display("\nAttempting invalid cast (read_transaction_casting object -> write_transaction_casting handle)...");
    if ($cast(write_cast, base_h)) begin
      $display("[SUCCESS] Unexpected cast success!");
    end else begin
      $display("[SAFE FAIL] $cast failed gracefully! Handle types in memory do not match.");
    end
  end
endmodule