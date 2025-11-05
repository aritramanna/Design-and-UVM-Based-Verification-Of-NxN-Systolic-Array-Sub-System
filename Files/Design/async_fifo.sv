//==========================================================
// Model: Asynchronous FIFO
//==========================================================
module async_fifo #(
    parameter int FIFO_DEPTH = 1024,
    parameter int DATA_WIDTH = 32
)(
    //==============================
    // Write domain
    //==============================
    input  logic                   wr_clk,      // Write clock
    input  logic                   wr_rst_n,    // Active-low write reset
    input  logic                   wr_en,       // Write enable
    input  logic [DATA_WIDTH-1:0]  din,         // Write data input
    output logic                   full,        // FIFO full flag

    //==============================
    // Read domain
    //==============================
    input  logic                   rd_clk,      // Read clock
    input  logic                   rd_rst_n,    // Active-low read reset
    input  logic                   rd_en,       // Read enable
    output logic [DATA_WIDTH-1:0]  dout,        // Read data output
    output logic                   empty        // FIFO empty flag
);

    // --------------------------------------------------------
    // Internal queue model representing the FIFO storage.
    // This is shared between the two clock domains.
    // --------------------------------------------------------
    logic [DATA_WIDTH-1:0] dataQ[$];

    //=========================================================
    // WRITE DOMAIN (wr_clk)
    // - Pushes data into the queue
    // - Generates the 'full' flag
    //=========================================================
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            dataQ.delete(); // Clear the storage on write reset
            full <= 1'b0;
        end
        else begin
            // The 'full' flag is synchronous to the write clock.
            // It reflects the state *before* the current write.
            full <= (dataQ.size() >= FIFO_DEPTH);

            if (wr_en && !full) begin
                dataQ.push_front(din);
            end
            
            // Optional: Add a warning for the testbench driver
            if (wr_en && full) begin
                $fatal("[%0t] (FIFO Model) ATTEMPTED WRITE TO FULL FIFO (ignored)", $time);
            end
        end
    end

    //=========================================================
    // READ DOMAIN (rd_clk)
    // - Pops data from the queue
    // - Generates the 'empty' flag and 'dout'
    //=========================================================
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            empty <= 1'b1;
            dout  <= '0;
            // Note: Read reset only clears the read-side logic.
            // The dataQ storage is only cleared by the write reset.
        end
        else begin
            // The 'empty' flag is synchronous to the read clock.
            // It reflects the state *before* the current read.
            empty <= (dataQ.size() == 0);

            if (rd_en && !empty) begin
                // Pop data from the back of the queue.
                // 'dout' will be valid on the *next* clock cycle.
                dout <= dataQ.pop_back();
            end
            
            // Optional: Add a warning for the testbench driver
            if (rd_en && empty) begin
                $fatal("[%0t] (FIFO Model) ATTEMPTED READ FROM EMPTY FIFO (ignored)", $time);
            end
        end
    end

endmodule