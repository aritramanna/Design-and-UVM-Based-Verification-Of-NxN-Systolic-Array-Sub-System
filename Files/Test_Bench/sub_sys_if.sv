`ifndef SUB_SYS_IF_SV
`define SUB_SYS_IF_SV

interface sub_sys_if #(
    parameter int DIN_WIDTH = 8,
    parameter int N = 4,
    parameter int BUS_WIDTH = 2 * DIN_WIDTH * N
);

    logic                   rst_n;
    logic                   sys_clk;
    logic                   sr_clk;
    logic [7:0]             M_minus_one;
    logic [BUS_WIDTH-1:0]   din;
    logic                   wr_fifo;
    logic                   rd_fifo;
    logic                   in_fifo_full;
    logic [BUS_WIDTH-1:0]   dout;
    logic                   out_fifo_empty;

    // Default Clocking block for general use (and assertions)
    default clocking cb_clk @(posedge sys_clk); endclocking

    // Optional clocking block for driver and monitor
    clocking drv_cb @(posedge sys_clk);
        default input #0 output #0;
        input   rst_n;
        input   sys_clk;
        input   sr_clk;
        output  M_minus_one;
        output  din;
        output  wr_fifo;
        output  rd_fifo;
        input   in_fifo_full;
        input   out_fifo_empty;
        input   dout;
    endclocking

    clocking mon_cb @(posedge sys_clk);
        default input #0 output #0;
        input rst_n;
        input sys_clk;
        input sr_clk;
        input M_minus_one;
        input din;
        input wr_fifo;
        input rd_fifo;
        input in_fifo_full;
        input dout;
        input out_fifo_empty;
    endclocking

    // ================================================================
    // ## Basic SVA Assertions
    // ================================================================
    
    // --- Reset Assertions ---

    // Check that during reset, the output FIFO is flagged as empty.
    property p_reset_out_fifo_empty;
        !rst_n |-> out_fifo_empty;
    endproperty
    a_reset_out_fifo_empty: assert property (p_reset_out_fifo_empty) else
        `uvm_error("SVA", "out_fifo_empty must be high during reset")

    // Check that during reset, the input FIFO is flagged as not full.
    property p_reset_in_fifo_not_full;
        !rst_n |-> !in_fifo_full;
    endproperty
    a_reset_in_fifo_not_full: assert property (p_reset_in_fifo_not_full) else
        `uvm_error("SVA", "in_fifo_full must be low during reset")

    // --- FIFO Protocol Assertions ---
    
    // Check that the driver never writes to the FIFO when it's full.
    property p_no_write_when_full;
        disable iff (!rst_n) // Only check when not in reset
        !(wr_fifo && in_fifo_full);
    endproperty
    a_no_write_when_full: assert property (p_no_write_when_full) else
        `uvm_error("SVA", "Attempted to write (wr_fifo) to a full input FIFO (in_fifo_full)")

    // Check that the driver never reads from the FIFO when it's empty.
    property p_no_read_when_empty;
        disable iff (!rst_n)
        !(rd_fifo && out_fifo_empty);
    endproperty
    a_no_read_when_empty: assert property (p_no_read_when_empty) else
        `uvm_error("SVA", "Attempted to read (rd_fifo) from an empty output FIFO (out_fifo_empty)")

    // --- Data Stability/Validity Assertions ---

    // Check that the DUT status flags are never unknown (X or Z).
    property p_status_flags_not_unknown;
        disable iff (!rst_n)
        !$isunknown({in_fifo_full, out_fifo_empty});
    endproperty
    a_status_flags_not_unknown: assert property (p_status_flags_not_unknown) else
        `uvm_error("SVA", "FIFO status flags (in_fifo_full, out_fifo_empty) are unknown")

    // Check that if the output FIFO is not empty, its data is not unknown.
    property p_dout_valid_when_not_empty;
        disable iff (!rst_n)
        !out_fifo_empty |-> !$isunknown(dout);
    endproperty
    a_dout_valid_when_not_empty: assert property (p_dout_valid_when_not_empty) else
        `uvm_error("SVA", "dout is unknown (X/Z) even though out_fifo_empty is low")

endinterface

`endif // SUB_SYS_IF_SV