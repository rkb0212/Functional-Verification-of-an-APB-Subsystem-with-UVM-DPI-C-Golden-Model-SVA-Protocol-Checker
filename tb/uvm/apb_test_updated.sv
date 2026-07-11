class apb_base_test extends uvm_test;

    `uvm_component_utils(apb_base_test)

    apb_env env;

    function new(string name = "apb_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env = apb_env::type_id::create("env", this);
    endfunction

endclass


class apb_smoke_test extends apb_base_test;

    `uvm_component_utils(apb_smoke_test)

    function new(string name = "apb_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);

        apb_smoke_sequence smoke_seq;

        phase.raise_objection(this);

        smoke_seq = apb_smoke_sequence::type_id::create("smoke_seq");
        smoke_seq.start(env.agent.sequencer);

        #200ns;

        phase.drop_objection(this);

    endtask

endclass


class apb_random_test extends apb_base_test;

    `uvm_component_utils(apb_random_test)

    function new(string name = "apb_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);

        apb_random_sequence rand_seq;

        phase.raise_objection(this);

        rand_seq = apb_random_sequence::type_id::create("rand_seq");
        rand_seq.start(env.agent.sequencer);

        #200ns;

        phase.drop_objection(this);

    endtask

endclass


class apb_ral_smoke_test extends apb_base_test;

    `uvm_component_utils(apb_ral_smoke_test)

    function new(string name = "apb_ral_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);

        apb_ral_smoke_sequence ral_seq;

        phase.raise_objection(this);

        ral_seq = apb_ral_smoke_sequence::type_id::create("ral_seq");
        ral_seq.ral = env.ral;

        // Start on null because the register model already knows the APB
        // sequencer through ral.default_map.set_sequencer() in apb_env.
        ral_seq.start(null);

        #200ns;

        phase.drop_objection(this);

    endtask

endclass
