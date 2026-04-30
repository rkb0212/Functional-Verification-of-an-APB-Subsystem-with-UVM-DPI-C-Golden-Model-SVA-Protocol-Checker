import "DPI-C" function void apb_c_reset();

import "DPI-C" function void apb_c_write(
    input int unsigned addr,
    input int unsigned data,
    input byte unsigned strb
);

import "DPI-C" function int unsigned apb_c_read(
    input int unsigned addr
);

import "DPI-C" function byte unsigned apb_c_slverr(
    input int unsigned addr,
    input byte unsigned is_write
);


class apb_scoreboard extends uvm_component;

    `uvm_component_utils(apb_scoreboard)

    uvm_analysis_imp #(apb_transaction, apb_scoreboard) imp;

    function new(string name = "apb_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp = new("imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Reset C/C++ golden model at start of simulation
        apb_c_reset();

        `uvm_info(get_type_name(),
            "DPI-C APB golden model reset complete",
            UVM_LOW)
    endfunction


    function bit is_timer_dynamic_read(apb_transaction tr);

        if (tr.cmd == APB_READ &&
           ((tr.addr == 32'h0000_0108) ||   // TIMER_COUNT
            (tr.addr == 32'h0000_010C)))    // TIMER_STATUS
            return 1;

        return 0;

    endfunction


    function void write(apb_transaction tr);

        int unsigned expected_data;
        byte unsigned expected_err;
        byte unsigned is_write;

        is_write = (tr.cmd == APB_WRITE);

        expected_err = apb_c_slverr(
            tr.addr,
            is_write
        );

        // ------------------------------------------------------------
        // 1. Compare PSLVERR first for both read and write
        // ------------------------------------------------------------
        if (tr.slverr !== expected_err) begin
            `uvm_error(get_type_name(),
                $sformatf("DPI PSLVERR mismatch addr=0x%08h cmd=%s expected=%0b actual=%0b",
                tr.addr, tr.cmd.name(), expected_err, tr.slverr))
        end

        // ------------------------------------------------------------
        // 2. For write transaction, update C model after checking error
        // ------------------------------------------------------------
        if (tr.cmd == APB_WRITE) begin

            if (!expected_err) begin
                apb_c_write(
                    tr.addr,
                    tr.wdata,
                    tr.strb
                );

                `uvm_info(get_type_name(),
                    $sformatf("DPI WRITE model update addr=0x%08h data=0x%08h strb=0x%0h",
                    tr.addr, tr.wdata, tr.strb),
                    UVM_HIGH)
            end
            else begin
                `uvm_info(get_type_name(),
                    $sformatf("DPI WRITE expected error addr=0x%08h data=0x%08h",
                    tr.addr, tr.wdata),
                    UVM_LOW)
            end

            return;
        end

        // ------------------------------------------------------------
        // 3. For read with expected error, do not compare PRDATA
        // ------------------------------------------------------------
        if (expected_err) begin
       /*     `uvm_info(get_type_name(),
                $sformatf("DPI READ expected error addr=0x%08h rdata=0x%08h",
                tr.addr, tr.rdata),
                UVM_LOW) */
      `uvm_info(get_type_name(),
          $sformatf("DPI READ expected error addr=0x%08h DUT_PSLVERR=%0b DPI_EXPECTED_PSLVERR=%0b rdata=0x%08h",
          tr.addr, tr.slverr, expected_err, tr.rdata),
          UVM_LOW)
            return;
        end

        // ------------------------------------------------------------
        // 4. Skip exact compare for dynamic timer registers
        // ------------------------------------------------------------
        if (is_timer_dynamic_read(tr)) begin
            `uvm_info(get_type_name(),
                $sformatf("DPI TIMER dynamic read observed addr=0x%08h rdata=0x%08h",
                tr.addr, tr.rdata),
                UVM_LOW)
            return;
        end

        // ------------------------------------------------------------
        // 5. Normal read comparison against C model
        // ------------------------------------------------------------
        expected_data = apb_c_read(tr.addr);

        if (tr.rdata !== expected_data) begin
            `uvm_error(get_type_name(),
                $sformatf("DPI READ mismatch addr=0x%08h expected=0x%08h actual=0x%08h",
                tr.addr, expected_data, tr.rdata))
        end
        else begin
    `uvm_info(get_type_name(),
        $sformatf("DPI READ PASS addr=0x%08h DUT_PRDATA=0x%08h DPI_EXPECTED=0x%08h",
        tr.addr, tr.rdata, expected_data),
        UVM_LOW)
        end

    endfunction

endclass