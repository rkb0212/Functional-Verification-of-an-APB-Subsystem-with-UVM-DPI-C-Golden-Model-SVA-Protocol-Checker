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