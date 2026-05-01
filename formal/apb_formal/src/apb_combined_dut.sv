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

module apb_gpio #(
    parameter ADDR_WIDTH =32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter GPIO_WIDTH = 8
) (
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

  input logic [GPIO_WIDTH-1:0] gpio_in,
  output logic [GPIO_WIDTH-1:0] gpio_out,
  output logic [GPIO_WIDTH-1:0] gpio_dir
);
 
localparam logic [7:0] GPIO_DATA_OFFSET = 8'h00;
localparam logic [7:0] GPIO_DIR_OFFSET = 8'h04;
localparam logic [7:0] GPIO_SET_OFFSET = 8'h08;
localparam logic [7:0] GPIO_CLEAR_OFFSET = 8'h0C;
localparam logic [7:0] GPIO_STATUS_OFFSET = 8'h10;

logic [7:0] addr_offset;
logic apb_access;
logic apb_write;
logic apb_read;
logic invalid_addr;

assign addr_offset = PADDR[7:0];

assign apb_access = PSEL && PENABLE;
assign apb_write = apb_access && PWRITE;
assign apb_read = apb_access && !PWRITE;

    always_comb begin
        invalid_addr = 1'b0;

        unique case (addr_offset)
            GPIO_DATA_OFFSET,
            GPIO_DIR_OFFSET,
            GPIO_SET_OFFSET,
            GPIO_CLEAR_OFFSET,
            GPIO_STATUS_OFFSET: invalid_addr = 1'b0;
            default:            invalid_addr = 1'b1;
        endcase
    end

    function automatic logic [DATA_WIDTH-1:0] apply_wstrb;
        input logic [DATA_WIDTH-1:0] old_data;
        input logic [DATA_WIDTH-1:0] new_data;
        input logic [STRB_WIDTH-1:0] strb;
        integer i;
        begin
            apply_wstrb = old_data;
            for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                if (strb[i]) begin
                    apply_wstrb[i*8 +: 8] = new_data[i*8 +: 8];
                end
            end
        end
    endfunction

    logic [DATA_WIDTH-1:0] gpio_data_full;
    logic [DATA_WIDTH-1:0] gpio_dir_full;
    
logic [DATA_WIDTH-1:0] gpio_data_wstrb;
logic [DATA_WIDTH-1:0] gpio_dir_wstrb;
logic [DATA_WIDTH-1:0] gpio_set_wstrb;
logic [DATA_WIDTH-1:0] gpio_clear_wstrb;

