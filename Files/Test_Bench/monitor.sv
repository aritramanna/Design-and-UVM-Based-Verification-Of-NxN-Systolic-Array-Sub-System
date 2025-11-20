`ifndef MONITOR_SV
`define MONITOR_SV

// ================================================================
// Monitor
// ================================================================
class monitor extends uvm_component;
    `uvm_component_utils(monitor)

    // Configuration object
    tb_config cfg;

    // Sub-System Analysis Ports
    uvm_analysis_port #(seq_item) ap_sub_input;
    uvm_analysis_port #(resp_item) ap_sub_output;

    // Systolic Array Analysis Ports
    uvm_analysis_port #(systolic_resp_item) ap_sa_output;

    // Virtual interface
    virtual sub_sys_if #(DIN_WIDTH, N, BUS_WIDTH) vif;
    virtual systolic_if #(DIN_WIDTH, N) vif_sa;

    // Systolic monitoring variables
    bit collecting_sa_output = 0;
    int sa_output_row_count = 0;
    systolic_resp_item sa_output_item;
    logic [7:0] last_M_minus_one = 0;

    // Counters for completed results
    int sub_output_count = 0;
    int sa_output_count = 0;

    function new(string name = "monitor", uvm_component parent = null);
        super.new(name, parent);
        ap_sub_input = new("ap_sub_input", this);
        ap_sub_output = new("ap_sub_output", this);
        ap_sa_output = new("ap_sa_output", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sub_sys_if #(DIN_WIDTH, N, BUS_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Sub-System Virtual interface not set")
        end
        if (!uvm_config_db#(tb_config)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "Config not set")
        end
        if (cfg.checker_mode == 1 || cfg.checker_mode == 3) begin
            if (!uvm_config_db#(virtual systolic_if #(DIN_WIDTH, N))::get(this, "", "sa_vif", vif_sa)) begin
                `uvm_fatal(get_type_name(), "Systolic virtual interface not set")
            end
        end
    endfunction

    // ------------------------
    // Main Run Phase
    // ------------------------
    virtual task run_phase(uvm_phase phase);
        fork
            update_m_task();
            if (cfg.checker_mode == 1 || cfg.checker_mode == 2 || cfg.checker_mode == 3) sub_monitor_task();
            if ((cfg.checker_mode == 1 || cfg.checker_mode == 3) && vif_sa != null) sa_monitor_task();
        join_none
    endtask

    // ------------------------
    // Update M Task
    // ------------------------
    task automatic update_m_task();
        forever begin
            @(vif.mon_cb);
            if (!vif.mon_cb.rst_n) begin
                last_M_minus_one = 0;
            end else begin
                if (vif.mon_cb.wr_fifo && !vif.mon_cb.in_fifo_full) begin
                    last_M_minus_one = vif.mon_cb.M_minus_one;
                end
            end
        end
    endtask

    // ------------------------
    // Subsystem Monitor Task
    // ------------------------
    task automatic sub_monitor_task();
        seq_item sub_input_item;
        resp_item sub_output_item;
        logic [7:0] current_sub_M_minus_one;
        int sub_input_slice_count;
        int sub_output_row_count;
        bit collecting_sub_input = 0;
        bit collecting_sub_output = 0;
        logic [DIN_WIDTH-1:0] a_col[N], b_row[N];
        logic signed [2*DIN_WIDTH-1:0] c_unpack [0:N-1];

        forever begin
            @(vif.mon_cb);
            if (!vif.mon_cb.rst_n) begin
                collecting_sub_input = 0;
                collecting_sub_output = 0;
                sub_input_slice_count = 0;
                sub_output_row_count = 0;
                sub_input_item = null;
                sub_output_item = null;
            end else begin
                if (vif.mon_cb.wr_fifo && !vif.mon_cb.in_fifo_full) begin
                    if (!collecting_sub_input) begin
                        sub_input_item = seq_item::type_id::create("sub_input_item");
                        current_sub_M_minus_one = vif.mon_cb.M_minus_one;
                        sub_input_item.M_minus_one = current_sub_M_minus_one;
                        sub_input_item.bus_din = new[current_sub_M_minus_one + 1];
                        collecting_sub_input = 1;
                        sub_input_slice_count = 0;
                        `uvm_info(get_type_name(), $sformatf("Starting input collection for M=%0d", current_sub_M_minus_one + 1), UVM_HIGH)
                    end
                    sub_input_item.bus_din[sub_input_slice_count] = vif.mon_cb.din;
                    sub_input_slice_count++;
                    if (sub_input_slice_count > current_sub_M_minus_one) begin
                        sub_input_item.a = new[N];
                        foreach (sub_input_item.a[i]) sub_input_item.a[i] = new[current_sub_M_minus_one + 1];
                        sub_input_item.b = new[current_sub_M_minus_one + 1];
                        foreach (sub_input_item.b[m]) sub_input_item.b[m] = new[N];
                        for (int m = 0; m <= current_sub_M_minus_one; m++) begin
                            sub_input_item.unpack_bus(sub_input_item.bus_din[m], a_col, b_row);
                            for (int i = 0; i < N; i++) begin
                                sub_input_item.a[i][m] = $signed(a_col[i]);
                                sub_input_item.b[m][i] = $signed(b_row[i]);
                            end
                        end
                        ap_sub_input.write(sub_input_item);
                        `uvm_info(get_type_name(), $sformatf("Collected input: %s", sub_input_item.convert2string()), UVM_HIGH)
                        collecting_sub_input = 0;
                    end
                end

                if (vif.mon_cb.rd_fifo && !vif.mon_cb.out_fifo_empty) begin
                    if (!collecting_sub_output) begin
                        sub_output_item = resp_item::type_id::create("sub_output_item");
                        sub_output_item.M_minus_one = last_M_minus_one;
                        collecting_sub_output = 1;
                        sub_output_row_count = 0;
                        `uvm_info(get_type_name(), $sformatf("Starting output collection for M=%0d", last_M_minus_one + 1), UVM_HIGH)
                    end
                    c_unpack = {<<{vif.mon_cb.dout}};
                    for (int i = 0; i < N; i++)
                        sub_output_item.c_out[sub_output_row_count][i] = c_unpack[i];
                    sub_output_row_count++;
                    if (sub_output_row_count == N) begin
                        ap_sub_output.write(sub_output_item);
                        sub_output_count++;
                        `uvm_info(get_type_name(), $sformatf("Subsystem result #%0d:\n%s", sub_output_count, sub_output_item.convert2string()), UVM_HIGH)
                        collecting_sub_output = 0;
                    end
                end
            end
        end
    endtask

    // ------------------------
    // Systolic Array Monitor Task
    // ------------------------
    task automatic sa_monitor_task();
        bit sa_out_valid_prev = 0;
        logic signed [2*DIN_WIDTH-1:0] c_dout_prev [0:N-1];

        forever begin
            @(vif_sa.mon_cb);
            
            if (!vif_sa.mon_cb.rst_n) begin
                collecting_sa_output = 0;
                sa_output_row_count = 0;
                sa_output_item = null;
                sa_out_valid_prev = 0;
                c_dout_prev = '{default:'0};
            end else begin
                // Capture current values from the interface
                bit sa_out_valid_current = vif_sa.mon_cb.out_valid;
                logic signed [2*DIN_WIDTH-1:0] c_dout_current [0:N-1];
                for(int i=0; i<N; i++) begin
                    c_dout_current[i] = vif_sa.mon_cb.c_dout[i];
                end

                // --- State Machine Logic ---

                if (!collecting_sa_output) begin
                    // STATE: IDLE
                    // Look for the rising edge of 'out_valid'
                    bit sa_out_valid_rising_edge = sa_out_valid_current && !sa_out_valid_prev;
                    
                    if (sa_out_valid_rising_edge) begin
                        // Rising edge detected (e.g., at T+1).
                        // Create the item and move to STREAMING state.
                        // We will start sampling on the *next* cycle (T+2).
                        `uvm_info(get_type_name(), $sformatf("SA rising edge detected. Starting collection for M=%0d", last_M_minus_one + 1), UVM_HIGH)
                        collecting_sa_output = 1; 
                        sa_output_row_count = 0;
                        
                        sa_output_item = systolic_resp_item::type_id::create("sa_output_item");
                        sa_output_item.M_minus_one = last_M_minus_one;
                    end
                    
                end else begin
                    // STATE: STREAMING
                    // We are in the collection state (e.g., at T+2).
                    // Sample the data from the *previous* cycle (T+1),
                    // which is stored in 'c_dout_prev'.
                    
                    `uvm_info(get_type_name(), $sformatf("SA collecting row %0d using previous cycle's data", sa_output_row_count), UVM_HIGH)

                    for (int i = 0; i < N; i++) begin
                        sa_output_item.c_out[sa_output_row_count][i] = c_dout_prev[i];
                    end
                    sa_output_row_count++;
                    
                    if (sa_output_row_count == N) begin
                        // We have collected all N rows
                        ap_sa_output.write(sa_output_item);
                        sa_output_count++;
                        `uvm_info(get_type_name(), $sformatf("Systolic result #%0d:\n%s", sa_output_count, sa_output_item.convert2string()), UVM_HIGH)
                        collecting_sa_output = 0; // Go back to IDLE
                    end
                end
                sa_out_valid_prev = sa_out_valid_current;
                c_dout_prev       = c_dout_current;
            end
        end
    endtask
    
  
  
  
endclass

`endif // MONITOR_SV

