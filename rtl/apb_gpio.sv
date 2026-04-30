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
                        gpio_out <= apply_wstrb(gpio_data_full, PWDATA, PSTRB)[GPIO_WIDTH-1:0];                 
                    end 

                    GPIO_DIR_OFFSET: begin
                        gpio_dir <= apply_wstrb(gpio_dir_full, PWDATA, PSTRB)[GPIO_WIDTH-1:0];
                    end

                    GPIO_SET_OFFSET: begin
                    //    gpio_out <= gpio_out | PWDATA[GPIO_WIDTH-1:0];
                        gpio_out <= gpio_out | (apply_wstrb('0, PWDATA, PSTRB)[GPIO_WIDTH-1:0]);                  
                    end

                    GPIO_CLEAR_OFFSET: begin
                    //    gpio_out <= gpio_out & ~PWDATA[GPIO_WIDTH-1:0];
                       gpio_out <= gpio_out & ~(apply_wstrb('0, PWDATA, PSTRB)[GPIO_WIDTH-1:0]);
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
