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