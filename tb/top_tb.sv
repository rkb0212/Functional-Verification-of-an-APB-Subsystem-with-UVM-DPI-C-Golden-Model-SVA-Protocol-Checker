`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

`include "apb_if.sv"
`include "apb_sva.sv"
`include "apb_pkg.sv"

module top_tb;

    import apb_pkg::*;

    logic PCLK;
    logic PRESETn;

    apb_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .GPIO_WIDTH(GPIO_WIDTH)
    ) apb_vif (
        .PCLK(PCLK),
        .PRESETn(PRESETn)
    );

    apb_subsystem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .GPIO_WIDTH(GPIO_WIDTH),
        .MEM_DEPTH(256)
    ) dut (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),

        .PSEL     (apb_vif.PSEL),
        .PENABLE  (apb_vif.PENABLE),
        .PWRITE   (apb_vif.PWRITE),
        .PADDR    (apb_vif.PADDR),
        .PWDATA   (apb_vif.PWDATA),
        .PSTRB    (apb_vif.PSTRB),
        .PPROT    (apb_vif.PPROT),

        .PREADY   (apb_vif.PREADY),
        .PSLVERR  (apb_vif.PSLVERR),
        .PRDATA   (apb_vif.PRDATA),

        .timer_irq(apb_vif.timer_irq),
        .gpio_in  (apb_vif.gpio_in),
        .gpio_out (apb_vif.gpio_out),
        .gpio_dir (apb_vif.gpio_dir)
    );

    apb_sva #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) u_apb_sva (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),

        .PSEL    (apb_vif.PSEL),
        .PENABLE (apb_vif.PENABLE),
        .PWRITE  (apb_vif.PWRITE),
        .PADDR   (apb_vif.PADDR),
        .PWDATA  (apb_vif.PWDATA),
        .PSTRB   (apb_vif.PSTRB),
        .PPROT   (apb_vif.PPROT),

        .PREADY  (apb_vif.PREADY),
        .PSLVERR (apb_vif.PSLVERR),
        .PRDATA  (apb_vif.PRDATA)
    );

    initial begin
        PCLK = 1'b0;
        forever #5 PCLK = ~PCLK;
    end

    initial begin
        PRESETn = 1'b0;
        repeat (20) @(posedge PCLK);
        PRESETn = 1'b1;
    end

    initial begin
        uvm_config_db#(virtual apb_if.DRV)::set(null, "uvm_test_top.env.agent.driver", "vif", apb_vif);
        uvm_config_db#(virtual apb_if.MON)::set(null, "uvm_test_top.env.agent.monitor", "vif", apb_vif);
 //   uvm_config_db#(virtual apb_if.DRV)::set(null, "uvm_test_top.*", "vif", apb_vif);
 //   uvm_config_db#(virtual apb_if.MON)::set(null, "uvm_test_top.*", "vif", apb_vif);

     //   run_test("apb_smoke_test");
        run_test("apb_random_test");
    end

    initial begin
        $dumpfile("apb_subsystem.vcd");
        $dumpvars(0, top_tb);
    end

endmodule