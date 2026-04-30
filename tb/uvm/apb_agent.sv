class apb_agent extends uvm_agent;

    `uvm_component_utils(apb_agent)

    uvm_sequencer #(apb_transaction) sequencer;
    apb_driver                     driver;
    apb_monitor                    monitor;

    function new(string name = "apb_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        sequencer = uvm_sequencer#(apb_transaction)::type_id::create("sequencer", this);
        driver    = apb_driver::type_id::create("driver", this);
        monitor   = apb_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass