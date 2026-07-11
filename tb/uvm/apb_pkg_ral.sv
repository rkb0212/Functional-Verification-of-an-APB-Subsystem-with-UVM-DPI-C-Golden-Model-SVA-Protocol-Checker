package apb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter STRB_WIDTH = DATA_WIDTH/8;
    parameter GPIO_WIDTH = 8;

    localparam logic [31:0] GPIO_BASE  = 32'h0000_0000;
    localparam logic [31:0] TIMER_BASE = 32'h0000_0100;
    localparam logic [31:0] MEM_BASE   = 32'h0000_0200;

    localparam logic [31:0] GPIO_DATA   = GPIO_BASE  + 32'h00;
    localparam logic [31:0] GPIO_DIR    = GPIO_BASE  + 32'h04;
    localparam logic [31:0] GPIO_SET    = GPIO_BASE  + 32'h08;
    localparam logic [31:0] GPIO_CLEAR  = GPIO_BASE  + 32'h0C;
    localparam logic [31:0] GPIO_STATUS = GPIO_BASE  + 32'h10;

    localparam logic [31:0] TIMER_CTRL   = TIMER_BASE + 32'h00;
    localparam logic [31:0] TIMER_LOAD   = TIMER_BASE + 32'h04;
    localparam logic [31:0] TIMER_COUNT  = TIMER_BASE + 32'h08;
    localparam logic [31:0] TIMER_STATUS = TIMER_BASE + 32'h0C;
    localparam logic [31:0] TIMER_CLEAR  = TIMER_BASE + 32'h10;

    typedef enum {
        APB_READ,
        APB_WRITE
    } apb_cmd_e;

    `include "apb_transaction.sv"

    // RAL files: include after apb_transaction because adapter uses
    // apb_transaction/apb_cmd_e, and before env/test because env/test use RAL.
    `include "apb_reg_model.sv"
    `include "apb_reg_adapter.sv"

    `include "apb_sequence.sv"
    `include "apb_ral_sequence.sv"

    `include "apb_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_scoreboard.sv"
    `include "apb_coverage.sv"
    `include "apb_agent.sv"
    `include "apb_env.sv"
    `include "apb_test.sv"

endpackage
