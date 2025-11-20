`ifndef SYSTOLIC_ARRAY_SV
`define SYSTOLIC_ARRAY_SV

`include "pe.sv"
// ======================================================================
// NxN Systolic Array with Snapshot + Row-wise Streaming Output
// - Captures full C matrix on flush
// - Streams rows sequentially after snapshot
// ======================================================================

module systolic_array #(
    parameter int DIN_WIDTH = 8,
    parameter int N         = 4
)(
    input  logic                         rst_n,
    input  logic                         clk,

    input  logic signed [2*DIN_WIDTH-1:0] c_din [0:N-1],
    input  logic signed [DIN_WIDTH-1:0]   a_din [0:N-1],
    input  logic signed [DIN_WIDTH-1:0]   b_din [0:N-1],
    input  logic                          in_valid,
    input  logic                          output_stall,

    output logic signed [2*DIN_WIDTH-1:0] c_dout [0:N-1],
    output logic                          out_valid
);

    // ------------------------------------------------------------------
    // Internal systolic interconnects
    // ------------------------------------------------------------------
    logic signed [DIN_WIDTH-1:0]    a_inter [0:N-1][0:N];
    logic signed [DIN_WIDTH-1:0]    b_inter [0:N][0:N-1];
    logic signed [2*DIN_WIDTH-1:0]  c_inter [0:N-1][0:N-1];

    logic [$clog2(2*N):0] valid_count;
    logic flush;

    // ------------------------------------------------------------------
    // Edge wiring
    // ------------------------------------------------------------------
    always_comb begin
        for (int k = 0; k < N; k++) begin
            a_inter[k][0] = a_din[k];
            b_inter[0][k] = b_din[k];
        end
    end

    // ------------------------------------------------------------------
    // Output valid counter (2*N - 1 latency)
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_count <= '0;
        else if (in_valid)
            valid_count <= 1;
        else if (valid_count != 0)
            valid_count <= (valid_count == (2*N - 1)) ? '0 : valid_count + 1;
    end

    assign flush = (valid_count == (2*N - 1)); 

    // ------------------------------------------------------------------
    // PE grid
    // ------------------------------------------------------------------
    genvar i, j;
    generate
        for (i = 0; i < N; i++) begin : row_gen
            for (j = 0; j < N; j++) begin : col_gen
                if (i == 0) begin
                    pe_cell #(.DIN_WIDTH(DIN_WIDTH)) pe_inst (
                        .clk   (clk),
                        .rst_n (rst_n),
                        .flush (flush),
                        .load  (flush),
                        .a_in  (a_inter[i][j]),
                        .b_in  (b_inter[i][j]),
                        .c_in  (c_din[j]),
                        .a_out (a_inter[i][j+1]),
                        .b_out (b_inter[i+1][j]),
                        .c_out (c_inter[i][j])
                    );
                end else begin
                    pe_cell #(.DIN_WIDTH(DIN_WIDTH)) pe_inst (
                        .clk   (clk),
                        .rst_n (rst_n),
                        .flush (flush),
                        .load  (1'b0),
                        .a_in  (a_inter[i][j]),
                        .b_in  (b_inter[i][j]),
                        .c_in  (c_inter[i-1][j]),
                        .a_out (a_inter[i][j+1]),
                        .b_out (b_inter[i+1][j]),
                        .c_out (c_inter[i][j])
                    );
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Snapshot + Streaming FSM (single-state Mealy)
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, STREAM} state_t;
    state_t state;

    logic signed [2*DIN_WIDTH-1:0] C_snap [0:N-1][0:N-1];
    logic [$clog2(N)-1:0] row_idx;
    logic out_valid_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            row_idx     <= '0;
            out_valid   <= 1'b0;
            out_valid_d <= 1'b0;
            for (int r = 0; r < N; r++)
                for (int c = 0; c < N; c++)
                    C_snap[r][c] <= '0;
            for (int k = 0; k < N; k++)
                c_dout[k] <= '0;
        end else begin
            out_valid_d <= out_valid; // delayed version for 1-cycle pulse

            if (!output_stall) begin
                case (state)
                    // ------------------------------------------------------
                    // Wait for flush → snapshot C matrix
                    // ------------------------------------------------------
                    IDLE: begin
                        out_valid <= 1'b0;
                        for (int k = 0; k < N; k++)
                            c_dout[k] <= '0;
                        if (flush) begin
                            // Snapshot all outputs at once
                            for (int r = 0; r < N; r++)
                                for (int c = 0; c < N; c++)
                                    C_snap[r][c] <= c_inter[r][c];

                            row_idx <= 0;
                            state   <= STREAM;
                        end
                    end

                    // ------------------------------------------------------
                    // Stream one row per cycle
                    // ------------------------------------------------------
                    STREAM: begin
                        // Output current row
                        for (int k = 0; k < N; k++)
                            c_dout[k] <= C_snap[row_idx][k];

                        // Pulse out_valid only once
                        out_valid <= (row_idx == 0 && !out_valid_d);

                        // Stream next row
                        if (row_idx < N - 1)
                            row_idx <= row_idx + 1;
                        else begin
                            row_idx <= '0;
                            state   <= IDLE;
                        end
                    end
                endcase
            end else begin
                // When stalled, hold current state and outputs
            end
        end
    end

endmodule

`endif // SYSTOLIC_ARRAY_SV
