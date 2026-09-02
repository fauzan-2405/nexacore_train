# ==============================================================================
# Xilinx Design Constraints (XDC) for AXI4-Stream Asynchronous CDC FIFO Wrapper
# NexaCore Training Day 5: Constraints Migration & Physical Design (ZCU104 Target)
# ==============================================================================

# 1. Primary Clock Definitions
# Define s_axis_aclk (100 MHz, 10ns period) and m_axis_aclk (62.5 MHz, 16ns period)
create_clock -period 10.000 -name s_axis_aclk [get_ports s_axis_aclk]
create_clock -period 16.000 -name m_axis_aclk [get_ports m_axis_aclk]

# 2. Clock Groups Constraint (Asynchronous Clock Domain Isolation)
# Declares the slave (write) and master (read) clocks as completely asynchronous.
# This instructs the static timing analysis (STA) engine to ignore inter-clock path checks,
# completely removing artificial "inter-clock timing violations" from the reports.
set_clock_groups -asynchronous -group [get_clocks s_axis_aclk] -group [get_clocks m_axis_aclk]

# 3. CDC Pointer Path Constraints (set_max_delay -datapath_only)
# We must apply maximum datapath delay limits to our Gray-code pointer crossings.
# This prevents the physical router from placing the bits randomly across the 
# Zynq UltraScale+ PL fabric, bounding bus skew to avoid data synchronization errors.
#
# Bounding the delay to the destination clock period ensures the bits travel together.
# Hierarchical filters are updated to match our 'axis_wrapper' instance hierarchy.

# Path A: Write Domain Pointer -> Read Domain Synchronizer (s_axis_aclk to m_axis_aclk)
# Max delay bounded to Master Read Clock Period (16.0ns)
set_max_delay -from [get_cells -hierarchical -filter {NAME =~ *async_fifo/fifo_write_ctrl/wptr_*_reg[*]}] \
              -to [get_pins -hierarchical -filter {NAME =~ *async_fifo/sync_w2r/sync_reg_0_reg[*]/D}] \
              16.000 -datapath_only

# Path B: Read Domain Pointer -> Write Domain Synchronizer (m_axis_aclk to s_axis_aclk)
# Max delay bounded to Slave Write Clock Period (10.0ns)
set_max_delay -from [get_cells -hierarchical -filter {NAME =~ *async_fifo/fifo_read_ctrl/rptr_*_reg[*]}] \
              -to [get_pins -hierarchical -filter {NAME =~ *async_fifo/sync_r2w/sync_reg_0_reg[*]/D}] \
              10.000 -datapath_only
