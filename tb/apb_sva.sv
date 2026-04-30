module apb_sva #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8
)(
    input logic                  PCLK,
    input logic                  PRESETn,

    input logic                  PSEL,
    input logic                  PENABLE,
    input logic                  PWRITE,
    input logic [ADDR_WIDTH-1:0] PADDR,
    input logic [DATA_WIDTH-1:0] PWDATA,
    input logic [STRB_WIDTH-1:0] PSTRB,
    input logic [2:0]            PPROT,

    input logic                  PREADY,
    input logic                  PSLVERR,
    input logic [DATA_WIDTH-1:0] PRDATA
);

property setup_before_access;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> (PSEL && PENABLE);
endproperty

    property control_stable_during_wait;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && !PREADY) |=> 
        $stable({PADDR, PWRITE, PWDATA, PSTRB, PPROT});
    endproperty

    property no_enable_without_select;
        @(posedge PCLK) disable iff (!PRESETn)
        PENABLE |-> PSEL;
    endproperty

    property idle_has_no_enable;
        @(posedge PCLK) disable iff (!PRESETn)
        !PSEL |-> !PENABLE;
    endproperty

    property pslverr_only_in_access_phase;
        @(posedge PCLK) disable iff (!PRESETn)
        PSLVERR |-> (PSEL && PENABLE && PREADY);
    endproperty

    property no_unknown_bus;
        @(posedge PCLK) disable iff (!PRESETn)
        PSEL |-> !$isunknown({PADDR, PWRITE, PSTRB, PPROT});
    endproperty

    property penable_deasserts_after_transfer;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE && PREADY) |=> !PENABLE;
    endproperty

    property pready_no_unknown;
        @(posedge PCLK) disable iff (!PRESETn)
        (PSEL && PENABLE) |-> !$isunknown(PREADY);
    endproperty

    a_setup_before_access:
        assert property(setup_before_access)
        else $error("APB ERROR: SETUP phase was not followed by ACCESS phase");

    a_control_stable_during_wait:
        assert property(control_stable_during_wait)
        else $error("APB ERROR: Control signals changed while PREADY was low");

    a_no_enable_without_select:
        assert property(no_enable_without_select)
        else $error("APB ERROR: PENABLE high while PSEL low");

    a_idle_has_no_enable:
        assert property(idle_has_no_enable)
        else $error("APB ERROR: PENABLE high in IDLE phase");

    a_pslverr_only_in_access_phase:
        assert property(pslverr_only_in_access_phase)
        else $error("APB ERROR: PSLVERR asserted outside valid ACCESS completion");

    a_no_unknown_bus:
        assert property(no_unknown_bus)
        else $error("APB ERROR: Unknown X/Z detected on APB control/address bus");

    a_penable_deasserts:
        assert property(penable_deasserts_after_transfer)
        else $error("APB ERROR: PENABLE stayed high after completed transfer");

    a_pready_no_unknown:
        assert property(pready_no_unknown)
        else $error("APB ERROR: PREADY is X/Z during access phase");
        
endmodule