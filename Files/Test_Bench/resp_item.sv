`ifndef RESP_ITEM_SV
`define RESP_ITEM_SV

class resp_item extends uvm_sequence_item;
    `uvm_object_utils(resp_item)

    logic signed [2*DIN_WIDTH-1:0] c_out [N][N];
    logic [7:0] M_minus_one;

    function new(string name = "resp_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        string s = "\n============================================\n";
        s = {s, $sformatf("Response Item (M=%0d)\n", M_minus_one + 1)};
        s = {s, "============================================\n\nMatrix C [N x N]:\n-------------\n"};
        foreach (c_out[i]) begin
            s = {s, "| "};
            foreach (c_out[i][j]) s = {s, $sformatf("%6d ", $signed(c_out[i][j]))};
            s = {s, "|\n"};
        end
        return {s, "\n"};
    endfunction
endclass

`endif // RESP_ITEM_SV
