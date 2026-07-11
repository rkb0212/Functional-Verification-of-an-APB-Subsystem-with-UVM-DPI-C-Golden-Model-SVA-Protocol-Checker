class apb_env extends uvm_env;

    `uvm_component_utils(apb_env)

    apb_agent      agent;
    apb_scoreboard scoreboard;
    apb_coverage   coverage;

    // RAL additions
    apb_reg_block                      ral;
    apb_reg_adapter                    ral_adapter;
    uvm_reg_predictor #(apb_transaction) ral_predictor;

    function new(string name = "apb_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent      = apb_agent::type_id::create("agent", this);
        scoreboard = apb_scoreboard::type_id::create("scoreboard", this);
        coverage   = apb_coverage::type_id::create("coverage", this);

        // RAL construction
        ral = apb_reg_block::type_id::create("ral", this);
        ral.build();

        ral_adapter = apb_reg_adapter::type_id::create("ral_adapter", this);
        ral_predictor = uvm_reg_predictor#(apb_transaction)::type_id::create("ral_predictor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        agent.monitor.ap.connect(scoreboard.imp);
        agent.monitor.ap.connect(coverage.imp);

        // RAL frontdoor path:
        // register.write/read -> RAL map -> adapter -> APB sequencer/driver
        ral.default_map.set_sequencer(agent.sequencer, ral_adapter);

        // RAL mirror prediction path:
        // APB monitor transaction -> predictor -> RAL mirror update
        agent.monitor.ap.connect(ral_predictor.bus_in);
        ral_predictor.map     = ral.default_map;
        ral_predictor.adapter = ral_adapter;
    endfunction

endclass
