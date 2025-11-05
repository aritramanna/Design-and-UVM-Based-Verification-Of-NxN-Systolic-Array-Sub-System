`ifndef AGENT_SV
`define AGENT_SV

`include "config.sv"

class agent extends uvm_component;
    `uvm_component_utils(agent)

    tb_config cfg;
    driver drv;
    monitor mon;
    uvm_sequencer #(seq_item) seqr;

    function new(string name = "agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Retrieve the configuration
        if (!uvm_config_db#(tb_config)::get(this, "", "cfg", cfg)) begin
           `uvm_fatal(get_type_name(), "Failed to get configuration")
        end

        // Create active components only when agent is active
        if (cfg.agent_is_active == UVM_ACTIVE) begin
            seqr = uvm_sequencer#(seq_item)::type_id::create("seqr", this);
            drv = driver::type_id::create("drv", this);
        end else begin
            `uvm_info(get_type_name(), "Agent running in PASSIVE mode (no driver/sequencer created)", UVM_LOW)
        end

        // Monitor is always created (observes DUT)
        mon = monitor::type_id::create("mon", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
            if (cfg.agent_is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction
endclass

`endif // AGENT_SV

