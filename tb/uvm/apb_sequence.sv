class apb_base_sequence extends uvm_sequence #(apb_transaction);

    `uvm_object_utils(apb_base_sequence)

    function new(string name = "apb_base_sequence");
        super.new(name);
    endfunction

    task apb_write(logic [31:0] addr,
                   logic [31:0] data,
                   logic [3:0]  strb = 4'hF);

        apb_transaction tr;

        tr = apb_transaction::type_id::create("tr");
        start_item(tr);

        tr.cmd   = APB_WRITE;
        tr.addr  = addr;
        tr.wdata = data;
        tr.strb  = strb;
        tr.prot  = 3'b000;

        finish_item(tr);
    endtask

    task apb_read(logic [31:0] addr);
        apb_transaction tr;

        tr = apb_transaction::type_id::create("tr");
        start_item(tr);

        tr.cmd   = APB_READ;
        tr.addr  = addr;
        tr.wdata = '0;
        tr.strb  = 4'h0;
        tr.prot  = 3'b000;

        finish_item(tr);
    endtask

endclass


class apb_smoke_sequence extends apb_base_sequence;

    `uvm_object_utils(apb_smoke_sequence)

    function new(string name = "apb_smoke_sequence");
        super.new(name);
    endfunction

    task body();

        `uvm_info(get_type_name(), "Starting APB smoke sequence", UVM_MEDIUM)

        apb_write(GPIO_DIR,  32'h0000_00FF);
        apb_write(GPIO_DATA, 32'h0000_00A5);
        apb_read (GPIO_DATA);
        apb_read (GPIO_DIR);

        apb_write(GPIO_SET,   32'h0000_000F);
        apb_read (GPIO_DATA);

        apb_write(GPIO_CLEAR, 32'h0000_0005);
        apb_read (GPIO_DATA);

        apb_write(TIMER_LOAD,  32'd5);
        apb_write(TIMER_CTRL,  32'h0000_0003);
        repeat (10) apb_read(TIMER_COUNT);
        apb_read(TIMER_STATUS);
        apb_write(TIMER_CLEAR, 32'h0000_0003);
        apb_read(TIMER_STATUS);

        apb_write(MEM_BASE + 32'h00, 32'hDEAD_BEEF);
        apb_read (MEM_BASE + 32'h00);

        apb_write(MEM_BASE + 32'h04, 32'hCAFE_1234);
        apb_read (MEM_BASE + 32'h04);

        apb_read(32'h0000_0800);

        `uvm_info(get_type_name(), "Finished APB smoke sequence", UVM_MEDIUM)

    endtask

endclass


class apb_random_sequence extends apb_base_sequence;

    `uvm_object_utils(apb_random_sequence)

    function new(string name = "apb_random_sequence");
        super.new(name);
    endfunction

    task body();

        apb_transaction tr;

      repeat (500) begin
            tr = apb_transaction::type_id::create("tr");
            start_item(tr);

            assert(tr.randomize() with {
                addr inside {
                    [32'h0000_0000:32'h0000_0010],   // GPIO valid offsets (0x00–0x10)
                    [32'h0000_0100:32'h0000_0110],   // Timer valid offsets (0x00–0x10)
                    [32'h0000_0200:32'h0000_02FC],   // Memory range
                    32'h0000_0800                     // Invalid address
                };
                // Force word-alignment for memory addresses
                if (addr >= 32'h0000_0200 && addr <= 32'h0000_02FC)
                    addr[1:0] == 2'b00;
            });

            finish_item(tr);
        end

    endtask

endclass