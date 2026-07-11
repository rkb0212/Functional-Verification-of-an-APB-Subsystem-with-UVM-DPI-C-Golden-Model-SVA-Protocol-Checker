// =============================================================================
// apb_reg_model.sv
// UVM RAL model for the APB subsystem register map.
//
// Address map used by current APB RTL/UVM package:
//   GPIO_BASE  = 0x0000_0000
//     GPIO_DATA   0x0000 RW
//     GPIO_DIR    0x0004 RW
//     GPIO_SET    0x0008 WO  side-effect: gpio_out |= WDATA
//     GPIO_CLEAR  0x000C WO  side-effect: gpio_out &= ~WDATA
//     GPIO_STATUS 0x0010 RO  reflects gpio_in
//
//   TIMER_BASE = 0x0000_0100
//     TIMER_CTRL   0x0100 RW
//     TIMER_LOAD   0x0104 RW reset=10
//     TIMER_COUNT  0x0108 RW/volatile because timer can change it
//     TIMER_STATUS 0x010C RO/volatile
//     TIMER_CLEAR  0x0110 WO side-effect: clears status bits
//
//   MEM_BASE   = 0x0000_0200
//     256 x 32-bit scratch memory modeled as uvm_mem
// =============================================================================

class apb_32b_reg extends uvm_reg;

  `uvm_object_utils(apb_32b_reg)

  rand uvm_reg_field f;

  string       access_policy;
  bit          is_volatile;
  uvm_reg_data_t reset_value;

  function new(string name = "apb_32b_reg",
               string access_policy = "RW",
               uvm_reg_data_t reset_value = 32'h0000_0000,
               bit is_volatile = 1'b0);
    super.new(name, 32, UVM_NO_COVERAGE);
    this.access_policy = access_policy;
    this.reset_value   = reset_value;
    this.is_volatile   = is_volatile;
  endfunction

  virtual function void build();
    f = uvm_reg_field::type_id::create("f");
    f.configure(
      .parent                 (this),
      .size                   (32),
      .lsb_pos                (0),
      .access                 (access_policy),
      .volatile               (is_volatile),
      .reset                  (reset_value),
      .has_reset              (1),
      .is_rand                ((access_policy == "RW") ? 1 : 0),
      .individually_accessible(1)
    );
  endfunction

endclass


class apb_reg_block extends uvm_reg_block;

  `uvm_object_utils(apb_reg_block)

  // GPIO registers
  rand apb_32b_reg gpio_data;
  rand apb_32b_reg gpio_dir;
       apb_32b_reg gpio_set;
       apb_32b_reg gpio_clear;
       apb_32b_reg gpio_status;

  // Timer registers
  rand apb_32b_reg timer_ctrl;
  rand apb_32b_reg timer_load;
  rand apb_32b_reg timer_count;
       apb_32b_reg timer_status;
       apb_32b_reg timer_clear;

  // APB memory window
  uvm_mem scratch_mem;

  function new(string name = "apb_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();

    // ------------------------------------------------------------
    // GPIO register construction
    // ------------------------------------------------------------
    gpio_data = apb_32b_reg::type_id::create("gpio_data");
    gpio_data.configure(this, null, "");
    gpio_data.build();

    gpio_dir = apb_32b_reg::type_id::create("gpio_dir");
    gpio_dir.configure(this, null, "");
    gpio_dir.build();

    gpio_set = apb_32b_reg::type_id::create("gpio_set");
    gpio_set.access_policy = "WO";
    gpio_set.configure(this, null, "");
    gpio_set.build();

    gpio_clear = apb_32b_reg::type_id::create("gpio_clear");
    gpio_clear.access_policy = "WO";
    gpio_clear.configure(this, null, "");
    gpio_clear.build();

    gpio_status = apb_32b_reg::type_id::create("gpio_status");
    gpio_status.access_policy = "RO";
    gpio_status.is_volatile   = 1'b1;
    gpio_status.configure(this, null, "");
    gpio_status.build();

    // ------------------------------------------------------------
    // Timer register construction
    // ------------------------------------------------------------
    timer_ctrl = apb_32b_reg::type_id::create("timer_ctrl");
    timer_ctrl.configure(this, null, "");
    timer_ctrl.build();

    timer_load = apb_32b_reg::type_id::create("timer_load");
    timer_load.reset_value = 32'd10;
    timer_load.configure(this, null, "");
    timer_load.build();

    timer_count = apb_32b_reg::type_id::create("timer_count");
    timer_count.is_volatile = 1'b1;
    timer_count.configure(this, null, "");
    timer_count.build();

    timer_status = apb_32b_reg::type_id::create("timer_status");
    timer_status.access_policy = "RO";
    timer_status.is_volatile   = 1'b1;
    timer_status.configure(this, null, "");
    timer_status.build();

    timer_clear = apb_32b_reg::type_id::create("timer_clear");
    timer_clear.access_policy = "WO";
    timer_clear.configure(this, null, "");
    timer_clear.build();

    // 256 x 32-bit memory region from 0x200 to 0x2FC
    scratch_mem = new("scratch_mem", 256, 32, "RW", UVM_NO_COVERAGE);
    scratch_mem.configure(this, "");

    // ------------------------------------------------------------
    // Address map
    // n_bytes=4 because APB data bus is 32-bit.
    // byte_addressing=1 because addresses are byte addresses.
    // ------------------------------------------------------------
    default_map = create_map("default_map", 32'h0000_0000, 4,
                             UVM_LITTLE_ENDIAN, 1);

    default_map.add_reg(gpio_data,   GPIO_DATA,   "RW");
    default_map.add_reg(gpio_dir,    GPIO_DIR,    "RW");
    default_map.add_reg(gpio_set,    GPIO_SET,    "WO");
    default_map.add_reg(gpio_clear,  GPIO_CLEAR,  "WO");
    default_map.add_reg(gpio_status, GPIO_STATUS, "RO");

    default_map.add_reg(timer_ctrl,   TIMER_CTRL,   "RW");
    default_map.add_reg(timer_load,   TIMER_LOAD,   "RW");
    default_map.add_reg(timer_count,  TIMER_COUNT,  "RW");
    default_map.add_reg(timer_status, TIMER_STATUS, "RO");
    default_map.add_reg(timer_clear,  TIMER_CLEAR,  "WO");

    default_map.add_mem(scratch_mem, MEM_BASE, "RW");

    // Use monitor predictor, not auto-predict.
    default_map.set_auto_predict(0);

    lock_model();
  endfunction

endclass
