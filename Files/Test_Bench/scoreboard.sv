`ifndef SCOREBOARD_SV
`define SCOREBOARD_SV

class scoreboard extends uvm_component;
    `uvm_component_utils(scoreboard)

    // Configuration object
    tb_config cfg;

    // Analysis FIFOs
    uvm_tlm_analysis_fifo #(seq_item) sub_input_fifo;
    uvm_tlm_analysis_fifo #(resp_item) sub_output_fifo;
    uvm_tlm_analysis_fifo #(seq_item) sa_input_fifo;
    uvm_tlm_analysis_fifo #(systolic_resp_item) sa_output_fifo;

    function new(string name, uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(tb_config)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "Config not set")
        end
        sub_input_fifo = new("sub_input_fifo", this);
        sub_output_fifo = new("sub_output_fifo", this);
        sa_input_fifo = new("sa_input_fifo", this);
        sa_output_fifo = new("sa_output_fifo", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        fork
          if (cfg.checker_mode == 1 || cfg.checker_mode == 2) sub_checker();
          if (cfg.checker_mode == 1 || cfg.checker_mode == 3) sa_checker();
        join
    endtask

    // ------------------------
    // Checker Tasks
    // ------------------------

    task sub_checker();
        seq_item sub_in;
        resp_item sub_out;
        forever begin
            sub_input_fifo.get(sub_in);
            sub_output_fifo.get(sub_out);
            if (sub_in.check_result(sub_out)) begin
                `uvm_info("SCOREBOARD", "Subsystem check passed", UVM_MEDIUM)
                print_sub_details(sub_in, sub_out, 1);
            end else begin
                `uvm_error("SCOREBOARD", "Subsystem check failed")
                print_sub_details(sub_in, sub_out, 0);
            end
        end
    endtask

    task sa_checker();
        seq_item sa_in_base;   
        systolic_resp_item sa_out;
        
        forever begin
            sa_input_fifo.get(sa_in_base);
            sa_output_fifo.get(sa_out);
            
            if (check_sa_result_from_sub(sa_in_base, sa_out)) begin
                `uvm_info("SCOREBOARD", "Systolic check passed", UVM_MEDIUM)
            end else begin
                `uvm_error("SCOREBOARD", "Systolic check failed")
            end
        end
    endtask

    // ------------------------
    // Check & Print Functions
    // ------------------------

    function bit check_sa_result_from_sub(seq_item sub_in, systolic_resp_item sa_out);
        bit match = 1;
        int expected_c [N][N]; 

        if (sub_in.M_minus_one != sa_out.M_minus_one) begin
            `uvm_error("CHECK_SA_RESULT", $sformatf("M_minus_one mismatch: expected %0d, got %0d", sub_in.M_minus_one, sa_out.M_minus_one))
            return 0;
        end

        // Compute expected C = A * B
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                expected_c[i][j] = 0;
                for (int k = 0; k <= sub_in.M_minus_one; k++) begin
                    expected_c[i][j] += sub_in.a[i][k] * sub_in.b[k][j];
                end
            end
        end

        // Compare with sa_out.c_out
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                if (expected_c[i][j] !== sa_out.c_out[i][j]) begin
                    `uvm_error("CHECK_SA_RESULT", $sformatf("C[%0d][%0d] mismatch: expected %0d, got %0d", i, j, expected_c[i][j], sa_out.c_out[i][j]))
                    match = 0;
                end
            end
        end
        return match;
    endfunction

    function void print_sub_details(seq_item sub_in, resp_item sub_out, bit pass);
        string s = $sformatf("\n=== Subsystem Checker Details (Pass: %0d) ===\n", pass);
        int expected_c [N][N]; 
        
        s = {s, "Input Matrices:\n"};
        s = {s, sub_in.convert2string()};
        s = {s, "\nExpected Output Matrix C:\n"};
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                expected_c[i][j] = 0;
                for (int k = 0; k <= sub_in.M_minus_one; k++) begin
                    expected_c[i][j] += sub_in.a[i][k] * sub_in.b[k][j];
                end
            end
        end
        s = {s, "-------------\n"};
        for (int i = 0; i < N; i++) begin
            s = {s, "| "};
            for (int j = 0; j < N; j++) begin
                s = {s, $sformatf("%6d ", $signed(expected_c[i][j]))};
            end
            s = {s, "|\n"};
        end
        s = {s, "\nDUT Output Matrix C:\n"};
        s = {s, "-------------\n"};
        for (int i = 0; i < N; i++) begin
            s = {s, "| "};
            for (int j = 0; j < N; j++) begin
                s = {s, $sformatf("%6d ", $signed(sub_out.c_out[i][j]))};
            end
            s = {s, "|\n"};
        end
        s = {s, "\n"};
        `uvm_info("SCOREBOARD", s, UVM_MEDIUM)
    endfunction

    // ------------------------
    // UVM Phases
    // ------------------------

    virtual function void extract_phase(uvm_phase phase);
        bit fifo_has_leftovers;
        
        // --- Local transaction handles ---
        seq_item sub_in_tr;
        resp_item sub_out_tr;
        seq_item sa_in_tr;
        systolic_resp_item sa_out_tr;
        // ---
        
        super.extract_phase(phase);
        `uvm_info(get_type_name(), "--- Extract Phase: Checking for leftover transactions ---", UVM_LOW)
        
        // Gated Sub-System FIFO Check
        if (cfg.checker_mode == 1 || cfg.checker_mode == 2) begin
            `uvm_info(get_type_name(), "Checking sub-system FIFOs (mode 1 or 2)...", UVM_LOW)
            
            fifo_has_leftovers = 0;
            while (sub_input_fifo.try_get(sub_in_tr)) begin
                `uvm_error("sub_input_fifo", {"Found leftover transaction(s): ", sub_in_tr.convert2string()});
                fifo_has_leftovers = 1;
            end
            if (!fifo_has_leftovers)
                `uvm_info(get_type_name(), "[PASS] All transactions in sub_input_fifo have been processed", UVM_LOW)

            fifo_has_leftovers = 0;
            while (sub_output_fifo.try_get(sub_out_tr)) begin
                `uvm_error("sub_output_fifo", {"Found leftover transaction(s): ", sub_out_tr.convert2string()});
                fifo_has_leftovers = 1;
            end
            if (!fifo_has_leftovers)
                `uvm_info(get_type_name(), "[PASS] All transactions in sub_output_fifo have been processed", UVM_LOW)
                
        end else begin
            `uvm_info(get_type_name(), "Skipping sub-system FIFO check (not mode 1 or 2).", UVM_LOW)
        end

        // Gated Systolic Array FIFO Check
        if (cfg.checker_mode == 1 || cfg.checker_mode == 3) begin
             `uvm_info(get_type_name(), "Checking systolic array FIFOs (mode 1 or 3)...", UVM_LOW)
             
            fifo_has_leftovers = 0;
            while (sa_input_fifo.try_get(sa_in_tr)) begin
                `uvm_error("sa_input_fifo", {"Found leftover transaction(s): ", sa_in_tr.convert2string()});
                fifo_has_leftovers = 1;
            end
            if (!fifo_has_leftovers)
                `uvm_info(get_type_name(), "[PASS] All transactions in sa_input_fifo have been processed", UVM_LOW)
            
            fifo_has_leftovers = 0;
            while (sa_output_fifo.try_get(sa_out_tr)) begin
                `uvm_error("sa_output_fifo", {"Found leftover transaction(s): ", sa_out_tr.convert2string()});
                fifo_has_leftovers = 1;
            end
            if (!fifo_has_leftovers)
                `uvm_info(get_type_name(), "[PASS] All transactions in sa_output_fifo have been processed", UVM_LOW)
                
        end else begin
             `uvm_info(get_type_name(), "Skipping systolic array FIFO check (not mode 1 or 3).", UVM_LOW)
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server svr;
        int error_count;
        
        super.report_phase(phase);
        svr = uvm_report_server::get_server();
        error_count = svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);

        `uvm_info(get_type_name(), "--- Final Report Phase ---", UVM_NONE)
        
        // Any error (data or FIFO) fails the test.
        if (error_count == 0) begin
            `uvm_info(get_type_name(), "[Check]: PASS - No UVM_ERRORs or UVM_FATALs recorded.", UVM_NONE)
        end else begin
            `uvm_info(get_type_name(), $sformatf("[Check]: FAIL - %0d UVM_ERRORs/UVM_FATALs recorded.", error_count), UVM_NONE)
        end
        
        // --- Overall Result ---
        `uvm_info(get_type_name(), "------------------------------------------", UVM_NONE)
        if (error_count == 0) begin
            `uvm_info(get_type_name(), "** OVERALL TEST PASSED        **", UVM_NONE)
        end else begin
            `uvm_info(get_type_name(), "** OVERALL TEST FAILED        **", UVM_NONE)
        end
        `uvm_info(get_type_name(), "------------------------------------------", UVM_NONE)
    endfunction

endclass

`endif // SCOREBOARD_SV