# AXI-Stream FIFO: UVM Verification Environment

## Overview
One-paragraph description: the DUT (AXI-Stream FIFO with AXI-Lite control
registers), the tools used (Vivado XSim, UVM 1.2), and the goal.

## Architecture
[Block diagram: sequence -> sequencer -> driver -> DUT -> output monitor
 -> scoreboard; input monitor -> coverage; RAL model + AXI-Lite driver
 for registers]

## Verification Plan
| Feature | How it is checked |
|---|---|
| Data integrity and packet order | Scoreboard (expected from driver vs. output monitor) |
| AXI-Stream protocol rules | SVA in axis_if (hold-until-ready, no X/Z) |
| Register access and config | RAL model, frontdoor writes/reads |
| Functional scenarios | Covergroup: length, stall, mode, FIFO state, cross |

## Results
- Packets checked: ___ , mismatches: ___
- Coverage per coverpoint: len ___, stall ___, mode ___, fifo ___, cross ___
- Uncovered bins and why (for example, FIFO_FULL / BYPASS behavior)

## Bugs Found
1. Driver sent each non-last beat twice (extra clock wait after handshake).
   How I found it: ... How I fixed it: ...
2. Scoreboard counted items without comparing. Fixed by ...

## How to Run
Steps for Vivado (files, top module, simulation settings).

## Limitations / Future Work
Honest list (for example, mode field has no effect in the DUT).