`ifndef SUB_SYS_TB_PKG_SV
`define SUB_SYS_TB_PKG_SV

package sub_sys_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "dut_hier_defines.sv"

    // Design parameters
    parameter int DIN_WIDTH  = 8;                      // Data input width
    parameter int N          = 4;                      // Systolic array dimension
    parameter int BUS_WIDTH  = 2 * DIN_WIDTH * N;      // Data bus width
    
    // Clock parameters
    parameter real BASE_CLK_PERIOD = 10.0;            // Base clock period (sys_clk, 100MHz)
    parameter real CLK_RATIO = 0.6;                   // sr_clk:sys_clk ratio (systolic runs faster)
    // Derived clock periods
parameter real SYS_CLK_PERIOD = BASE_CLK_PERIOD* CLK_RATIO;  // System clock period (166.67Hz)
    parameter real SR_CLK_PERIOD  = BASE_CLK_PERIOD;         // Systolic array clock (100MHz)
    // Instrumentation debug enables
    parameter bit DEBUG_ENABLE = 1'b0;                 // Global debug enable
    parameter bit DEBUG_ENABLE_INPUT_FIFO = 1'b1;      // Monitor input FIFO activity
    parameter bit DEBUG_ENABLE_ALIGN_CTRL = 1'b1;      // Monitor alignment controller
    parameter bit DEBUG_ENABLE_SYSTOLIC = 1'b1;        // Monitor systolic array
    parameter bit DEBUG_ENABLE_OUTPUT_FIFO = 1'b1;     // Monitor output FIFO
    parameter bit DEBUG_ENABLE_MATRIX_RESULT = 1'b1;   // Print matrix result data
    parameter bit DEBUG_ENABLE_SUMMARY = 1'b0;         // Periodic summary prints
    parameter bit DEBUG_ENABLE_DATA_TRACE = 1'b1;      // Monitor A/B matrix data flow
 
    // Local Parameters for value ranges
    localparam int OP_MIN  = -(1 << (DIN_WIDTH - 1));
    localparam int OP_MAX  = (1 << (DIN_WIDTH - 1)) - 1;
    localparam int RES_MIN = -(1 << (2*DIN_WIDTH - 1));
    localparam int RES_MAX = (1 << (2*DIN_WIDTH - 1)) - 1;

    `include "resp_item.sv"
    `include "seq_item.sv"
    `include "systolic_resp_item.sv"
    `include "config.sv"
    `include "scoreboard.sv"
    `include "sequence.sv"
    `include "driver.sv"
    `include "monitor.sv"
    `include "agent.sv"
    `include "env.sv"
    `include "test.sv"

endpackage

`endif // SUB_SYS_TB_PKG_SV