`ifndef SYSTOLIC_IF_SV
`define SYSTOLIC_IF_SV

`include "dut_hier_defines.sv"

interface systolic_if #(
    parameter int DIN_WIDTH = 8,
    parameter int N = 4
);

    // Clocks & reset
    logic rst_n;
    logic clk;

    // Inputs to the array (driven by parent: aligner)
    logic signed [2*DIN_WIDTH-1:0] c_din [0:N-1];
    logic signed [DIN_WIDTH-1:0]   a_din [0:N-1];
    logic signed [DIN_WIDTH-1:0]   b_din [0:N-1];
    logic                          in_valid;
    logic                          output_stall;

    // Outputs from the array (driven by array)
    logic signed [2*DIN_WIDTH-1:0] c_dout [0:N-1];
    logic                          out_valid;

    // Hierarchical access to systolic dut i/o signals
    assign c_din        = `DUT_HIER.u_sa.c_din;
    assign a_din        = `DUT_HIER.u_sa.a_din;
    assign b_din        = `DUT_HIER.u_sa.b_din;
    assign in_valid     = `DUT_HIER.u_sa.in_valid;
    assign output_stall = `DUT_HIER.u_sa.output_stall;
    assign c_dout       = `DUT_HIER.u_sa.c_dout;
    assign out_valid    = `DUT_HIER.u_sa.out_valid;

    // Default clocking block for general use
    default clocking cb_clk @(posedge clk); endclocking

    // Driver clocking block
    clocking drv_cb @(posedge clk);
        default input #1step output #0;
        // No outputs as signals are driven by assigns
    endclocking

    // Monitor clocking block
    clocking mon_cb @(posedge clk);
        default input #1step output #0;
        input rst_n;
        input clk;
        input c_din;
        input a_din;
        input b_din;
        input in_valid;
        input c_dout;
        input out_valid;
    endclocking

endinterface

`endif // SYSTOLIC_IF_SV
