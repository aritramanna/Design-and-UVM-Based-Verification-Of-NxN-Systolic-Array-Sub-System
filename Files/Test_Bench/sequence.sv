`ifndef SEQUENCE_SV
`define SEQUENCE_SV

class seq extends uvm_sequence #(seq_item);
    `uvm_object_utils(seq)

    seq_item tr;
    int num_transactions;

    function new(string name = "seq");
        super.new(name);
    endfunction

    virtual task body();
      num_transactions = $urandom_range(15,20);
      
        for(int idx = 0; idx < num_transactions; idx++) begin
            tr = seq_item::type_id::create($sformatf("tr_%0d", idx));
            start_item(tr);
            assert(tr.randomize() with { M_minus_one == N-1;});
            `uvm_info (get_type_name(), tr.convert2string(), UVM_HIGH)
            finish_item(tr);
        end
    endtask

endclass

`endif // SEQUENCE_SV

