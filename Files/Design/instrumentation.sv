`ifndef INSTRUMENTATION_SV
`define INSTRUMENTATION_SV

`include "dut_hier_defines.sv"

// ======================================================================
// Instrumentation Module for sub_sys Design
// Provides detailed monitoring and debug signals from internal interfaces
// Monitors: Input FIFO, Alignment Controller, Systolic Array, Output FIFO
// ======================================================================
module instrumentation #(
    parameter int DIN_WIDTH = 8,
    parameter int N = 4,
    parameter int BUS_WIDTH = 2 * DIN_WIDTH * N,
    // Global and per-section debug enables
    parameter bit DEBUG_ENABLE = 1'b1,                 // Global debug enable
    parameter bit DEBUG_ENABLE_INPUT_FIFO = 1'b1,      // Monitor input FIFO activity
    parameter bit DEBUG_ENABLE_ALIGN_CTRL = 1'b1,      // Monitor alignment controller
    parameter bit DEBUG_ENABLE_SYSTOLIC = 1'b1,        // Monitor systolic array
    parameter bit DEBUG_ENABLE_OUTPUT_FIFO = 1'b1,     // Monitor output FIFO
    parameter bit DEBUG_ENABLE_MATRIX_RESULT = 1'b1,   // Print matrix result data
    parameter bit DEBUG_ENABLE_SUMMARY = 1'b1,         // Periodic summary prints
    parameter bit DEBUG_ENABLE_DATA_TRACE = 1'b1       // Monitor A/B matrix data flows
)(
    // Control signals
    // instrumentation controlled at compile/instantiation time via DEBUG_ENABLE

    // Clocks and resets
    input  logic                        sys_clk,
    input  logic                        sr_clk,
    input  logic                        rst_n,
    
    // Top-level interface signals (for reference and monitoring)
    input  logic [BUS_WIDTH-1:0]        din,
    input  logic                        wr_fifo,
    input  logic                        rd_fifo,
    input  logic                        in_fifo_full,
    input  logic [BUS_WIDTH-1:0]        dout,
    input  logic                        out_fifo_empty
);
    // Hierarchical access to internal signals via $parent

    // Internal signals for state name conversion
    string align_state_name;
    string sa_state_name;
    string out_fifo_state_name;
    
    // Previous values for change detection
    logic [2:0]                  prev_align_state;
    logic [1:0]                  prev_sa_state;
    logic [1:0]                  prev_out_fifo_state;
    logic                        prev_sa_flush;
    logic                        prev_align_in_valid;
    logic                        prev_sa_out_valid;
    logic                        prev_in_fifo_full;
    logic                        prev_out_fifo_empty;
    logic                        prev_align_fifo_empty;
    logic                        prev_out_fifo_full;
    
    // Edge detection
    logic                        align_in_valid_edge;
    logic                        sa_out_valid_edge;
    logic                        sa_flush_edge;

    // ------------------------------------------------------------------
    // Signals moved out of procedural blocks (continuous/externally driven)
    // ------------------------------------------------------------------
    // sys_clk domain
    logic [31:0]                 input_fifo_depth_local; // updated in sys_clk procedural monitor

    // sr_clk / hierarchical snapshot signals (logic driven by always_comb)
    logic [2:0]                  align_state_local;
    logic [7:0]                  align_load_cnt_local;
    logic [7:0]                  align_inject_cycle_local;
    logic [7:0]                  align_capture_idx_local;
    logic [$clog2(2*N):0]        align_sa_complete_local;
    logic                        align_output_stall_local;
    logic                        align_in_valid_local;
    logic                        align_fifo_empty_local;
    logic                        align_fifo_rd_en_local;
    logic [BUS_WIDTH-1:0]        align_fifo_data_local;
    logic signed [DIN_WIDTH-1:0] align_a_din_local [0:N-1];
    logic signed [DIN_WIDTH-1:0] align_b_din_local [0:N-1];
    logic signed [2*DIN_WIDTH-1:0] align_c_din_local [0:N-1];
    logic [1:0]                  sa_state_local;
    logic [$clog2(N)-1:0]        sa_row_idx_local;
    logic                        sa_flush_local;
    logic [$clog2(2*N):0]        sa_valid_count_local;
    logic                        sa_output_stall_local;
    logic                        sa_out_valid_local;
    logic signed [2*DIN_WIDTH-1:0] sa_c_dout_local [0:N-1];
    logic [1:0]                  out_fifo_state_local;
    logic [$clog2(N)-1:0]        out_fifo_stream_cnt_local;
    logic                        out_fifo_full_local;
    logic                        out_fifo_wr_en_local;
    logic                        out_fifo_empty_internal_local;

    // ======================================================================
    // State name conversion functions
    // ======================================================================
    function string get_align_state_name(logic [2:0] state_val);
        case (state_val)
            3'b000: return "IDLE";
            3'b001: return "LOAD_REQ";
            3'b010: return "LOAD_CAPTURE";
            3'b011: return "INJECT";
            default: return "UNKNOWN";
        endcase
    endfunction

    function string get_sa_state_name(logic [1:0] state_val);
        case (state_val)
            2'b00: return "IDLE";
            2'b01: return "STREAM";
            default: return "UNKNOWN";
        endcase
    endfunction

    function string get_out_fifo_state_name(logic [1:0] state_val);
        case (state_val)
            2'b00: return "IDLE";
            2'b01: return "STREAMING";
            default: return "UNKNOWN";
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Continuous assignments mapping module-scope snapshot signals to
    // hierarchical sources ($parent). This avoids declaring signals
    // inside procedural blocks while keeping snapshots current.
    // ------------------------------------------------------------------
    // sys_clk domain: FIFO depth is computed inside the sys_clk procedural monitor

    // Drive snapshot logic signals from DUT hierarchy using a combinational block
    // (replaces previous continuous assigns but keeps single-source drive)
    always_comb begin
        // Alignment controller signals
    align_state_local        = `DUT_HIER.u_align.state;
    align_load_cnt_local     = `DUT_HIER.u_align.load_cnt;
    align_inject_cycle_local = `DUT_HIER.u_align.inject_cycle;
    align_capture_idx_local  = `DUT_HIER.u_align.capture_idx;
    align_sa_complete_local  = `DUT_HIER.u_align.sa_complete_count;
    align_output_stall_local = `DUT_HIER.output_full_internal;
    align_in_valid_local     = `DUT_HIER.in_valid_align;
    align_fifo_empty_local   = `DUT_HIER.fifo_empty;
    align_fifo_rd_en_local   = `DUT_HIER.fifo_rd_en;
    align_fifo_data_local    = `DUT_HIER.fifo_dout;

        // Systolic array signals
    sa_state_local           = `DUT_HIER.u_sa.state;
    sa_row_idx_local         = `DUT_HIER.u_sa.row_idx;
    sa_flush_local           = `DUT_HIER.u_sa.flush;
    sa_valid_count_local     = `DUT_HIER.u_sa.valid_count;
    sa_output_stall_local    = `DUT_HIER.output_full_internal;
    sa_out_valid_local       = `DUT_HIER.sa_out_valid_internal;

        // Output FIFO signals
    out_fifo_state_local     = `DUT_HIER.u_output_fifo.state;
    out_fifo_stream_cnt_local= `DUT_HIER.u_output_fifo.stream_count;
    out_fifo_full_local      = `DUT_HIER.u_output_fifo.fifo_full;
    out_fifo_wr_en_local     = `DUT_HIER.u_output_fifo.fifo_wr_en;
    out_fifo_empty_internal_local = out_fifo_empty;

        // Per-element arrays
        for (int gi = 0; gi < N; gi++) begin
            align_a_din_local[gi] = `DUT_HIER.a_align[gi];
            align_b_din_local[gi] = `DUT_HIER.b_align[gi];
            align_c_din_local[gi] = `DUT_HIER.c_align[gi];
            sa_c_dout_local[gi]   = `DUT_HIER.c_out_internal[gi];
        end
    end

    // ======================================================================
    // Monitor on sys_clk (Input FIFO domain)
    // ======================================================================
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_in_fifo_full <= 1'b0;
            prev_out_fifo_empty <= 1'b1;
    end else if (DEBUG_ENABLE) begin
            // Print input FIFO activity on significant events
            if (DEBUG_ENABLE && DEBUG_ENABLE_INPUT_FIFO && (wr_fifo || (in_fifo_full != prev_in_fifo_full))) begin
                input_fifo_depth_local = `DUT_HIER.u_input_fifo.dataQ.size();
                $write("[%0t] [SYS_CLK] [INPUT_FIFO] ", $time);
                $write("WR=%0d FULL=%0d EMPTY=%0d DEPTH=%0d/%0d", 
                       wr_fifo, in_fifo_full, !in_fifo_full, 
                       input_fifo_depth_local, 512);
                if (wr_fifo && in_fifo_full) begin
                    $write(" [WARNING: Write while full!]");
                end
                $display("");
                
                // Print input data when written to FIFO
                if (DEBUG_ENABLE && DEBUG_ENABLE_INPUT_FIFO && DEBUG_ENABLE_DATA_TRACE && wr_fifo && !in_fifo_full) begin
                    $write("[%0t] [SYS_CLK] [INPUT_DATA] Writing to FIFO: A_col=[", $time);
                    for (int idx = 0; idx < N; idx++) begin
                        $write("%0d", $signed(din[idx*DIN_WIDTH +: DIN_WIDTH]));
                        if (idx < N - 1) $write(", ");
                    end
                    $write("] B_row=[");
                    for (int idx = 0; idx < N; idx++) begin
                        $write("%0d", $signed(din[(N*DIN_WIDTH) + idx*DIN_WIDTH +: DIN_WIDTH]));
                        if (idx < N - 1) $write(", ");
                    end
                    $display("]");
                end
            end
            
            // Print output FIFO read activity
            if (DEBUG_ENABLE && DEBUG_ENABLE_OUTPUT_FIFO && (rd_fifo || (out_fifo_empty != prev_out_fifo_empty))) begin
                $write("[%0t] [SYS_CLK] [OUTPUT_FIFO_RD] ", $time);
                $write("RD=%0d EMPTY=%0d", rd_fifo, out_fifo_empty);
                if (rd_fifo && out_fifo_empty) begin
                    $write(" [WARNING: Read while empty!]");
                end
                $display("");
                
                // Print the actual matrix row data when read is successful
                if (DEBUG_ENABLE && DEBUG_ENABLE_OUTPUT_FIFO && DEBUG_ENABLE_MATRIX_RESULT && rd_fifo && !out_fifo_empty) begin
                    $write("[%0t] [SYS_CLK] [MATRIX_RESULT] Row data: [", $time);
                    for (int idx = 0; idx < N; idx++) begin
                        $write("%0d", $signed(dout[idx*(2*DIN_WIDTH) +: (2*DIN_WIDTH)]));
                        if (idx < N - 1) $write(", ");
                    end
                    $display("]");
                end
            end
            
            // Update previous values
            prev_in_fifo_full <= in_fifo_full;
            prev_out_fifo_empty <= out_fifo_empty;
        end
    end

    // ======================================================================
    // Monitor on sr_clk (SA domain: Alignment, SA, Output FIFO write)
    // ======================================================================
    always_ff @(posedge sr_clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_align_state        <= 3'b0;
            prev_sa_state          <= 2'b0;
            prev_out_fifo_state    <= 2'b0;
            prev_sa_flush          <= 1'b0;
            prev_align_in_valid    <= 1'b0;
            prev_sa_out_valid      <= 1'b0;
            prev_align_fifo_empty  <= 1'b1;
            prev_out_fifo_full     <= 1'b0;
    end else if (DEBUG_ENABLE) begin
            // Hierarchical signal snapshots are provided via continuous assigns
            // (module-scope signals updated by assign statements). No local
            // declarations or procedural hierarchical reads here.
            
            // Update state names
            align_state_name = get_align_state_name(align_state_local);
            sa_state_name = get_sa_state_name(sa_state_local);
            out_fifo_state_name = get_out_fifo_state_name(out_fifo_state_local);
            
            // Edge detection
            align_in_valid_edge = align_in_valid_local && !prev_align_in_valid;
            sa_out_valid_edge = sa_out_valid_local && !prev_sa_out_valid;
            sa_flush_edge = sa_flush_local && !prev_sa_flush;
            
            // Print when state changes
            if (DEBUG_ENABLE && DEBUG_ENABLE_ALIGN_CTRL && align_state_local != prev_align_state) begin
                $write("[%0t] [SR_CLK] [ALIGN_CTRL] STATE: %s -> %s", 
                       $time, get_align_state_name(prev_align_state), align_state_name);
                $write(" | LOAD_CNT=%0d INJECT_CYCLE=%0d CAPTURE_IDX=%0d", 
                       align_load_cnt_local, align_inject_cycle_local, align_capture_idx_local);
                $write(" | SA_COMPLETE=%0d OUTPUT_STALL=%0d", 
                       align_sa_complete_local, align_output_stall_local);
                $display("");
            end
            
            // Print on in_valid edge
            if (DEBUG_ENABLE && DEBUG_ENABLE_ALIGN_CTRL && align_in_valid_edge) begin
                $write("[%0t] [SR_CLK] [ALIGN_CTRL] ", $time);
                $display("*** in_valid PULSE *** (Data injection to SA started)");
            end
            
            // Print alignment activity
            if (DEBUG_ENABLE && DEBUG_ENABLE_ALIGN_CTRL && (align_fifo_rd_en_local || (align_fifo_empty_local != prev_align_fifo_empty))) begin
                $write("[%0t] [SR_CLK] [ALIGN_CTRL] FIFO_RD=%0d FIFO_EMPTY=%0d", 
                       $time, align_fifo_rd_en_local, align_fifo_empty_local);
                $display("");
            end
            
            // Print data alignment - when FIFO data is read
            if (DEBUG_ENABLE && DEBUG_ENABLE_ALIGN_CTRL && DEBUG_ENABLE_DATA_TRACE && align_fifo_rd_en_local) begin
                $write("[%0t] [SR_CLK] [ALIGN_DATA] FIFO_DATA (idx=%0d): A_col=[", 
                       $time, align_capture_idx_local);
                for (int idx = 0; idx < N; idx++) begin
                    $write("%0d", $signed(align_fifo_data_local[idx*DIN_WIDTH +: DIN_WIDTH]));
                    if (idx < N - 1) $write(", ");
                end
                $write("] B_row=[");
                for (int idx = 0; idx < N; idx++) begin
                    $write("%0d", $signed(align_fifo_data_local[(N*DIN_WIDTH) + idx*DIN_WIDTH +: DIN_WIDTH]));
                    if (idx < N - 1) $write(", ");
                end
                $display("]");
            end
            
            // Print skewed injection pattern during INJECT state (print every few cycles)
            if (DEBUG_ENABLE && DEBUG_ENABLE_ALIGN_CTRL && DEBUG_ENABLE_DATA_TRACE && align_state_local == 3'b011 && !align_output_stall_local) begin
                // Print every 2 cycles to show pattern without too much output
                if (align_inject_cycle_local % 2 == 0) begin
                    $write("[%0t] [SR_CLK] [ALIGN_DATA] INJECT cycle=%0d: ", $time, align_inject_cycle_local);
                    $write("A_din=[");
                    for (int idx = 0; idx < N; idx++) begin
                        if (align_a_din_local[idx] != 0) begin
                            $write("idx%0d:%0d ", idx, align_a_din_local[idx]);
                        end else begin
                            $write("  -  ");
                        end
                    end
                    $write("] B_din=[");
                    for (int idx = 0; idx < N; idx++) begin
                        if (align_b_din_local[idx] != 0) begin
                            $write("idx%0d:%0d ", idx, align_b_din_local[idx]);
                        end else begin
                            $write("  -  ");
                        end
                    end
                    $display("]");
                end
            end
            
            // Print when data is injected to systolic array (in_valid pulse)
            if (DEBUG_ENABLE && DEBUG_ENABLE_ALIGN_CTRL && DEBUG_ENABLE_DATA_TRACE && align_in_valid_edge) begin
                $write("[%0t] [SR_CLK] [ALIGN_DATA] *** DATA INJECTION TO SA ***", $time);
                $write(" (Full row/column injection)");
                $display("");
                $write("  A_din (horizontal flow) = [");
                for (int idx = 0; idx < N; idx++) begin
                    $write("%0d", align_a_din_local[idx]);
                    if (idx < N - 1) $write(", ");
                end
                $write("]");
                $display("");
                $write("  B_din (vertical flow)  = [");
                for (int idx = 0; idx < N; idx++) begin
                    $write("%0d", align_b_din_local[idx]);
                    if (idx < N - 1) $write(", ");
                end
                $write("]");
                $display("");
                $write("  C_din (initial values)  = [");
                for (int idx = 0; idx < N; idx++) begin
                    $write("%0d", align_c_din_local[idx]);
                    if (idx < N - 1) $write(", ");
                end
                $display("]");
            end
            
            // Print systolic array state changes
            if (DEBUG_ENABLE && DEBUG_ENABLE_SYSTOLIC && sa_state_local != prev_sa_state) begin
                $write("[%0t] [SR_CLK] [SYSTOLIC_ARRAY] STATE: %s -> %s", 
                       $time, get_sa_state_name(prev_sa_state), sa_state_name);
                $write(" | ROW_IDX=%0d VALID_CNT=%0d", 
                       sa_row_idx_local, sa_valid_count_local);
                $write(" | OUTPUT_STALL=%0d", sa_output_stall_local);
                $display("");
            end
            
            // Print systolic array row streaming (when in STREAM state)
            if (DEBUG_ENABLE && DEBUG_ENABLE_SYSTOLIC && DEBUG_ENABLE_DATA_TRACE && sa_state_local == 2'b01 && !sa_output_stall_local) begin
                $write("[%0t] [SR_CLK] [SA_DATA] Streaming row %0d: C_dout=[", $time, sa_row_idx_local);
                for (int idx = 0; idx < N; idx++) begin
                    $write("%0d", sa_c_dout_local[idx]);
                    if (idx < N - 1) $write(", ");
                end
                $display("]");
            end
            
            // Print flush event
            if (DEBUG_ENABLE && DEBUG_ENABLE_SYSTOLIC && sa_flush_edge) begin
                $write("[%0t] [SR_CLK] [SYSTOLIC_ARRAY] ", $time);
                $display("*** FLUSH EVENT *** (Matrix computation complete, snapshot taken)");
                
                // Print snapshot of complete C matrix during flush
                if (DEBUG_ENABLE && DEBUG_ENABLE_DATA_TRACE) begin
                    $write("[%0t] [SR_CLK] [SA_DATA] C matrix snapshot at flush:", $time);
                    $display("");
                    // Note: Full matrix snapshot would require accessing internal signals
                    // This prints what's currently being streamed
                    $write("  C_dout=[");
                    for (int idx = 0; idx < N; idx++) begin
                        $write("%0d", sa_c_dout_local[idx]);
                        if (idx < N - 1) $write(", ");
                    end
                    $display("]");
                end
            end
            
            // Print on out_valid edge
            if (DEBUG_ENABLE && DEBUG_ENABLE_SYSTOLIC && sa_out_valid_edge) begin
                $write("[%0t] [SR_CLK] [SYSTOLIC_ARRAY] ", $time);
                $display("*** out_valid PULSE *** (Streaming started)");
                
                // Print the computed results being streamed out
                if (DEBUG_ENABLE && DEBUG_ENABLE_DATA_TRACE) begin
                    $write("[%0t] [SR_CLK] [SA_DATA] Streaming results: C_dout=[", $time);
                    for (int idx = 0; idx < N; idx++) begin
                        $write("%0d", sa_c_dout_local[idx]);
                        if (idx < N - 1) $write(", ");
                    end
                    $display("]");
                end
            end
            
            // Print systolic array stall condition
            if (DEBUG_ENABLE && DEBUG_ENABLE_SYSTOLIC && sa_output_stall_local) begin
                $write("[%0t] [SR_CLK] [SYSTOLIC_ARRAY] ", $time);
                $display("[STALL] Output FIFO full - computation paused");
            end
            
            // Print output FIFO state changes
            if (DEBUG_ENABLE && DEBUG_ENABLE_OUTPUT_FIFO && out_fifo_state_local != prev_out_fifo_state) begin
                $write("[%0t] [SR_CLK] [OUTPUT_FIFO_WR] STATE: %s -> %s", 
                       $time, get_out_fifo_state_name(prev_out_fifo_state), out_fifo_state_name);
                $write(" | STREAM_CNT=%0d/%0d", out_fifo_stream_cnt_local, N);
                $write(" | FULL=%0d WR_EN=%0d", out_fifo_full_local, out_fifo_wr_en_local);
                $display("");
            end
            
            // Print output FIFO write activity
            if (DEBUG_ENABLE && DEBUG_ENABLE_OUTPUT_FIFO && (out_fifo_wr_en_local || (out_fifo_full_local != prev_out_fifo_full))) begin
                $write("[%0t] [SR_CLK] [OUTPUT_FIFO_WR] ", $time);
                $write("WR=%0d FULL=%0d EMPTY=%0d", 
                       out_fifo_wr_en_local, out_fifo_full_local, !out_fifo_empty_internal_local);
                if (out_fifo_wr_en_local && out_fifo_full_local) begin
                    $write(" [WARNING: Write while full!]");
                end
                $display("");
            end
            
            // Update previous values
            prev_align_fifo_empty <= align_fifo_empty_local;
            prev_out_fifo_full <= out_fifo_full_local;
            
            // Update previous values
            prev_align_state       <= align_state_local;
            prev_sa_state          <= sa_state_local;
            prev_out_fifo_state    <= out_fifo_state_local;
            prev_sa_flush          <= sa_flush_local;
            prev_align_in_valid    <= align_in_valid_local;
            prev_sa_out_valid      <= sa_out_valid_local;
        end
    end

    // ======================================================================
    // Periodic summary print (every 100 cycles)
    // ======================================================================
    int cycle_count;
    always_ff @(posedge sr_clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
    end else if (DEBUG_ENABLE) begin
            cycle_count <= cycle_count + 1;
      if (DEBUG_ENABLE && cycle_count >= 100) begin
          // Use module-scope snapshot signals (continuous assigned) for summary

          $write("[%0t] [SR_CLK] [SUMMARY] ", $time);
          if (DEBUG_ENABLE_ALIGN_CTRL) begin
              $write("ALIGN: %s (load=%0d inj=%0d) ", 
                  get_align_state_name(align_state_local), align_load_cnt_local, align_inject_cycle_local);
          end
          if (DEBUG_ENABLE_SYSTOLIC) begin
              $write("| SA: %s (row=%0d val_cnt=%0d flush=%0d stall=%0d) ", 
                  get_sa_state_name(sa_state_local), sa_row_idx_local, sa_valid_count_local, 
                  sa_flush_local, sa_output_stall_local);
          end
          if (DEBUG_ENABLE_OUTPUT_FIFO) begin
              $write("| OUT_FIFO: %s (strm=%0d full=%0d)", 
                  get_out_fifo_state_name(out_fifo_state_local), out_fifo_stream_cnt_local, out_fifo_full_local);
          end
          $display("");
          cycle_count <= 0;
            end
        end
    end

endmodule

`endif // INSTRUMENTATION_SV
