// =============================================================================
// apb_reg_adapter.sv
// Converts UVM RAL register operations into your existing apb_transaction item.
// =============================================================================

class apb_reg_adapter extends uvm_reg_adapter;

  `uvm_object_utils(apb_reg_adapter)

  function new(string name = "apb_reg_adapter");
    super.new(name);

    // Your driver completes the same request item and updates rdata/slverr
    // before item_done(), so no separate response item is required.
    provides_responses = 0;
    supports_byte_enable = 1;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    apb_transaction tr;

    tr = apb_transaction::type_id::create("tr");

    tr.cmd   = (rw.kind == UVM_READ) ? APB_READ : APB_WRITE;
    tr.addr  = rw.addr[ADDR_WIDTH-1:0];
    tr.wdata = rw.data[DATA_WIDTH-1:0];

    // RAL byte enables map directly to APB PSTRB.
    // For normal 32-bit register writes, RAL generally gives 4'hF.
    // If byte_en is zero, default to full-word write for safety.
    if (rw.kind == UVM_WRITE) begin
      tr.strb = (rw.byte_en[STRB_WIDTH-1:0] == '0) ? {STRB_WIDTH{1'b1}}
                                                    : rw.byte_en[STRB_WIDTH-1:0];
    end else begin
      tr.strb = '0;
    end

    tr.prot   = 3'b000;
    tr.rdata  = '0;
    tr.slverr = 1'b0;

    return tr;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item,
                                ref uvm_reg_bus_op rw);
    apb_transaction tr;

    if (!$cast(tr, bus_item)) begin
      `uvm_fatal(get_type_name(), "bus_item is not an apb_transaction")
    end

    rw.kind    = (tr.cmd == APB_READ) ? UVM_READ : UVM_WRITE;
    rw.addr    = tr.addr;
    rw.data    = (tr.cmd == APB_READ) ? tr.rdata : tr.wdata;
    rw.byte_en = tr.strb;
    rw.status  = tr.slverr ? UVM_NOT_OK : UVM_IS_OK;
  endfunction

endclass
