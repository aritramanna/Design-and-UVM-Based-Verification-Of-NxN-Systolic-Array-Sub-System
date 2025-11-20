`ifndef SYSTOLIC_RESP_ITEM_SV
`define SYSTOLIC_RESP_ITEM_SV

class systolic_resp_item extends resp_item;
    `uvm_object_utils(systolic_resp_item)

    function new(string name = "systolic_resp_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = "\n============================================\n";
        s = {s, $sformatf("Systolic Output Item (M=%0d)\n", M_minus_one + 1)};
        s = {s, "============================================\n"};
        s = {s, "\nMatrix C [N x N]:\n"};
        s = {s, "-------------\n"};
        for (int i = 0; i < N; i++) begin
            s = {s, "| "};
            for (int j = 0; j < N; j++) begin
                s = {s, $sformatf("%6d ", $signed(c_out[i][j]))};
            end
            s = {s, "|\n"};
        end
        s = {s, "\n"};
        return s;
    endfunction
endclass

`endif // SYSTOLIC_RESP_ITEM_SV
