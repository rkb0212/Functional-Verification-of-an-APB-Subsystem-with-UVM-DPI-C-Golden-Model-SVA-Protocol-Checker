module apb_decoder #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input logic [ADDR_WIDTH-1:0] PADDR,
    input logic PSEL,
    input logic PENABLE,

    output logic gpio_psel,
    output logic timer_psel,
    output logic mem_psel,
    output logic invalid_psel,

    input logic gpio_pready,
    input logic [DATA_WIDTH-1:0] gpio_prdata,
    input logic gpio_pslverr,

    input logic timer_pready,
    input logic [DATA_WIDTH-1:0] timer_prdata,
    input logic timer_pslverr,

    input logic mem_pready,
    input logic [DATA_WIDTH-1:0] mem_prdata,
    input logic mem_pslverr,

    output logic PREADY,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic PSLVERR
);

    localparam logic [ADDR_WIDTH-1:0] GPIO_BASE  = 32'h0000_0000;
    localparam logic [ADDR_WIDTH-1:0] GPIO_END   = 32'h0000_00FF;

    localparam logic [ADDR_WIDTH-1:0] TIMER_BASE = 32'h0000_0100;
    localparam logic [ADDR_WIDTH-1:0] TIMER_END  = 32'h0000_01FF;

    localparam logic [ADDR_WIDTH-1:0] MEM_BASE   = 32'h0000_0200;
    localparam logic [ADDR_WIDTH-1:0] MEM_END    = 32'h0000_02FF;

    always_comb begin            //SLAVE_SELECTION
        gpio_psel    = 1'b0;
        timer_psel   = 1'b0;
        mem_psel     = 1'b0;
        invalid_psel = 1'b0;

        if (PSEL) begin
            if ((PADDR >= GPIO_BASE) && (PADDR <= GPIO_END)) begin
                gpio_psel = 1'b1;
            end
            else if ((PADDR >= TIMER_BASE) && (PADDR <= TIMER_END)) begin
                timer_psel = 1'b1;
            end
            else if ((PADDR >= MEM_BASE) && (PADDR <= MEM_END)) begin
                mem_psel = 1'b1;
            end
            else begin
                invalid_psel = 1'b1;
            end
        end
    end

    always_comb begin 
        PREADY  = 1'b1;
        PRDATA  = '0;
        PSLVERR = 1'b0;

        if (gpio_psel) begin
            PREADY  = gpio_pready;
            PRDATA  = gpio_prdata;
            PSLVERR = gpio_pslverr;
        end
        else if (timer_psel) begin
            PREADY  = timer_pready;
            PRDATA  = timer_prdata;
            PSLVERR = timer_pslverr;
        end
        else if (mem_psel) begin
            PREADY  = mem_pready;
            PRDATA  = mem_prdata;
            PSLVERR = mem_pslverr;
        end
        else if (invalid_psel) begin
            PREADY  = 1'b1;
            PRDATA  = '0;
            PSLVERR = PENABLE;
        end
    end

endmodule