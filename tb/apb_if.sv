interface apb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter GPIO_WIDTH = 8
)(
    input logic PCLK,
    input logic PRESETn
);
    logic                  PSEL;
    logic                  PENABLE;
    logic                  PWRITE;
    logic [ADDR_WIDTH-1:0] PADDR;
    logic [DATA_WIDTH-1:0] PWDATA;
    logic [STRB_WIDTH-1:0] PSTRB;
    logic [2:0]            PPROT;

    logic                  PREADY;
    logic                  PSLVERR;
    logic [DATA_WIDTH-1:0] PRDATA;

    logic                  timer_irq;
    logic [GPIO_WIDTH-1:0] gpio_in;
    logic [GPIO_WIDTH-1:0] gpio_out;
    logic [GPIO_WIDTH-1:0] gpio_dir;

    clocking drv_cb @(posedge PCLK);
        default input #1step output #1step;

        output PSEL;
        output PENABLE;
        output PWRITE;
        output PADDR;
        output PWDATA;
        output PSTRB;
        output PPROT;
        output gpio_in;

        input PREADY;
        input PSLVERR;
        input PRDATA;
        input timer_irq;
        input gpio_out;
        input gpio_dir;
    endclocking

    clocking mon_cb @(posedge PCLK);
        default input #1step output #1step;

        input PSEL;
        input PENABLE;
        input PWRITE;
        input PADDR;
        input PWDATA;
        input PSTRB;
        input PPROT;
        input PREADY;
        input PSLVERR;
        input PRDATA;
        input timer_irq;
        input gpio_in;
        input gpio_out;
        input gpio_dir;
    endclocking

    modport DRV(clocking drv_cb, input PCLK, input PRESETn);
    modport MON(clocking mon_cb, input PCLK, input PRESETn);

endinterface