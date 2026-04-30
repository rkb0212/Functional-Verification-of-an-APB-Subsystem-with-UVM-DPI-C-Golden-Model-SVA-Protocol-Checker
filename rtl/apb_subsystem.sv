//apb_subsystem.sv
module apb_subsystem #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter STRB_WIDTH = DATA_WIDTH/8,
  parameter GPIO_WIDTH = 8,
  parameter MEM_DEPTH = 256		) (
  
  input logic PCLK, 
  input logic PRESETn, 

  input logic PSEL, 
  input logic PENABLE, 
  input logic PWRITE,
  input logic [ADDR_WIDTH-1:0] PADDR,
  input logic [DATA_WIDTH-1:0] PWDATA,
  input logic [STRB_WIDTH-1:0] PSTRB,
  input logic [2:0] PPROT,

  output logic PREADY, 
  output logic PSLVERR, 
  output logic [DATA_WIDTH-1:0] PRDATA,

  output logic timer_irq,
  input logic [GPIO_WIDTH-1:0] gpio_in,
  output logic [GPIO_WIDTH-1:0] gpio_out,
  output logic [GPIO_WIDTH-1:0] gpio_dir	);
  
  logic gpio_psel;
  logic timer_psel;
  logic mem_psel;
  logic invalid_psel;
  
  logic gpio_pready;
  logic [DATA_WIDTH-1:0] gpio_prdata;
  logic gpio_pslverr;
  
  logic timer_pready;
  logic [DATA_WIDTH-1:0] timer_prdata;
  logic timer_pslverr;  
  
  logic mem_pready;
  logic [DATA_WIDTH-1:0] mem_prdata;
  logic mem_pslverr;  
  
    apb_decoder #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_decoder (
    .PADDR(PADDR),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .gpio_psel(gpio_psel),
    .timer_psel(timer_psel),
    .mem_psel(mem_psel),
    .invalid_psel(invalid_psel),
    
    .gpio_pready(gpio_pready),
    .gpio_prdata(gpio_prdata), 
    .gpio_pslverr(gpio_pslverr),
  
    .timer_pready(timer_pready),
    .timer_prdata(timer_prdata), 
    .timer_pslverr(timer_pslverr),
    
    .mem_pready(mem_pready),
    .mem_prdata(mem_prdata), 
    .mem_pslverr(mem_pslverr),
    
    .PREADY(PREADY),
    .PRDATA(PRDATA),
    .PSLVERR(PSLVERR) );
  
    apb_gpio #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .GPIO_WIDTH(GPIO_WIDTH)
    ) u_gpio (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),

        .PADDR   (PADDR),
        .PSEL    (gpio_psel),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PPROT   (PPROT),

        .PREADY  (gpio_pready),
        .PRDATA  (gpio_prdata),
        .PSLVERR (gpio_pslverr),

        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .gpio_dir (gpio_dir)
    );
  
    apb_timer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) u_timer (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),

        .PADDR   (PADDR),
        .PSEL    (timer_psel),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PPROT   (PPROT),

        .PREADY  (timer_pready),
        .PRDATA  (timer_prdata),
        .PSLVERR (timer_pslverr),

        .timer_irq(timer_irq)
    );

    apb_memory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_memory (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),

        .PADDR   (PADDR),
        .PSEL    (mem_psel),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PPROT   (PPROT),

        .PREADY  (mem_pready),
        .PRDATA  (mem_prdata),
        .PSLVERR (mem_pslverr)
    );

endmodule