`ifndef TB_CONFIG_SV
`define TB_CONFIG_SV

class tb_config extends uvm_object;
    `uvm_object_utils(tb_config)

    // Agent configuration
    uvm_active_passive_enum agent_is_active = UVM_ACTIVE;    // Control agent mode

    // Coverage configuration
    bit enable_coverage = 1;                                 // Enable/disable coverage collection

    // monitoring and checking (1: both , 2: sub-system only, 3: systolic only)
    int checker_mode = 2;

    function new(string name = "tb_config");
        super.new(name);
    endfunction

    // Custom print formatting
    virtual function string convert2string();
        string s = "\n=== Testbench Configuration ===\n";
        s = {s, $sformatf("Agent Mode: %s\n", agent_is_active.name())};
        s = {s, $sformatf("Coverage: %s\n", enable_coverage ? "Enabled" : "Disabled")};
        s = {s, $sformatf("Checker Mode: %0d\n", checker_mode)};
        return s;
    endfunction

endclass

`endif // TB_CONFIG_SV