class apb_transaction extends uvm_sequence_item;

    rand apb_cmd_e              cmd;
    rand logic [ADDR_WIDTH-1:0] addr;
    rand logic [DATA_WIDTH-1:0] wdata;
    rand logic [STRB_WIDTH-1:0] strb;
    rand logic [2:0]            prot;

    logic [DATA_WIDTH-1:0]      rdata;
    logic                       slverr;

    constraint c_strb_nonzero {
        if (cmd == APB_WRITE)
            strb != 0;
    }

    constraint c_prot_default {
        prot inside {[0:7]};
    }

    `uvm_object_utils_begin(apb_transaction)
        `uvm_field_enum(apb_cmd_e, cmd, UVM_ALL_ON)
        `uvm_field_int(addr,   UVM_ALL_ON)
        `uvm_field_int(wdata,  UVM_ALL_ON)
        `uvm_field_int(strb,   UVM_ALL_ON)
        `uvm_field_int(prot,   UVM_ALL_ON)
        `uvm_field_int(rdata,  UVM_ALL_ON)
        `uvm_field_int(slverr, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_transaction");
        super.new(name);
    endfunction

endclass