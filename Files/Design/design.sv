`ifndef DESIGN_SV
`define DESIGN_SV

`timescale 1ns/1ps

`include "async_fifo.sv"
`include "data_align_ctrl.sv"
`include "systolic_array.sv"
`include "streaming_async_fifo.sv"
`include "instrumentation.sv"
// ======================================================================
// Sub-system: Data Alignment + Systolic Array + Asynchronous FIFOs
// - Input FIFO: buffers input data (sys_clk write, sr_clk read)
// - Data alignment controller: manages skewed injection (sr_clk)
// - Systolic array: performs matrix multiplication (sr_clk)
// - Output FIFO: buffers results (sr_clk write, sys_clk read)
// ======================================================================
module sub_sys #(
    parameter int DIN_WIDTH  = 8,
    parameter int N          = 4,
    // BUS_WIDTH = N elements of A column + N elements of B row
    parameter int BUS_WIDTH  = 2 * DIN_WIDTH * N,
    // Instrumentation debug enables
    parameter bit DEBUG_ENABLE = 1'b1,                 // Global debug enable
    parameter bit DEBUG_ENABLE_INPUT_FIFO = 1'b1,      // Monitor input FIFO activity
    parameter bit DEBUG_ENABLE_ALIGN_CTRL = 1'b1,      // Monitor alignment controller
    parameter bit DEBUG_ENABLE_SYSTOLIC = 1'b1,        // Monitor systolic array
    parameter bit DEBUG_ENABLE_OUTPUT_FIFO = 1'b1,     // Monitor output FIFO
    parameter bit DEBUG_ENABLE_MATRIX_RESULT = 1'b1,   // Print matrix result data
    parameter bit DEBUG_ENABLE_SUMMARY = 1'b1,         // Periodic summary prints
    parameter bit DEBUG_ENABLE_DATA_TRACE = 1'b1       // Monitor A/B matrix data flow
)(
    input  logic                        rst_n,         // active-low reset
    input  logic                        sys_clk,       // system clock for data read/write
    input  logic                        sr_clk,        // systolic array clock for computation
    input  logic [7:0]                  M_minus_one,   // M-1 for NxM and MxN matrix multiplication
    input  logic [BUS_WIDTH-1:0]        din,           // input data (one column A + one row B)
    input  logic                        wr_fifo,       // write input FIFO signal, active high
    input  logic                        rd_fifo,       // read output FIFO signal, active high
    output logic                        in_fifo_full,  // input FIFO full (active high)
    output logic [BUS_WIDTH-1:0]        dout,          // output FIFO data (N elements of C)
    output logic                        out_fifo_empty // output FIFO empty (active high)
    // Instrumentation is controlled via parameter DEBUG_ENABLE (compile-time)
);

    // ------------------------------------------------------------------
    // FIFO Depth Parameters
    // ------------------------------------------------------------------
    localparam int INPUT_FIFO_DEPTH  = 512;  // CPU side input FIFO depth
    localparam int OUTPUT_FIFO_DEPTH = 1024; // Streaming side output FIFO depth

    // ------------------------------------------------------------------
    // Input FIFO (sys_clk write, sr_clk read)
    // ------------------------------------------------------------------
    logic [BUS_WIDTH-1:0] fifo_dout;
    logic                 fifo_empty;
    logic                 fifo_rd_en;

    async_fifo #(
        .FIFO_DEPTH(INPUT_FIFO_DEPTH),
        .DATA_WIDTH(BUS_WIDTH)
    ) u_input_fifo (
        .wr_clk  (sys_clk),
        .wr_rst_n(rst_n),
        .wr_en   (wr_fifo),
        .din     (din),
        .full    (in_fifo_full),
        .rd_clk  (sr_clk),
        .rd_rst_n(rst_n),
        .rd_en   (fifo_rd_en),
        .dout    (fifo_dout),
        .empty   (fifo_empty)
    );

    // ------------------------------------------------------------------
    // M FIFO (sys_clk write, sr_clk read)
    // ------------------------------------------------------------------
    logic [7:0]          m_fifo_dout;
    logic                m_fifo_empty;
    logic                m_fifo_rd_en;

    async_fifo #(
        .FIFO_DEPTH(INPUT_FIFO_DEPTH),
        .DATA_WIDTH(8)
    ) u_m_fifo (
        .wr_clk  (sys_clk),
        .wr_rst_n(rst_n),
        .wr_en   (wr_fifo),
        .din     (M_minus_one),
        .full    (), // Not used, assuming input FIFO full covers
        .rd_clk  (sr_clk),
        .rd_rst_n(rst_n),
        .rd_en   (m_fifo_rd_en),
        .dout    (m_fifo_dout),
        .empty   (m_fifo_empty)
    );

    // ------------------------------------------------------------------
    // Systolic array outputs (internal, fed to streaming FIFO)
    // ------------------------------------------------------------------
    logic signed [2*DIN_WIDTH-1:0]      c_out_internal [0:N-1];
    logic                               sa_out_valid_internal;
    
    // ------------------------------------------------------------------
    // Backpressure signal from output FIFO
    // ------------------------------------------------------------------
    logic                               output_full_internal;


    // ------------------------------------------------------------------
    // Data align controller (read domain)
    // ------------------------------------------------------------------
    // Internal nets from aligner
    logic signed [DIN_WIDTH-1:0]       a_align [0:N-1];
    logic signed [DIN_WIDTH-1:0]       b_align [0:N-1];
    logic signed [2*DIN_WIDTH-1:0]     c_align [0:N-1];
    logic                              in_valid_align;

    data_align_ctrl #(
        .DIN_WIDTH(DIN_WIDTH),
        .N(N),
        .BUS_WIDTH(BUS_WIDTH)
    ) u_align (
        .rst_n        (rst_n),
        .clk          (sr_clk),
        .fifo_data    (fifo_dout),
        .fifo_empty   (fifo_empty),
        .fifo_rd_en   (fifo_rd_en),
        .M_fifo_empty (m_fifo_empty),
        .M_fifo_dout  (m_fifo_dout),
        .M_fifo_rd_en (m_fifo_rd_en),
        .output_stall (output_full_internal),
        .a_din        (a_align),
        .b_din        (b_align),
        .c_din        (c_align),
        .in_valid     (in_valid_align)
    );

    // ------------------------------------------------------------------
    // Systolic array
    // ------------------------------------------------------------------
    systolic_array #(
        .DIN_WIDTH(DIN_WIDTH),
        .N(N)
    ) u_sa (
        .rst_n        (rst_n),
        .clk          (sr_clk),
        .c_din        (c_align),
        .a_din        (a_align),
        .b_din        (b_align),
        .in_valid     (in_valid_align),
        .output_stall (output_full_internal),
        .c_dout       (c_out_internal),
        .out_valid    (sa_out_valid_internal)
    );

    // ------------------------------------------------------------------
    // Output FIFO (sr_clk write, sys_clk read)
    // ------------------------------------------------------------------
    streaming_async_fifo #(
        .DIN_WIDTH(DIN_WIDTH),
        .N(N),
        .FIFO_DEPTH(OUTPUT_FIFO_DEPTH),
        .BUS_WIDTH(BUS_WIDTH)
    ) u_output_fifo (
        .sa_clk      (sr_clk),
        .sa_rst_n    (rst_n),
        .c_dout      (c_out_internal),
        .sa_out_valid(sa_out_valid_internal),
        .sys_clk     (sys_clk),
        .sys_rst_n   (rst_n),
        .rd_en       (rd_fifo),
        .dout        (dout),
        .empty       (out_fifo_empty),
        .output_full (output_full_internal)
    );


    // ------------------------------------------------------------------
    // Instrumentation module instantiation
    // ------------------------------------------------------------------
    // Enable/disable different monitoring sections using parameters
    instrumentation #(
        .DIN_WIDTH(DIN_WIDTH),
        .N(N),
        .BUS_WIDTH(BUS_WIDTH),
        .DEBUG_ENABLE(DEBUG_ENABLE),
        .DEBUG_ENABLE_INPUT_FIFO(DEBUG_ENABLE_INPUT_FIFO), 
        .DEBUG_ENABLE_ALIGN_CTRL(DEBUG_ENABLE_ALIGN_CTRL),
        .DEBUG_ENABLE_SYSTOLIC(DEBUG_ENABLE_SYSTOLIC),
        .DEBUG_ENABLE_OUTPUT_FIFO(DEBUG_ENABLE_OUTPUT_FIFO),
        .DEBUG_ENABLE_MATRIX_RESULT(DEBUG_ENABLE_MATRIX_RESULT),
        .DEBUG_ENABLE_SUMMARY(DEBUG_ENABLE_SUMMARY),
        .DEBUG_ENABLE_DATA_TRACE(DEBUG_ENABLE_DATA_TRACE)
    ) u_instrumentation (
        .sys_clk                (sys_clk),
        .sr_clk                 (sr_clk),
        .rst_n                  (rst_n),
        .din                    (din),
        .wr_fifo                (wr_fifo),
        .rd_fifo                (rd_fifo),
        .in_fifo_full           (in_fifo_full),
        .dout                   (dout),
        .out_fifo_empty         (out_fifo_empty)
    );

endmodule

`endif // DESIGN_SV



