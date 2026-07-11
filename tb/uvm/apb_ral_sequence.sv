// =============================================================================
// apb_ral_sequence.sv
// RAL smoke sequence for APB GPIO, timer, and memory.
// =============================================================================

class apb_ral_smoke_sequence extends uvm_sequence #(uvm_sequence_item);

  `uvm_object_utils(apb_ral_smoke_sequence)

  apb_reg_block ral;

  function new(string name = "apb_ral_smoke_sequence");
    super.new(name);
  endfunction

  task automatic ral_write(uvm_reg rg, logic [31:0] data);
    uvm_status_e status;

    rg.write(status, data, UVM_FRONTDOOR, .parent(this));

    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(),
        $sformatf("RAL WRITE failed: %s data=0x%08h", rg.get_full_name(), data))
    end else begin
      `uvm_info(get_type_name(),
        $sformatf("RAL WRITE %s = 0x%08h", rg.get_full_name(), data),
        UVM_MEDIUM)
    end
  endtask

  task automatic ral_read_check(uvm_reg rg, logic [31:0] expected,
                                bit do_check = 1'b1);
    uvm_status_e status;
    uvm_reg_data_t rdata;

    rg.read(status, rdata, UVM_FRONTDOOR, .parent(this));

    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(),
        $sformatf("RAL READ failed: %s", rg.get_full_name()))
    end else begin
      `uvm_info(get_type_name(),
        $sformatf("RAL READ  %s = 0x%08h", rg.get_full_name(), rdata[31:0]),
        UVM_MEDIUM)
    end

    if (do_check) begin
      if (rdata[31:0] !== expected) begin
        `uvm_error(get_type_name(),
          $sformatf("RAL CHECK FAIL %s actual=0x%08h expected=0x%08h",
                    rg.get_full_name(), rdata[31:0], expected))
      end else begin
        `uvm_info(get_type_name(),
          $sformatf("RAL CHECK PASS %s = 0x%08h",
                    rg.get_full_name(), expected),
          UVM_MEDIUM)
      end
    end
  endtask

  task automatic ral_mem_write(int unsigned word_idx, logic [31:0] data);
    uvm_status_e status;

    ral.scratch_mem.write(status, word_idx, data, UVM_FRONTDOOR, .parent(this));

    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(),
        $sformatf("RAL MEM WRITE failed: scratch_mem[%0d] data=0x%08h",
                  word_idx, data))
    end else begin
      `uvm_info(get_type_name(),
        $sformatf("RAL MEM WRITE scratch_mem[%0d] = 0x%08h", word_idx, data),
        UVM_MEDIUM)
    end
  endtask

  task automatic ral_mem_read_check(int unsigned word_idx, logic [31:0] expected);
    uvm_status_e status;
    uvm_reg_data_t rdata;

    ral.scratch_mem.read(status, word_idx, rdata, UVM_FRONTDOOR, .parent(this));

    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(),
        $sformatf("RAL MEM READ failed: scratch_mem[%0d]", word_idx))
    end else if (rdata[31:0] !== expected) begin
      `uvm_error(get_type_name(),
        $sformatf("RAL MEM CHECK FAIL scratch_mem[%0d] actual=0x%08h expected=0x%08h",
                  word_idx, rdata[31:0], expected))
    end else begin
      `uvm_info(get_type_name(),
        $sformatf("RAL MEM CHECK PASS scratch_mem[%0d] = 0x%08h",
                  word_idx, expected),
        UVM_MEDIUM)
    end
  endtask

  virtual task body();

    if (ral == null) begin
      `uvm_fatal(get_type_name(), "ral handle is null. Set ral_seq.ral = env.ral before start().")
    end

    `uvm_info(get_type_name(), "Starting APB RAL smoke sequence", UVM_MEDIUM)

    // ------------------------------------------------------------
    // Reset value checks
    // ------------------------------------------------------------
    ral_read_check(ral.gpio_data, 32'h0000_0000);
    ral_read_check(ral.gpio_dir,  32'h0000_0000);
    ral_read_check(ral.timer_ctrl, 32'h0000_0000);
    ral_read_check(ral.timer_load, 32'd10);

    // ------------------------------------------------------------
    // GPIO RW + side-effect registers
    // ------------------------------------------------------------
    ral_write     (ral.gpio_dir,  32'h0000_00FF);
    ral_read_check(ral.gpio_dir,  32'h0000_00FF);

    ral_write     (ral.gpio_data, 32'h0000_00A5);
    ral_read_check(ral.gpio_data, 32'h0000_00A5);

    // GPIO_SET is WO and updates gpio_data by ORing bits.
    ral_write     (ral.gpio_set, 32'h0000_000F);
    ral_read_check(ral.gpio_data, 32'h0000_00AF);

    // GPIO_CLEAR is WO and updates gpio_data by clearing bits.
    ral_write     (ral.gpio_clear, 32'h0000_0005);
    ral_read_check(ral.gpio_data, 32'h0000_00AA);

    // ------------------------------------------------------------
    // Timer basic register checks
    // Avoid strict checking of timer_count while timer is enabled because
    // it is volatile and changes with time.
    // ------------------------------------------------------------
    ral_write     (ral.timer_load, 32'd5);
    ral_read_check(ral.timer_load, 32'd5);

    ral_write     (ral.timer_ctrl, 32'h0000_0003); // enable + irq_enable
    ral_read_check(ral.timer_ctrl, 32'h0000_0003);

    // Volatile read: print only, no exact check.
    ral_read_check(ral.timer_count, 32'h0, 1'b0);
    ral_read_check(ral.timer_status, 32'h0, 1'b0);

    // Clear timer status bits. It is okay even if status is 0 at that moment.
    ral_write(ral.timer_clear, 32'h0000_0003);

    // ------------------------------------------------------------
    // APB memory window through uvm_mem
    // ------------------------------------------------------------
    ral_mem_write     (0, 32'hDEAD_BEEF); // address MEM_BASE + 0x00
    ral_mem_read_check(0, 32'hDEAD_BEEF);

    ral_mem_write     (1, 32'hCAFE_1234); // address MEM_BASE + 0x04
    ral_mem_read_check(1, 32'hCAFE_1234);

    `uvm_info(get_type_name(), "Finished APB RAL smoke sequence", UVM_MEDIUM)
  endtask

endclass