assign gpio_data_wstrb  = apply_wstrb(gpio_data_full, PWDATA, PSTRB);
assign gpio_dir_wstrb   = apply_wstrb(gpio_dir_full,  PWDATA, PSTRB);
assign gpio_set_wstrb   = apply_wstrb('0, PWDATA, PSTRB);
assign gpio_clear_wstrb = apply_wstrb('0, PWDATA, PSTRB);

    always_comb begin
        gpio_data_full = '0;
        gpio_dir_full  = '0;

        gpio_data_full[GPIO_WIDTH-1:0] = gpio_out;
        gpio_dir_full [GPIO_WIDTH-1:0] = gpio_dir;
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_out <= '0;
            gpio_dir <= '0;
        end
        else begin
            if (apb_write && !invalid_addr) begin
                unique case (addr_offset)
                    GPIO_DATA_OFFSET: begin
                     //   gpio_out <= apply_wstrb(gpio_data_full, PWDATA, PSTRB)[GPIO_WIDTH-1:0];                 
                        gpio_out <= gpio_data_wstrb[GPIO_WIDTH-1:0];
                    end 

                    GPIO_DIR_OFFSET: begin
                      //  gpio_dir <= apply_wstrb(gpio_dir_full, PWDATA, PSTRB)[GPIO_WIDTH-1:0];
                        gpio_dir <= gpio_dir_wstrb[GPIO_WIDTH-1:0];
                    end

                    GPIO_SET_OFFSET: begin
                    //    gpio_out <= gpio_out | PWDATA[GPIO_WIDTH-1:0];
                    //    gpio_out <= gpio_out | (apply_wstrb('0, PWDATA, PSTRB)[GPIO_WIDTH-1:0]);          
                    gpio_out <= gpio_out | gpio_set_wstrb[GPIO_WIDTH-1:0];        
                    end

                    GPIO_CLEAR_OFFSET: begin
                    //    gpio_out <= gpio_out & ~PWDATA[GPIO_WIDTH-1:0];
                     //  gpio_out <= gpio_out & ~(apply_wstrb('0, PWDATA, PSTRB)[GPIO_WIDTH-1:0]);
                       gpio_out <= gpio_out & ~gpio_clear_wstrb[GPIO_WIDTH-1:0];
                    end

                    GPIO_STATUS_OFFSET: begin
                        // STATUS is read-only. Write causes error through PSLVERR.
                       // PRDATA[GPIO_WIDTH-1:0] = gpio_in; 
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

    always_comb begin
        PRDATA = '0;

    if (apb_read && !invalid_addr) begin
        unique case (addr_offset)
            GPIO_DATA_OFFSET: begin
                PRDATA[GPIO_WIDTH-1:0] = gpio_out;
            end

            GPIO_DIR_OFFSET: begin
                PRDATA[GPIO_WIDTH-1:0] = gpio_dir;
            end

            GPIO_SET_OFFSET: begin
                PRDATA = '0;
            end

            GPIO_CLEAR_OFFSET: begin
                PRDATA = '0;
            end

            GPIO_STATUS_OFFSET: begin
                PRDATA[GPIO_WIDTH-1:0] = gpio_in;
            end

            default: begin
                PRDATA = '0;
            end
        endcase
    end
end

    always_comb begin
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        if (apb_access) begin
            if (invalid_addr) begin
                PSLVERR = 1'b1;
            end
            else if (PWRITE && (addr_offset == GPIO_STATUS_OFFSET)) begin
                PSLVERR = 1'b1;
            end
        end
    end

endmodule    
module apb_timer #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8
)(
    input  logic                  PCLK,
    input  logic                  PRESETn,

    input  logic [ADDR_WIDTH-1:0] PADDR,
    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [DATA_WIDTH-1:0] PWDATA,
    input  logic [STRB_WIDTH-1:0] PSTRB,
    input  logic [2:0]            PPROT,

    output logic                  PREADY,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PSLVERR,

    output logic                  timer_irq
);

    localparam logic [7:0] TIMER_CTRL_OFFSET   = 8'h00;
    localparam logic [7:0] TIMER_LOAD_OFFSET   = 8'h04;
    localparam logic [7:0] TIMER_COUNT_OFFSET  = 8'h08;
    localparam logic [7:0] TIMER_STATUS_OFFSET = 8'h0C;
    localparam logic [7:0] TIMER_CLEAR_OFFSET  = 8'h10;

    logic [7:0] addr_offset;

    logic apb_access;
    logic apb_write;
    logic apb_read;
    logic invalid_addr;

    logic [DATA_WIDTH-1:0] timer_ctrl;
    logic [DATA_WIDTH-1:0] timer_load;
    logic [DATA_WIDTH-1:0] timer_count;
    logic [DATA_WIDTH-1:0] timer_status;

    wire timer_enable = timer_ctrl[0];
    wire irq_enable   = timer_ctrl[1];

    assign addr_offset = PADDR[7:0];

    assign apb_access = PSEL && PENABLE;
    assign apb_write  = apb_access && PWRITE;
    assign apb_read   = apb_access && !PWRITE;

//APPLY_WSTRB FUNCTION
    function automatic logic [DATA_WIDTH-1:0] apply_wstrb;
        input logic [DATA_WIDTH-1:0] old_data;
        input logic [DATA_WIDTH-1:0] new_data;
        input logic [STRB_WIDTH-1:0] strb;
        integer i;
        begin
            apply_wstrb = old_data;
            for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                if (strb[i]) begin
                    apply_wstrb[i*8 +: 8] = new_data[i*8 +: 8];
                end
            end
        end
    endfunction

    always_comb begin
        invalid_addr = 1'b0;

        unique case (addr_offset)
            TIMER_CTRL_OFFSET,
            TIMER_LOAD_OFFSET,
            TIMER_COUNT_OFFSET,
            TIMER_STATUS_OFFSET,
            TIMER_CLEAR_OFFSET: invalid_addr = 1'b0;
            default:            invalid_addr = 1'b1;
        endcase
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            timer_ctrl   <= '0;
            timer_load   <= 32'd10;
            timer_count  <= '0;
            timer_status <= '0;
        end
        else begin
            if (timer_enable) begin
                if (timer_count >= timer_load) begin   
                    timer_count     <= '0;
                    timer_status[0] <= 1'b1;
                    if (irq_enable)
                        timer_status[1] <= 1'b1;
                end                                   
                else begin                             
                    timer_count <= timer_count + 1'b1;
                end
            end                                        


            if (apb_write && !invalid_addr) begin
                unique case (addr_offset)
                    TIMER_CTRL_OFFSET: begin
                        timer_ctrl <= apply_wstrb(timer_ctrl, PWDATA, PSTRB);
                    end

                    TIMER_LOAD_OFFSET: begin
                        timer_load <= apply_wstrb(timer_load, PWDATA, PSTRB);
                    end

                    TIMER_COUNT_OFFSET: begin
                        timer_count <= apply_wstrb(timer_count, PWDATA, PSTRB);
                    end

                    TIMER_CLEAR_OFFSET: begin
                    if (PSTRB[0]) begin
                        if (PWDATA[0]) begin
                            timer_status[0] <= 1'b0;
                        end
                        if (PWDATA[1]) begin
                            timer_status[1] <= 1'b0;
                        end
                    end
                    end

                    TIMER_STATUS_OFFSET: begin
                        // STATUS is read-only. Write produces PSLVERR.
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

    always_comb begin
        PRDATA = '0;

        unique case (addr_offset)
            TIMER_CTRL_OFFSET: begin
                PRDATA = timer_ctrl;
            end

            TIMER_LOAD_OFFSET: begin
                PRDATA = timer_load;
            end

            TIMER_COUNT_OFFSET: begin
                PRDATA = timer_count;
            end

            TIMER_STATUS_OFFSET: begin
                PRDATA = timer_status;
            end

            TIMER_CLEAR_OFFSET: begin
                PRDATA = '0;
            end

            default: begin
                PRDATA = '0;
            end
        endcase
    end

    always_comb begin
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        if (apb_access) begin
            if (invalid_addr) begin
                PSLVERR = 1'b1;
            end
            else if (PWRITE && (addr_offset == TIMER_STATUS_OFFSET)) begin
                PSLVERR = 1'b1;
            end
        end
    end

    assign timer_irq = timer_status[1];

endmodule

module apb_memory #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter MEM_DEPTH  = 256
)(
    input  logic                  PCLK,
    input  logic                  PRESETn,

    input  logic [ADDR_WIDTH-1:0] PADDR,
    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [DATA_WIDTH-1:0] PWDATA,
    input  logic [STRB_WIDTH-1:0] PSTRB,
    input  logic [2:0]            PPROT,

    output logic                  PREADY,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PSLVERR
);

    logic apb_access;
    logic apb_write;
    logic apb_read;

    logic [$clog2(MEM_DEPTH)-1:0] mem_index;
    logic invalid_index;

    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    integer i;

    assign apb_access = PSEL && PENABLE;
    assign apb_write  = apb_access && PWRITE;
    assign apb_read   = apb_access && !PWRITE;

   // assign mem_index = PADDR[9:2];
   localparam logic [ADDR_WIDTH-1:0] MEM_BASE = 32'h0000_0200;
    logic [ADDR_WIDTH-1:0] local_addr;
    assign local_addr = PADDR - MEM_BASE;
    assign mem_index  = local_addr[$clog2(MEM_DEPTH)+1:2];

    always_comb begin
        invalid_index = 1'b0;

        if (local_addr[1:0] != 2'b00) begin
            invalid_index = 1'b1;
        end
        else if (local_addr[$clog2(MEM_DEPTH)+1:2] >= MEM_DEPTH) begin
            invalid_index = 1'b1;
        end
    end

    function automatic logic [DATA_WIDTH-1:0] apply_wstrb;
        input logic [DATA_WIDTH-1:0] old_data;
        input logic [DATA_WIDTH-1:0] new_data;
        input logic [STRB_WIDTH-1:0] strb;
        integer j;
        begin
            apply_wstrb = old_data;
            for (j = 0; j < STRB_WIDTH; j = j + 1) begin
                if (strb[j]) begin
                    apply_wstrb[j*8 +: 8] = new_data[j*8 +: 8];
                end
            end
        end
    endfunction

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                mem[i] <= '0;
            end
        end
        else begin
            if (apb_write && !invalid_index) begin
                mem[mem_index] <= apply_wstrb(mem[mem_index], PWDATA, PSTRB);
            end
        end
    end

    always_comb begin
        PRDATA = '0;

        if (apb_read && !invalid_index) begin
            PRDATA = mem[mem_index];
        end
    end

    always_comb begin
        PREADY  = 1'b1;
        PSLVERR = 1'b0;

        if (apb_access && invalid_index) begin
            PSLVERR = 1'b1;
        end
    end

endmodule

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
