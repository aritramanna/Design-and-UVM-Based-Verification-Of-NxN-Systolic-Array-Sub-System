`timescale 1ns/1ps

module streaming_async_fifo #(
    parameter int DIN_WIDTH  = 8,
    parameter int N          = 4,
    parameter int FIFO_DEPTH = 1024,
    parameter int BUS_WIDTH  = 2 * DIN_WIDTH * N
)(
    // Write domain (systolic array clock)
    input  logic                        sa_clk,
    input  logic                        sa_rst_n,
    input  logic signed [2*DIN_WIDTH-1:0] c_dout [0:N-1],
    input  logic                        sa_out_valid,

    // Read domain (system clock)
    input  logic                        sys_clk,
    input  logic                        sys_rst_n,
    input  logic                        rd_en,
    output logic [BUS_WIDTH-1:0]        dout,
    output logic                        empty,
    
    // Backpressure signal (systolic array clock domain)
    output logic                        output_full
);

    typedef enum logic [1:0] {IDLE, STREAMING} state_t;
    state_t state;

    logic [$clog2(N)-1:0] stream_count;
    logic [BUS_WIDTH-1:0] fifo_din;
    logic signed [2*DIN_WIDTH-1:0] c_dout_delayed [0:N-1]; // Delayed version of c_dout
    logic [BUS_WIDTH-1:0] fifo_din_delayed; // Delayed packed version
    logic fifo_wr_en;
    logic fifo_full;
    logic sa_out_valid_d;  // Delayed version to detect edge
    
    // Stalls the systolic array when the output FIFO is full
    assign output_full = fifo_full;

    // Pack all N outputs into fifo_din
    assign fifo_din = {<<{c_dout}};

    // ======================================================================
    // Delay c_dout by one cycle to account for non-blocking assignment timing
    // When sa_out_valid goes high, c_dout is assigned but not yet visible
    // By delaying it, we capture the correct data on the next cycle
    // ======================================================================
    always_ff @(posedge sa_clk or negedge sa_rst_n) begin
        if (!sa_rst_n) begin
            for (int k = 0; k < N; k++) begin
                c_dout_delayed[k] <= '0;
            end
            fifo_din_delayed <= '0;
        end else begin
            // Register c_dout to get delayed version
            for (int k = 0; k < N; k++) begin
                c_dout_delayed[k] <= c_dout[k];
            end
            fifo_din_delayed <= fifo_din;
        end
    end

    // ======================================================================
    // Combinational: Write enable - write when in STREAMING and not full
    // ======================================================================
    always_comb begin
        fifo_wr_en = 1'b0;
        if (state == STREAMING && !fifo_full) begin
            fifo_wr_en = 1'b1; // Write when in streaming state and not full
        end
        // If fifo_full, fifo_wr_en stays 0, and output_full asserts backpressure
    end

    // ======================================================================
    // Sequential: State machine to track streaming progress
    // ======================================================================
    always_ff @(posedge sa_clk or negedge sa_rst_n) begin
        if (!sa_rst_n) begin
            state        <= IDLE;
            stream_count <= '0;
            sa_out_valid_d <= 1'b0;
        end else begin
            sa_out_valid_d <= sa_out_valid; // Track previous value for edge detection
            
            case (state)
                IDLE: begin
                    // Detect rising edge of sa_out_valid
                    // On next cycle, c_dout_delayed will have row 0 data
                    if (sa_out_valid && !sa_out_valid_d) begin
                        //$write("STREAMING_FIFO: IDLE->STREAMING, sa_out_valid edge detected\n");
                        state <= STREAMING;
                        stream_count <= 0; // Start counting from 0
                    end
                end

                STREAMING: begin
                    // Write delayed version of c_dout (one cycle behind)
                    // This ensures we capture the correct row data
                    if (fifo_wr_en) begin
                        //$write("STREAMING_FIFO: Writing row (count=%0d), fifo_din={", stream_count);
                        //for (int k = 0; k < N; k++) begin
                        //    $write("%6d", c_dout_delayed[k]);
                        //    if (k != N-1) $write(", ");
                        //end
                        //$write("}\n");
                        
                        if (stream_count < N - 1) begin
                            stream_count <= stream_count + 1;
                        end else begin
                            // Completed N rows (0 through N-1), go back to IDLE
                            stream_count <= '0;
                            state <= IDLE;
                            //$write("STREAMING_FIFO: STREAMING->IDLE (completed N rows)\n");
                        end
                    end
                    // If fifo_full, stay in STREAMING and wait (backpressure via output_full)
                end
            endcase
        end
    end

    async_fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(BUS_WIDTH)
    ) u_output_fifo (
        .wr_clk  (sa_clk),
        .wr_rst_n(sa_rst_n),
        .wr_en   (fifo_wr_en),
        .din     (fifo_din_delayed), // Use delayed version
        .full    (fifo_full),
        .rd_clk  (sys_clk),
        .rd_rst_n(sys_rst_n),
        .rd_en   (rd_en),
        .dout    (dout),
        .empty   (empty)
    );

endmodule
