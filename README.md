# NxN Systolic Array Sub-System (RTL + UVM Verification)

This repository contains a parameterizable, cycle-accurate SystemVerilog implementation of an NxN systolic array for matrix multiplication. The design includes FIFO-based clock domain crossing, a data alignment controller for skewed injection of matrix elements, and a streaming output stage. A complete UVM testbench is provided to verify functionality, latency, flow control, and corner cases.

EDA Playground: https://www.edaplayground.com/x/Jk8s

## Design Overview
- Fully synthesizable RTL (except queue-based FIFO used for simulation)
- Configurable `N`, `DIN_WIDTH`, and FIFO depth
- Packed input/output buses for streaming matrix rows and columns
- Asynchronous `sys_clk` ↔ `sr_clk` clock domain crossing
- Data alignment controller schedules skewed A/B matrix injection
- Output FIFO streams one result row per cycle

<img width="560" height="286" alt="image" src="https://github.com/user-attachments/assets/40cb9514-88c8-4193-9552-244303c81e18" />


**RTL Sources**
design.sv – Top-level sub-system
systolic_array.sv – NxN processing grid
pe.sv – Processing element
data_align_ctrl.sv – Skewed input scheduler
async_fifo.sv – CDC using SV queues
streaming_async_fifo.sv – Output queue controller
instrumentation.sv – Optional debug/trace

## UVM Testbench
The verification environment checks both the external interface and the internal systolic array results.

<img width="453" height="396" alt="image" src="https://github.com/user-attachments/assets/0e05051a-694f-4b95-8f38-9b24653b5e9a" />


- Constrained-random matrix stimulus (seq + seq_item)
- Scoreboard with golden model comparison
- Dual monitors:
  - Top-level I/O (black-box view)
  - Internal systolic array outputs (white-box view)
- Assertions for FIFO protocol and reset behavior
- Automatic pass/fail reporting and end-of-test checks

**Testbench Sources**
tb_top.sv, config.sv, env.sv, agent.sv, driver.sv,
monitor.sv, scoreboard.sv, seq_item.sv, sequence.sv

## Latency Summary (Array Only)
First result row after in_valid : 2N − 1 cycles
Last result row after in_valid : 3N − 2 cycles

<img width="542" height="218" alt="image" src="https://github.com/user-attachments/assets/72c7bbd5-b336-4152-9e03-64961c9caee1" />

<img width="338" height="328" alt="image" src="https://github.com/user-attachments/assets/40a78764-6d71-4b32-9608-0ade610da0c4" />



## Supported Test Scenarios
- Single multiply (M=1)
- Accumulation across multiple packets
- Zero and identity matrices
- Output never read (stall and backpressure)
- Input burst and random pacing
- Asynchronous clock ratios (fast→slow, slow→fast, non-integer)
- Reset during input or output

## Running a Simulation (example)
vlog design/.sv tb/.sv
vsim -c tb_top -do "run -all"

Expected result:
Subsystem check passed
Systolic array check passed
Overall test passed

## Known Issues
- Some configurations fail when `M != N` or at larger N values
- FIFO uses SV queues; real hardware should use gray-code pointers

## Author
Aritra Manna
