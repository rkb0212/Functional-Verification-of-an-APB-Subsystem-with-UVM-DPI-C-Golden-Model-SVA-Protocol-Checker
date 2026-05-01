`default_nettype none

module apb_formal_top (
    input  logic        PCLK,

    input  logic        PRESETn,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic [3:0]  PSTRB,
    input  logic [2:0]  PPROT,
    input  logic [7:0]  gpio_in
);

    logic        PREADY;
    logic        PSLVERR;
    logic [31:0] PRDATA;

    logic        timer_irq;
    logic [7:0]  gpio_out;
    logic [7:0]  gpio_dir;

/*    logic f_past_valid;

    always_ff @(posedge PCLK) begin
        f_past_valid <= 1'b1;
    end   */
    logic f_past_valid = 1'b0;

initial begin
    assume(f_past_valid == 1'b0);
    assume(PRESETn == 1'b0);
end

always_ff @(posedge PCLK) begin
    f_past_valid <= 1'b1;
end

    apb_subsystem #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .STRB_WIDTH (4),
        .GPIO_WIDTH (8),
        .MEM_DEPTH  (16)
    ) dut (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),

        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR),
        .PWDATA    (PWDATA),
        .PSTRB     (PSTRB),
        .PPROT     (PPROT),

        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR),
        .PRDATA    (PRDATA),

        .timer_irq (timer_irq),
        .gpio_in   (gpio_in),
        .gpio_out  (gpio_out),
        .gpio_dir  (gpio_dir)
    );

    // ------------------------------------------------------------
    // RESET ASSUMPTION
    // ------------------------------------------------------------
always_ff @(posedge PCLK) begin
    if (!f_past_valid) begin
        assume(PRESETn == 1'b0);
    end
    else begin
        assume(PRESETn == 1'b1);
    end
end

    // ------------------------------------------------------------
    // APB MASTER PROTOCOL ASSUMPTIONS
    // These constrain the environment driving the DUT.
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (PRESETn) begin

            // PENABLE should never be high when PSEL is low.
            if (PENABLE) begin
                assume(PSEL);
            end

            if (!PSEL) begin
                assume(!PENABLE);
            end

            if (f_past_valid && PRESETn && $past(PRESETn)) begin

                // APB setup phase must be followed by access phase.
                if ($past(PSEL && !PENABLE)) begin
                    assume(PSEL && PENABLE);

                    // APB control signals should remain stable from setup to access.
                    assume(PADDR  == $past(PADDR));
                    assume(PWRITE == $past(PWRITE));
                    assume(PWDATA  == $past(PWDATA));
                    assume(PSTRB  == $past(PSTRB));
                    assume(PPROT  == $past(PPROT));
                end

                // If the slave inserts wait states, master must hold control stable.
                if ($past(PSEL && PENABLE && !PREADY)) begin
                    assume(PSEL && PENABLE);
                    assume(PADDR  == $past(PADDR));
                    assume(PWRITE == $past(PWRITE));
                    assume(PWDATA  == $past(PWDATA));
                    assume(PSTRB  == $past(PSTRB));
                    assume(PPROT  == $past(PPROT));
                end

                // After completed APB transfer, PENABLE must deassert.
                if ($past(PSEL && PENABLE && PREADY)) begin
                    assume(!PENABLE);
                end
            end
        end
    end

    // ------------------------------------------------------------
    // RESET PROPERTIES
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            assert(gpio_out == 8'h00);
            assert(gpio_dir == 8'h00);
            assert(timer_irq == 1'b0);
        end
    end

    // ------------------------------------------------------------
    // BASIC APB SUBSYSTEM OUTPUT PROPERTIES
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (PRESETn) begin

            // In your current design, all slaves are zero-wait-state.
            assert(PREADY == 1'b1);

            // Decoder should never select more than one target.
      /*      assert(
                ({3'b000, dut.gpio_psel}  +
                 {3'b000, dut.timer_psel} +
                 {3'b000, dut.mem_psel}   +
                 {3'b000, dut.invalid_psel}) <= 4'd1
            );

            // If PSEL is low, no slave should be selected.
            if (!PSEL) begin
                assert(!dut.gpio_psel);
                assert(!dut.timer_psel);
                assert(!dut.mem_psel);
                assert(!dut.invalid_psel);
            end   */
        end
    end

    // ------------------------------------------------------------
    // DECODER ADDRESS MAP PROPERTIES
    // ------------------------------------------------------------
  /*  always_ff @(posedge PCLK) begin
        if (PRESETn && PSEL) begin

            // GPIO range: 0x0000_0000 to 0x0000_00FF
            if (PADDR >= 32'h0000_0000 && PADDR <= 32'h0000_00FF) begin
                assert(dut.gpio_psel);
                assert(!dut.timer_psel);
                assert(!dut.mem_psel);
                assert(!dut.invalid_psel);
            end

            // Timer range: 0x0000_0100 to 0x0000_01FF
            else if (PADDR >= 32'h0000_0100 && PADDR <= 32'h0000_01FF) begin
                assert(!dut.gpio_psel);
                assert(dut.timer_psel);
                assert(!dut.mem_psel);
                assert(!dut.invalid_psel);
            end

            // Memory range: 0x0000_0200 to 0x0000_02FF
            else if (PADDR >= 32'h0000_0200 && PADDR <= 32'h0000_02FF) begin
                assert(!dut.gpio_psel);
                assert(!dut.timer_psel);
                assert(dut.mem_psel);
                assert(!dut.invalid_psel);
            end

            // Everything else should be invalid.
            else begin
                assert(!dut.gpio_psel);
                assert(!dut.timer_psel);
                assert(!dut.mem_psel);
                assert(dut.invalid_psel);
            end
        end
    end          */

    // ------------------------------------------------------------
    // INVALID ADDRESS ERROR PROPERTY
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (PRESETn && PSEL && PENABLE) begin

            if (!((PADDR >= 32'h0000_0000 && PADDR <= 32'h0000_00FF) ||
                  (PADDR >= 32'h0000_0100 && PADDR <= 32'h0000_01FF) ||
                  (PADDR >= 32'h0000_0200 && PADDR <= 32'h0000_02FF))) begin
                assert(PSLVERR == 1'b1);
                assert(PRDATA  == 32'h0000_0000);
            end
        end
    end

    // ------------------------------------------------------------
    // GPIO REGISTER PROPERTIES
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (f_past_valid && $past(PRESETn) && PRESETn) begin

            // GPIO DATA write: address 0x0000_0000
            if ($past(PSEL && PENABLE && PREADY &&
                      PWRITE &&
                      PADDR == 32'h0000_0000 &&
                      PSTRB[0])) begin
                assert(gpio_out == $past(PWDATA[7:0]));
            end

            // GPIO DIR write: address 0x0000_0004
            if ($past(PSEL && PENABLE && PREADY &&
                      PWRITE &&
                      PADDR == 32'h0000_0004 &&
                      PSTRB[0])) begin
                assert(gpio_dir == $past(PWDATA[7:0]));
            end

            // GPIO STATUS is read-only. Write to 0x10 should raise PSLVERR.
		if (PSEL && PENABLE && PWRITE &&
		    PADDR == 32'h0000_0010) begin
		    assert(PSLVERR == 1'b1);
		end
        end
    end

    // ------------------------------------------------------------
    // TIMER REGISTER PROPERTIES
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (PRESETn && PSEL && PENABLE) begin

            // Timer STATUS is read-only.
            // Timer base = 0x100, status offset = 0x0C
            // Full address = 0x10C
            if (PWRITE && PADDR == 32'h0000_010C) begin
                assert(PSLVERR == 1'b1);
            end
        end
    end

    // ------------------------------------------------------------
    // MEMORY PROPERTIES
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (PRESETn && PSEL && PENABLE) begin

            // Memory base = 0x200.
            // Memory access must be word aligned.
            if ((PADDR >= 32'h0000_0200 && PADDR <= 32'h0000_02FF) &&
                (PADDR[1:0] != 2'b00)) begin
                assert(PSLVERR == 1'b1);
            end
        end
    end

    // ------------------------------------------------------------
    // COVER PROPERTIES
    // These are not proofs. They ask: can formal reach this scenario?
    // ------------------------------------------------------------
    always_ff @(posedge PCLK) begin
        if (PRESETn) begin
            cover(PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0000);
            cover(PSEL && PENABLE && !PWRITE && PADDR == 32'h0000_0000);
            cover(PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0100);
            cover(PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0200);
            cover(PSEL && PENABLE && PSLVERR);
        end
    end

endmodule

`default_nettype wire
