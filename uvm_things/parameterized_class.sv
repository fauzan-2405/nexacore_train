// =========================================================================
// 1. VALUE PARAMETERIZATION (Configurable Bit-Widths)
// =========================================================================
// We define default parameter values: AW = 32 (Address Width), DW = 32 (Data Width)
class bus_transaction #(int AW = 32, int DW = 32);
    rand bit [31:0] addr;
    rand bit [31:0] data;

    function new();
    endfunction

    function void display();
        $display("TX AW = %0d and TX DW = %0d Addr: 0x%0h | Data: 0x%0h", AW, DW, addr, data);
    endfunction
endclass

// =========================================================================
// 2. TYPE PARAMETERIZATION (Generic Data Structures & Components)
// =========================================================================
// Here, parameter 'type T' accepts ANY class type (e.g., transaction type).
class generic_driver #(type T = bus_transaction);
    task drive_item(T item);
        $display("\n[GENERIC DRIVER] Driving Item into interface...");
        item.display();
    endtask
endclass

// =========================================================================
// 3. TESTBENCH TOP MODULE
// =========================================================================
module parameterized_class;
    initial begin
        // A. Initiating with default parameters (AW = 32, DW = 32)
        bus_transaction #() default_tx;
        bus_transaction #(16,64) wide_tx;
        generic_driver #(bus_transaction #(16, 64)) wide_driver;
         
        default_tx  = new();
        default_tx.addr = 32'hA000_1234;
        default_tx.data = 32'hDEAD_BEEF;

        $display("--- 1. Default Parameter Transaction (32-bit) ---");
        default_tx.display();
        
        // B. Instantiating with Overriden Parameters
        wide_tx = new();
        wide_tx.addr = 16'hFFFF;
        wide_tx.data = 64'h1122_3344_5566_7788;
        
        $display("\n--- 2. Overridden Parameter Transaction (16-bit Addr / 64-bit Data) ---");
        wide_tx.display();

        // C. Instantiating a parameterized driver
        wide_driver = new();
        wide_driver.drive_item(wide_tx);
    end
endmodule