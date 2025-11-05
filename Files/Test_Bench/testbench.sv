`timescale 1ns/1ps

`include "sub_sys_if.sv"
`include "systolic_if.sv"
`include "sub_sys_tb_pkg.sv"

module tb_top;

    import uvm_pkg::*;
    import sub_sys_tb_pkg::*;

    // Instantiate sub-system interface
    sub_sys_if #(
      .DIN_WIDTH(DIN_WIDTH),
        .N(N),
        .BUS_WIDTH(BUS_WIDTH)
    ) tb_if();

    // Instantiate systolic array interface
    systolic_if #(
        .DIN_WIDTH(DIN_WIDTH),
        .N(N)
    ) sa_if();

    // Connect its clock/reset to the testbench clocks so monitors see correct timing
    assign sa_if.clk = tb_if.sr_clk;
    assign sa_if.rst_n = tb_if.rst_n;

    // Sub-System DUT instantiation

    sub_sys #(
        // Design Parameters
        .DIN_WIDTH(DIN_WIDTH),
        .N(N),
        .BUS_WIDTH(BUS_WIDTH),
        // Instrumentation debug enables
        .DEBUG_ENABLE(DEBUG_ENABLE),
        .DEBUG_ENABLE_INPUT_FIFO(DEBUG_ENABLE_INPUT_FIFO),
        .DEBUG_ENABLE_ALIGN_CTRL(DEBUG_ENABLE_ALIGN_CTRL),
        .DEBUG_ENABLE_SYSTOLIC(DEBUG_ENABLE_SYSTOLIC),
        .DEBUG_ENABLE_OUTPUT_FIFO(DEBUG_ENABLE_OUTPUT_FIFO),
        .DEBUG_ENABLE_MATRIX_RESULT(DEBUG_ENABLE_MATRIX_RESULT),
        .DEBUG_ENABLE_SUMMARY(DEBUG_ENABLE_SUMMARY),
        .DEBUG_ENABLE_DATA_TRACE(DEBUG_ENABLE_DATA_TRACE)
    ) dut (
        .rst_n         (tb_if.rst_n),
        .sys_clk       (tb_if.sys_clk),
        .sr_clk        (tb_if.sr_clk),
        .M_minus_one   (tb_if.M_minus_one),
        .din           (tb_if.din),
        .wr_fifo       (tb_if.wr_fifo),
        .rd_fifo       (tb_if.rd_fifo),
        .in_fifo_full  (tb_if.in_fifo_full),
        .dout          (tb_if.dout),
        .out_fifo_empty(tb_if.out_fifo_empty)
    );

    // Clock and reset generation

    // Initialize clocks
    initial tb_if.sys_clk = 1'b0;
    initial tb_if.sr_clk = 1'b0;
  
    initial begin
        forever #(SYS_CLK_PERIOD/2) tb_if.sys_clk = ~tb_if.sys_clk; 
    end
  
    initial begin
        forever #(SR_CLK_PERIOD/2) tb_if.sr_clk = ~tb_if.sr_clk; 
    end

    initial begin
        tb_if.rst_n = 1'b0;
        tb_if.M_minus_one = 8'b011;
        tb_if.din = '0;
        tb_if.wr_fifo = 1'b0;
        tb_if.rd_fifo = 1'b0;
        `uvm_info("TB_TOP", "Asserting reset", UVM_LOW)
        repeat (5) @(posedge tb_if.sys_clk);
        tb_if.rst_n = 1'b1;
    end

    // Print clock configuration information and start test
    initial begin
        // Configure time format to show ns with 2 decimal places
        $timeformat(-9, 2, " ns", 20);
        
        // Print testbench configuration header
        $display("\n=== Systolic Array Testbench Configuration ===");
        $display("Time: %0t", $time);
        $display("Clock Settings:");
        $display("  System Clock (sys_clk):");
        $display("    Period    : %0.2f ns", SYS_CLK_PERIOD);
        $display("    Frequency : %0.2f MHz", 1000.0/SYS_CLK_PERIOD);
        $display("  Systolic Array Clock (sr_clk):");
        $display("    Period    : %0.2f ns", SR_CLK_PERIOD);
        $display("    Frequency : %0.2f MHz", 1000.0/SR_CLK_PERIOD);
        $display("  Clock Ratio : %0.2f (sr_clk:sys_clk)", CLK_RATIO);
        $display("==========================================\n");

        // Register the virtual interface with uvm_config_db
        uvm_config_db#(virtual sub_sys_if #(DIN_WIDTH, N, BUS_WIDTH))::set(
            null,
            "*",
            "vif",
            tb_if
        );

        // Register the systolic array virtual interface with uvm_config_db
        uvm_config_db#(virtual systolic_if #(DIN_WIDTH, N))::set(
            null,
            "*",
            "sa_vif",
            sa_if
        );

        // Start the test
        $display("=== Starting Test at Time: %0t ===", $time);
        run_test("test");
    end
 
    // Capture VCD dump
    initial begin
        $dumpfile("systolic_array_tb.vcd");
        $dumpvars(0, tb_top.dut);
    end

endmodule





