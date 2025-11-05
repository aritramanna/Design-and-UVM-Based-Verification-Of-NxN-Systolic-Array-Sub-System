`ifndef ENV_SV
`define ENV_SV

class env extends uvm_env;
    `uvm_component_utils(env)

    agent   agent_h;
    scoreboard scbd;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent_h = agent::type_id::create("agent_h", this);
        scbd = scoreboard::type_id::create("scbd", this);
    endfunction

    // Print the topology of the environment
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent_h.mon.ap_sub_input.connect(scbd.sub_input_fifo.analysis_export);
        agent_h.mon.ap_sub_output.connect(scbd.sub_output_fifo.analysis_export);
        agent_h.mon.ap_sub_input.connect(scbd.sa_input_fifo.analysis_export);
        agent_h.mon.ap_sa_output.connect(scbd.sa_output_fifo.analysis_export);
    endfunction
endclass

`endif // ENV_SV

