`ifndef DATA_ALIGN_CTRL_SV
`define DATA_ALIGN_CTRL_SV

// ======================================================================
// Data Alignment Unit and Controller
// Handles FIFO reading, buffering, and skewed injection pattern generation
// Supports rectangular matrices (MxN or NxM)
// Minimal change: latch M one cycle after M_fifo_rd_en so M_fifo_dout is valid
// ======================================================================
module data_align_ctrl #(
    parameter DIN_WIDTH = 8,
    parameter N = 4,
    parameter BUS_WIDTH = 2 * DIN_WIDTH * N
) (
    input  logic rst_n,
    input  logic clk,

    // FIFO interface
    input  logic [BUS_WIDTH-1:0] fifo_data,
    input  logic fifo_empty,
    output logic fifo_rd_en,

    // M FIFO interface
    input  logic M_fifo_empty,
    input  logic [7:0] M_fifo_dout,
    output logic M_fifo_rd_en,

    // Backpressure from output FIFO
    input  logic output_stall,

    // Systolic array interface
    output logic signed [DIN_WIDTH-1:0] a_din [0:N-1],
    output logic signed [DIN_WIDTH-1:0] b_din [0:N-1],
    output logic signed [2*DIN_WIDTH-1:0] c_din [0:N-1],
    output logic in_valid
);

    localparam int C_WIDTH = 2 * DIN_WIDTH;

    typedef enum logic [3:0] {
        IDLE,
        MFIFO_RD,       // read M FIFO
        LOAD_REQ,       // assert fifo_rd_en when data available
        LOAD_CAPTURE,   // capture fifo_data one cycle later
        INJECT
    } state_t;

    state_t state;
    logic [7:0] load_cnt;
    logic [7:0] inject_cycle;
    logic [7:0] capture_idx;
    logic [7:0] M_lat;

    // Tracks when systolic array snapshot is complete (2*N-1 cycles from in_valid)
    logic [$clog2(2*N):0] sa_complete_count;

    logic signed [DIN_WIDTH-1:0] a_buffer [0:N-1][0:255];
    logic signed [DIN_WIDTH-1:0] b_buffer [0:255][0:N-1];

    // Loop variables declared at module level
    int init_i, init_j, init_i2, init_j2, load_i, comb_r, comb_c, comb_i, comb_r2, comb_c2;

    // ------------------------------------------------------------------
    // Correctly latch M one cycle after asserting M_fifo_rd_en
    // (M FIFO has 1-cycle output latency)
    // ------------------------------------------------------------------
    logic M_rd_d;  // delayed read pulse

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_rd_d <= 1'b0;
            M_lat  <= '0;
        end else begin
            M_rd_d <= (state == MFIFO_RD && !M_fifo_empty && !output_stall);
            if (M_rd_d)
                M_lat <= M_fifo_dout + 1; // latch when dout becomes valid
        end
    end

    // ======================================================================
    // Controller State Machine
    // ======================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= IDLE;
            load_cnt          <= 0;
            inject_cycle      <= 0;
            capture_idx       <= 0;
            sa_complete_count <= '0;

            // Initialize buffers
            for (init_i = 0; init_i < N; init_i++) begin
                for (init_j = 0; init_j < 256; init_j++) begin
                    a_buffer[init_i][init_j] <= '0;
                end
            end
            for (init_i2 = 0; init_i2 < 256; init_i2++) begin
                for (init_j2 = 0; init_j2 < N; init_j2++) begin
                    b_buffer[init_i2][init_j2] <= '0;
                end
            end

        end else begin
            // Wait (2*N-1) cycles from in_valid until snapshot, then can start next computation
            if (in_valid) begin
                sa_complete_count <= 1;
            end else if (sa_complete_count != 0) begin
                if (sa_complete_count == (2 * N - 1))
                    sa_complete_count <= '0;
                else
                    sa_complete_count <= sa_complete_count + 1;
            end
            
            if (!output_stall) begin
                case (state)
                    // Wait for data
                    IDLE: begin
                        if (!fifo_empty && !M_fifo_empty) begin
                            state       <= MFIFO_RD;
                        end
                    end

                    // Read M FIFO
                    MFIFO_RD: begin
                        state       <= LOAD_REQ;
                        load_cnt    <= 0;
                        capture_idx <= 0;
                    end

                    // Request a read (rd_en asserted via fifo_rd_en)
                    LOAD_REQ: begin
                        if (!fifo_empty) begin
                            capture_idx <= load_cnt;
                            state       <= LOAD_CAPTURE;
                        end
                    end

                    // Capture fifo_data after one cycle latency into buffers
                    LOAD_CAPTURE: begin
                        for (load_i = 0; load_i < N; load_i++) begin
                            a_buffer[load_i][capture_idx] <= fifo_data[load_i*DIN_WIDTH +: DIN_WIDTH];
                            b_buffer[capture_idx][load_i] <= fifo_data[(N*DIN_WIDTH) + load_i*DIN_WIDTH +: DIN_WIDTH];
                        end

                        if (load_cnt == (M_lat - 1)) begin
                            state        <= INJECT;
                            inject_cycle <= 0;
                            load_cnt     <= 0;
                        end else begin
                            load_cnt <= load_cnt + 1;
                            state    <= LOAD_REQ;
                        end
                    end

                    // Generate skewed injection
                    INJECT: begin
                        if (inject_cycle >= (N + M_lat - 2)) begin
                            inject_cycle <= 0;
                            // Wait until snapshot complete (sa_complete_count == 0)
                            if (!fifo_empty && !M_fifo_empty && sa_complete_count == 0) begin
                                state       <= MFIFO_RD;
                            end else if (sa_complete_count == 0) begin
                                state     <= IDLE;
                            end
                            // If sa_complete_count != 0, stay in INJECT and wait
                        end else begin
                            inject_cycle <= inject_cycle + 1;
                        end
                    end
                endcase
            end
        end
    end

    // ======================================================================
    // FIFO Read Enable (stall when output FIFO is full)
    // ======================================================================
    always_comb begin
        fifo_rd_en   = (state == LOAD_REQ && !fifo_empty && !output_stall);
        M_fifo_rd_en = (state == MFIFO_RD && !M_fifo_empty && !output_stall);
    end

    // ======================================================================
    // Data Alignment: Generate Skewed Injection Pattern
    // ======================================================================
    always_comb begin
        // Defaults
        for (comb_r = 0; comb_r < N; comb_r++) a_din[comb_r] = '0;
        for (comb_c = 0; comb_c < N; comb_c++) b_din[comb_c] = '0;
        for (comb_i = 0; comb_i < N; comb_i++) c_din[comb_i] = '0;

        if (state == INJECT && !output_stall) begin
            // A flows horizontally
            for (comb_r2 = 0; comb_r2 < N; comb_r2++) begin
                if ((inject_cycle >= comb_r2) && ((inject_cycle - comb_r2) < M_lat))
                    a_din[comb_r2] = a_buffer[comb_r2][inject_cycle - comb_r2];
            end

            // B flows vertically
            for (comb_c2 = 0; comb_c2 < N; comb_c2++) begin
                if ((inject_cycle >= comb_c2) && ((inject_cycle - comb_c2) < M_lat))
                    b_din[comb_c2] = b_buffer[inject_cycle - comb_c2][comb_c2];
            end
        end
    end

    // ======================================================================
// in_valid generation (synchronous, 1-cycle aligned)
// ======================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_valid <= 1'b0;
    end else begin
        // Default off
        in_valid <= 1'b0;

        // Assert only when inject_phase is active AND M_lat is valid
        if (state == INJECT) begin
            // Because synchronous logic updates next cycle,
            // this will assert exactly when inject_cycle reaches the last valid point.
            if (inject_cycle == (N + M_lat - 3)) begin
                in_valid <= 1'b1;
            end
        end
    end
end


endmodule

`endif // DATA_ALIGN_CTRL_SV
