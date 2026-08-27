# ==============================================================================
# Xilinx Design Constraints (XDC) for Asynchronous CDC FIFO
# For Timing Constraints & CDC Isolation
# ==============================================================================

# 1. Primary Clock Definitions
# In this example, we use wclk (100 MHz, 10ns period) and rclk (62.5 MHz, 16ns period)
create_clock -period 10.000 -name wclk [get_ports wclk]
create_clock -period 16.000 -name rclk [get_ports rclk]

# 2. Clock Groups Constraint (Declares clock domains as completely asynchronous)
# This will prevent Vivado to analyze inter-clock paths for setup and hold,
# Also, this will eliminate the meaningless "inter-clock timing violations" from the report
set_clock_groups -asynchronous -group [get_clocks wclk] -group [get_clocks rclk]

# 3. CDC Pointer Path Constraints (set_max_delay -datapath_only)
# For Gray-code pointer crossings, we must not use "set_false_path" because it leaves
# routing delays completely unbounded, which can cause severe bus skew (data coherency errors).
# Instead, we bound the datapath delay to the destination clock period to keep bits tightly grouped.

# Path A: Write Domain Pointer -> Read Domain Synchronizer (wclk to rclk)
# Max delay bounded to Read Clock Period (16.0ns)
set_max_delay -to [get_pins -hierarchical -filter {NAME =~ *sync_w2r/sync_reg_0_reg[*]/D}] 16.000 -datapath_only

# Path B: Read Domain Pointer -> Write Domain Synchronizer (rclk to wclk)
# Max delay bounded to Write Clock Period (10.0ns)
set_max_delay -to [get_pins -hierarchical -filter {NAME =~ *sync_r2w/sync_reg_0_reg[*]/D}] 10.000 -datapath_only
