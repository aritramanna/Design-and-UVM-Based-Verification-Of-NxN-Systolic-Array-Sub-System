`ifndef TEST_SV
`define TEST_SV

class test extends uvm_test;
    `uvm_component_utils(test)

    env env_h;
    seq s;
    tb_config cfg;

    function new(string name = "test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create and configure the testbench configuration
        cfg = tb_config::type_id::create("cfg");

        // Set default configuration for this test
        cfg.agent_is_active = UVM_ACTIVE;
        cfg.enable_coverage = 1;
        cfg.checker_mode = 1; // monitoring and checking (1: both , 2: sub-system only, 3) systolic only

        // Set the configuration in the config_db for all components to access
        uvm_config_db#(tb_config)::set(this, "*", "cfg", cfg);

        // Create environment and sequence
        env_h = env::type_id::create("env_h", this);
        s = seq::type_id::create("s");

        // Print the configuration
        `uvm_info(get_type_name(), $sformatf("Test Configuration:\n%s", cfg.convert2string()), UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        if (cfg.agent_is_active == UVM_ACTIVE) begin
            s.start(env_h.agent_h.seqr);
        end
        phase.drop_objection(this);
        // Drain time helps capture pending response data
      phase.phase_done.set_drain_time(this,2200ns);
    endtask
endclass

`endif // TEST_SV

