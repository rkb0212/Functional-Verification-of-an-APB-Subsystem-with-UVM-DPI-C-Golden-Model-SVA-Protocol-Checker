class apb_coverage extends uvm_component;

    `uvm_component_utils(apb_coverage)

    uvm_analysis_imp #(apb_transaction, apb_coverage) imp;

    apb_transaction tr;

    covergroup apb_cg;

        option.per_instance = 1;

        cp_cmd: coverpoint tr.cmd {
            bins read  = {APB_READ};
            bins write = {APB_WRITE};
        }

        cp_region: coverpoint tr.addr {
            bins gpio  = {[32'h0000_0000:32'h0000_00FF]};
            bins timer = {[32'h0000_0100:32'h0000_01FF]};
            bins mem   = {[32'h0000_0200:32'h0000_02FF]};
            bins invalid = default;
        }

        cp_gpio_offsets: coverpoint tr.addr[7:0] iff (tr.addr inside {[32'h0000_0000:32'h0000_00FF]}) {
            bins data   = {8'h00};
            bins dir    = {8'h04};
            bins set    = {8'h08};
            bins clear  = {8'h0C};
            bins status = {8'h10};
            bins invalid_offsets = default;
        }

        cp_timer_offsets: coverpoint tr.addr[7:0] iff (tr.addr inside {[32'h0000_0100:32'h0000_01FF]}) {
            bins ctrl   = {8'h00};
            bins load   = {8'h04};
            bins count  = {8'h08};
            bins status = {8'h0C};
            bins clear  = {8'h10};
            bins invalid_offsets = default;
        }

        cp_strb: coverpoint tr.strb {
            bins byte0 = {4'b0001};
            bins byte1 = {4'b0010};
            bins byte2 = {4'b0100};
            bins byte3 = {4'b1000};
            bins lower_half = {4'b0011};
            bins upper_half = {4'b1100};
            bins full_word  = {4'b1111};
        }

        cp_slverr: coverpoint tr.slverr {
            bins no_error = {0};
            bins error    = {1};
        }

        cross_cmd_region: cross cp_cmd, cp_region;

    endgroup

    function new(string name = "apb_coverage", uvm_component parent = null);
        super.new(name, parent);
        imp = new("imp", this);
        apb_cg = new();
    endfunction

    function void write(apb_transaction t);
        tr = t;
        apb_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(),
            $sformatf("APB functional coverage = %0.2f%%", apb_cg.get_coverage()),
            UVM_NONE)
    endfunction

endclass