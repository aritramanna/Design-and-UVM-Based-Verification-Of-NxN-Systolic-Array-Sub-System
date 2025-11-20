`ifndef DRIVER_SV
`define DRIVER_SV

class driver extends uvm_driver #(seq_item);
    `uvm_component_utils(driver)

    virtual sub_sys_if #(DIN_WIDTH, N, BUS_WIDTH) vif;
    seq_item req;
    int idx;

    function new(string name = "driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sub_sys_if #(DIN_WIDTH, N, BUS_WIDTH))::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Virtual interface could not be retrieved")
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        vif.drv_cb.wr_fifo      <= 1'b0;
        vif.drv_cb.rd_fifo      <= 1'b0;
        vif.drv_cb.din          <= '0;
        vif.drv_cb.M_minus_one  <= '0;
        
        wait(vif.drv_cb.rst_n);
        @(vif.drv_cb);
        `uvm_info(get_type_name(), "Reset De-Asserted....", UVM_LOW)
        
        fork
            drive_items();
            rd_task();
        join_none
    endtask
  
    virtual task drive_items();
        forever begin
            vif.drv_cb.wr_fifo <= 1'b0;
            vif.drv_cb.din     <= '0;

            `uvm_info(get_type_name(), $sformatf("Waiting for sequence item at %0t", $time), UVM_HIGH)
            seq_item_port.get_next_item(req);
            `uvm_info(get_type_name(), $sformatf("Got item at %0t starting [New Operation]", $time), UVM_HIGH)

            vif.drv_cb.M_minus_one <= req.M_minus_one;
            @(vif.drv_cb);
            repeat (req.delay) @(vif.drv_cb); 

            for (int i = 0; i < req.bus_din.size(); i++) begin
                @(vif.drv_cb);
                wait (!vif.drv_cb.in_fifo_full);

                vif.drv_cb.din     <= req.bus_din[i];
                vif.drv_cb.wr_fifo <= 1'b1;

                `uvm_info(get_type_name(),
                    $sformatf("Writing data[%0d]: 0x%0h", i, req.bus_din[i]),
                    UVM_HIGH)
            end

           @(vif.drv_cb);
           vif.drv_cb.wr_fifo <= 1'b0;

            seq_item_port.item_done();
        end
    endtask
  
    virtual task rd_task();
        forever begin
            @(vif.drv_cb); 
            if (!vif.drv_cb.out_fifo_empty) begin
                vif.drv_cb.rd_fifo <= 1'b1;
                @(vif.drv_cb);
                `uvm_info(get_type_name(),
                    $sformatf("Read data from Sub-System FIFO: 0x%0h", vif.drv_cb.dout),
                    UVM_HIGH)
                vif.drv_cb.rd_fifo <= 1'b0;
            end 
            else begin
                vif.drv_cb.rd_fifo <= 1'b0;
                `uvm_info(get_type_name(), "Output FIFO empty - waiting for data", UVM_HIGH)
            end
        end
    endtask

endclass : driver

`endif // DRIVER_SV
