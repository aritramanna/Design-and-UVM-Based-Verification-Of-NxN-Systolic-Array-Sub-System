// ======================================================================
// PE CELL — Multiply-Accumulate with synchronous flush and load
// ======================================================================
module pe_cell #(
    parameter int DIN_WIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic flush,   // clears accumulated sum same cycle as out_valid
    input  logic load,    // load Cin into Cout instead of accumulating

    // Data flow inputs
    input  logic signed [DIN_WIDTH-1:0]    a_in,
    input  logic signed [DIN_WIDTH-1:0]    b_in,
    input  logic signed [2*DIN_WIDTH-1:0]  c_in,

    // Data flow outputs
    output logic signed [DIN_WIDTH-1:0]    a_out,
    output logic signed [DIN_WIDTH-1:0]    b_out,
    output logic signed [2*DIN_WIDTH-1:0]  c_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= '0;
            b_out <= '0;
            c_out <= '0;
        end else if (load) begin
            // load Cin directly for top edge
            a_out <= a_in;
            b_out <= b_in;
            c_out <= c_in;
        end else if (flush) begin
            // clear accumulation registers during the same cycle as out_valid
            a_out <= a_in;
            b_out <= b_in;
            c_out <= '0;
        end else begin
            // normal multiply-accumulate operation
            a_out <= a_in;
            b_out <= b_in;
            c_out <= c_out + (a_in * b_in);
        end
    end

endmodule
