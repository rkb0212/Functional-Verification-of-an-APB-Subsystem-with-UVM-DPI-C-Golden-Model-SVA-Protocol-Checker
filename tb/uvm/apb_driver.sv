// NOTE: compiled inside apb_pkg — all package symbols are in scope automatically.
// The wildcard import below is only needed if this file is ever compiled standalone.
class apb_driver extends uvm_driver #(apb_transaction);

    `uvm_component_utils(apb_driver)

    virtual apb_if.DRV vif;

    function new(string name = "apb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_if.DRV)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Could not get virtual interface for driver")
        end
    endfunction

    task run_phase(uvm_phase phase);

        reset_bus();

        forever begin
            seq_item_port.get_next_item(req);
            drive_transfer(req);
            seq_item_port.item_done();
        end

    endtask

    task reset_bus();

        vif.drv_cb.PSEL    <= 1'b0;
        vif.drv_cb.PENABLE <= 1'b0;
        vif.drv_cb.PWRITE  <= 1'b0;
        vif.drv_cb.PADDR   <= '0;
        vif.drv_cb.PWDATA  <= '0;
        vif.drv_cb.PSTRB   <= '0;
        vif.drv_cb.PPROT   <= '0;
        vif.drv_cb.gpio_in <= '0;

        wait (vif.PRESETn == 1'b1);
        repeat (2) @(vif.drv_cb);

    endtask

task drive_transfer(apb_transaction tr);

    // SETUP phase
    @(vif.drv_cb);
    vif.drv_cb.PSEL    <= 1'b1;
    vif.drv_cb.PENABLE <= 1'b0;
    vif.drv_cb.PWRITE  <= (tr.cmd == APB_WRITE);
    vif.drv_cb.PADDR   <= tr.addr;
    vif.drv_cb.PWDATA  <= tr.wdata;
    vif.drv_cb.PSTRB   <= tr.strb;
    vif.drv_cb.PPROT   <= tr.prot;

    // ACCESS phase
    @(vif.drv_cb);
    vif.drv_cb.PENABLE <= 1'b1;

    // Hold ACCESS phase for at least one sampled clock
    @(vif.drv_cb);

    while (vif.drv_cb.PREADY !== 1'b1) begin
        @(vif.drv_cb);
    end

    tr.rdata  = vif.drv_cb.PRDATA;
    tr.slverr = vif.drv_cb.PSLVERR;

    // Return to IDLE
    vif.drv_cb.PSEL    <= 1'b0;
    vif.drv_cb.PENABLE <= 1'b0;
    vif.drv_cb.PWRITE  <= 1'b0;
    vif.drv_cb.PADDR   <= '0;
    vif.drv_cb.PWDATA  <= '0;
    vif.drv_cb.PSTRB   <= '0;
    vif.drv_cb.PPROT   <= '0;

endtask
endclass