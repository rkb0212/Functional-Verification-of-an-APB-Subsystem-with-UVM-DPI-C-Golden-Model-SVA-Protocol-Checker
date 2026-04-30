class apb_monitor extends uvm_component;

    `uvm_component_utils(apb_monitor)

    virtual apb_if.MON vif;

    uvm_analysis_port #(apb_transaction) ap;

    function new(string name = "apb_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual apb_if.MON)::get(this, "", "vif", vif)) begin
            `uvm_fatal(get_type_name(), "Could not get virtual interface for monitor")
        end
    endfunction

    task run_phase(uvm_phase phase);

        apb_transaction tr;

        forever begin
            @(vif.mon_cb);

            if (vif.mon_cb.PSEL &&
                vif.mon_cb.PENABLE &&
                vif.mon_cb.PREADY) begin

                tr = apb_transaction::type_id::create("tr", this);

                tr.cmd    = vif.mon_cb.PWRITE ? APB_WRITE : APB_READ;
                tr.addr   = vif.mon_cb.PADDR;
                tr.wdata  = vif.mon_cb.PWDATA;
                tr.strb   = vif.mon_cb.PSTRB;
                tr.prot   = vif.mon_cb.PPROT;
                tr.rdata  = vif.mon_cb.PRDATA;
                tr.slverr = vif.mon_cb.PSLVERR;

                ap.write(tr);

                `uvm_info(get_type_name(),
                    $sformatf("MON: %s addr=0x%08h wdata=0x%08h rdata=0x%08h slverr=%0b",
                    tr.cmd.name(), tr.addr, tr.wdata, tr.rdata, tr.slverr),
                    UVM_HIGH)
            end
        end

    endtask

endclass