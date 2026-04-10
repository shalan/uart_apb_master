`timescale 1ns/1ps

module uart_apb_sys_tb;

    localparam CLK_PERIOD = 62.5;
    localparam DIVISOR    = 3;       // fast for simulation
    localparam BIT_PERIOD = DIVISOR * 16 * CLK_PERIOD;
    localparam NUM_SLAVES = 8;
    localparam SLOT_BITS  = 13;
    localparam SLOT_SIZE  = (1 << SLOT_BITS);  // 8192 bytes

    reg         clk;
    reg         rst_n;
    reg         uart_rx_pin;
    wire        uart_tx_pin;
    wire        locked;

    // Slave port wires
    wire [NUM_SLAVES-1:0]    s_psel;
    wire [SLOT_BITS-1:0]     s_paddr   [0:NUM_SLAVES-1];
    wire [NUM_SLAVES-1:0]    s_penable;
    wire [NUM_SLAVES-1:0]    s_pwrite;
    wire [31:0]              s_pwdata  [0:NUM_SLAVES-1];
    reg  [31:0]              s_prdata  [0:NUM_SLAVES-1];
    reg  [NUM_SLAVES-1:0]    s_pready;
    reg  [NUM_SLAVES-1:0]    s_pslverr;

    // Simple memory per slave: 2048 words (8KB) each
    reg [31:0] slave_mem [0:NUM_SLAVES-1][0:2047];

    uart_apb_sys #(
        .DEFAULT_DIVISOR (DIVISOR),
        .TIMEOUT_CYCLES  (32'd1000),
        .NUM_SLAVES      (NUM_SLAVES),
        .SLOT_BITS       (SLOT_BITS)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx_pin),
        .uart_tx (uart_tx_pin),
        .locked  (locked),

        .S0_PSEL(s_psel[0]), .S0_PADDR(s_paddr[0]), .S0_PENABLE(s_penable[0]),
        .S0_PWRITE(s_pwrite[0]), .S0_PWDATA(s_pwdata[0]),
        .S0_PRDATA(s_prdata[0]), .S0_PREADY(s_pready[0]), .S0_PSLVERR(s_pslverr[0]),

        .S1_PSEL(s_psel[1]), .S1_PADDR(s_paddr[1]), .S1_PENABLE(s_penable[1]),
        .S1_PWRITE(s_pwrite[1]), .S1_PWDATA(s_pwdata[1]),
        .S1_PRDATA(s_prdata[1]), .S1_PREADY(s_pready[1]), .S1_PSLVERR(s_pslverr[1]),

        .S2_PSEL(s_psel[2]), .S2_PADDR(s_paddr[2]), .S2_PENABLE(s_penable[2]),
        .S2_PWRITE(s_pwrite[2]), .S2_PWDATA(s_pwdata[2]),
        .S2_PRDATA(s_prdata[2]), .S2_PREADY(s_pready[2]), .S2_PSLVERR(s_pslverr[2]),

        .S3_PSEL(s_psel[3]), .S3_PADDR(s_paddr[3]), .S3_PENABLE(s_penable[3]),
        .S3_PWRITE(s_pwrite[3]), .S3_PWDATA(s_pwdata[3]),
        .S3_PRDATA(s_prdata[3]), .S3_PREADY(s_pready[3]), .S3_PSLVERR(s_pslverr[3]),

        .S4_PSEL(s_psel[4]), .S4_PADDR(s_paddr[4]), .S4_PENABLE(s_penable[4]),
        .S4_PWRITE(s_pwrite[4]), .S4_PWDATA(s_pwdata[4]),
        .S4_PRDATA(s_prdata[4]), .S4_PREADY(s_pready[4]), .S4_PSLVERR(s_pslverr[4]),

        .S5_PSEL(s_psel[5]), .S5_PADDR(s_paddr[5]), .S5_PENABLE(s_penable[5]),
        .S5_PWRITE(s_pwrite[5]), .S5_PWDATA(s_pwdata[5]),
        .S5_PRDATA(s_prdata[5]), .S5_PREADY(s_pready[5]), .S5_PSLVERR(s_pslverr[5]),

        .S6_PSEL(s_psel[6]), .S6_PADDR(s_paddr[6]), .S6_PENABLE(s_penable[6]),
        .S6_PWRITE(s_pwrite[6]), .S6_PWDATA(s_pwdata[6]),
        .S6_PRDATA(s_prdata[6]), .S6_PREADY(s_pready[6]), .S6_PSLVERR(s_pslverr[6]),

        .S7_PSEL(s_psel[7]), .S7_PADDR(s_paddr[7]), .S7_PENABLE(s_penable[7]),
        .S7_PWRITE(s_pwrite[7]), .S7_PWDATA(s_pwdata[7]),
        .S7_PRDATA(s_prdata[7]), .S7_PREADY(s_pready[7]), .S7_PSLVERR(s_pslverr[7])
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // APB slave responders — one per slave
    genvar gi;
    generate
        for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_slave
            always @(posedge clk) begin
                if (s_psel[gi] && s_penable[gi]) begin
                    s_pready[gi] <= 1'b1;
                    if (s_pwrite[gi])
                        slave_mem[gi][s_paddr[gi][SLOT_BITS-1:2]] <= s_pwdata[gi];
                    else
                        s_prdata[gi] <= slave_mem[gi][s_paddr[gi][SLOT_BITS-1:2]];
                end else begin
                    s_pready[gi] <= 1'b0;
                end
            end
        end
    endgenerate

    // ----- UART Tasks -----
    task uart_send_byte(input [7:0] byte_val);
        integer i;
        begin
            uart_rx_pin = 1'b0;
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = byte_val[i];
                #(BIT_PERIOD);
            end
            uart_rx_pin = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    task uart_recv_byte(output [7:0] byte_val);
        integer i;
        begin
            @(negedge uart_tx_pin);
            #(BIT_PERIOD / 2);
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                byte_val[i] = uart_tx_pin;
                if (i < 7) #(BIT_PERIOD);
            end
            #(BIT_PERIOD);
        end
    endtask

    task send_write_cmd(input [31:0] addr, input [31:0] data);
        begin
            $display("[%0t] TX WRITE: addr=0x%08h data=0x%08h", $time, addr, data);
            uart_send_byte(8'hDE);
            uart_send_byte(8'hAD);
            uart_send_byte(8'hA5);
            uart_send_byte(addr[31:24]);
            uart_send_byte(addr[23:16]);
            uart_send_byte(addr[15:8]);
            uart_send_byte(addr[7:0]);
            uart_send_byte(data[31:24]);
            uart_send_byte(data[23:16]);
            uart_send_byte(data[15:8]);
            uart_send_byte(data[7:0]);
        end
    endtask

    task send_read_cmd(input [31:0] addr);
        begin
            $display("[%0t] TX READ:  addr=0x%08h", $time, addr);
            uart_send_byte(8'hDE);
            uart_send_byte(8'hAD);
            uart_send_byte(8'h5A);
            uart_send_byte(addr[31:24]);
            uart_send_byte(addr[23:16]);
            uart_send_byte(addr[15:8]);
            uart_send_byte(addr[7:0]);
        end
    endtask

    task recv_write_resp(output [7:0] status);
        begin
            uart_recv_byte(status);
            if (status == 8'hAC)
                $display("[%0t] RX: Write ACK", $time);
            else
                $display("[%0t] RX: Write ERROR (0x%02h)", $time, status);
        end
    endtask

    task recv_read_resp(output [31:0] data, output [7:0] status);
        reg [7:0] b0, b1, b2, b3;
        begin
            uart_recv_byte(status);
            if (status == 8'hAC) begin
                uart_recv_byte(b0);
                uart_recv_byte(b1);
                uart_recv_byte(b2);
                uart_recv_byte(b3);
                data = {b0, b1, b2, b3};
                $display("[%0t] RX: Read ACK data=0x%08h", $time, data);
            end else begin
                data = 32'hDEAD_DEAD;
                $display("[%0t] RX: Read ERROR (0x%02h)", $time, status);
            end
        end
    endtask

    // ----- Test infrastructure -----
    integer test_num, pass_count, fail_count;

    task check(input [255:0] name, input pass);
        begin
            test_num = test_num + 1;
            if (pass) begin
                $display("  [PASS] Test %0d: %0s", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Test %0d: %0s", test_num, name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ----- Main test -----
    reg [31:0] read_data;
    reg [7:0]  status;
    integer    s, j;

    initial begin
        $dumpfile("uart_apb_sys_tb.vcd");
        $dumpvars(0, uart_apb_sys_tb);

        uart_rx_pin = 1'b1;
        s_pready    = {NUM_SLAVES{1'b0}};
        s_pslverr   = {NUM_SLAVES{1'b0}};
        rst_n       = 1'b0;
        test_num    = 0;
        pass_count  = 0;
        fail_count  = 0;

        for (s = 0; s < NUM_SLAVES; s = s + 1)
            for (j = 0; j < 2048; j = j + 1)
                slave_mem[s][j] = 32'd0;

        // Initialize s_prdata
        for (s = 0; s < NUM_SLAVES; s = s + 1)
            s_prdata[s] = 32'd0;

        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        $display("\n=== UART-APB System (Splitter) Tests ===\n");

        // ---- Test 1: Write to Slave 0, offset 0x00 ----
        fork
            send_write_cmd(32'h0000_0000, 32'hAAAA_0000);
            recv_write_resp(status);
        join
        check("Write Slave 0 @ 0x0000", status == 8'hAC);
        #(BIT_PERIOD * 2);

        // ---- Test 2: Read back from Slave 0 ----
        fork
            send_read_cmd(32'h0000_0000);
            recv_read_resp(read_data, status);
        join
        check("Read Slave 0 @ 0x0000", status == 8'hAC && read_data == 32'hAAAA_0000);
        #(BIT_PERIOD * 2);

        // ---- Test 3: Write to Slave 1, offset 0x04 ----
        // Slave 1 base = 0x2000
        fork
            send_write_cmd(32'h0000_2004, 32'hBBBB_1111);
            recv_write_resp(status);
        join
        check("Write Slave 1 @ 0x2004", status == 8'hAC);
        #(BIT_PERIOD * 2);

        // ---- Test 4: Read back from Slave 1 ----
        fork
            send_read_cmd(32'h0000_2004);
            recv_read_resp(read_data, status);
        join
        check("Read Slave 1 @ 0x2004", status == 8'hAC && read_data == 32'hBBBB_1111);
        #(BIT_PERIOD * 2);

        // ---- Test 5: Write to Slave 7, offset 0x10 ----
        // Slave 7 base = 0xE000
        fork
            send_write_cmd(32'h0000_E010, 32'h7777_7777);
            recv_write_resp(status);
        join
        check("Write Slave 7 @ 0xE010", status == 8'hAC);
        #(BIT_PERIOD * 2);

        // ---- Test 6: Read back from Slave 7 ----
        fork
            send_read_cmd(32'h0000_E010);
            recv_read_resp(read_data, status);
        join
        check("Read Slave 7 @ 0xE010", status == 8'hAC && read_data == 32'h7777_7777);
        #(BIT_PERIOD * 2);

        // ---- Test 7: Verify Slave 0 data is independent ----
        fork
            send_read_cmd(32'h0000_0000);
            recv_read_resp(read_data, status);
        join
        check("Slave 0 independent of Slave 7", status == 8'hAC && read_data == 32'hAAAA_0000);
        #(BIT_PERIOD * 2);

        // ---- Test 8: Write to all 8 slaves ----
        for (s = 0; s < NUM_SLAVES; s = s + 1) begin
            fork
                send_write_cmd({16'd0, s[2:0], 13'h100}, {8'd0, s[7:0], 16'hFACE});
                recv_write_resp(status);
            join
            #(BIT_PERIOD * 2);
        end
        check("Write to all 8 slaves completed", status == 8'hAC);

        // ---- Test 9: Read back from all 8 slaves ----
        begin : readback_all
            reg all_ok;
            all_ok = 1'b1;
            for (s = 0; s < NUM_SLAVES; s = s + 1) begin
                fork
                    send_read_cmd({16'd0, s[2:0], 13'h100});
                    recv_read_resp(read_data, status);
                join
                if (status != 8'hAC || read_data != {8'd0, s[7:0], 16'hFACE})
                    all_ok = 1'b0;
                #(BIT_PERIOD * 2);
            end
            check("Read back all 8 slaves correct", all_ok);
        end

        // ---- Test 10: Out-of-range address (above 0xFFFF) ----
        fork
            send_write_cmd(32'h0001_0000, 32'hDEAD_BEEF);
            recv_write_resp(status);
        join
        check("Out-of-range address returns error", status == 8'hEE);
        #(BIT_PERIOD * 2);

        // ---- Test 11: Another out-of-range (read) ----
        fork
            send_read_cmd(32'h0010_0000);
            begin
                uart_recv_byte(status);
                $display("[%0t] RX: status=0x%02h", $time, status);
            end
        join
        check("Out-of-range read returns error", status == 8'hEE);
        #(BIT_PERIOD * 2);

        // ---- Test 12: Lock and verify ----
        fork
            send_write_cmd(32'hFFFF_FFF0, 32'hDEAD_10CC);
            recv_write_resp(status);
        join
        #(BIT_PERIOD * 2);
        check("Lock activates", locked == 1'b1);

        fork
            send_write_cmd(32'h0000_0000, 32'hBAD0_BAD0);
            recv_write_resp(status);
        join
        check("Write after lock rejected", status == 8'hEE);

        // ---- Summary ----
        $display("\n=== Results: %0d passed, %0d failed out of %0d ===\n",
                 pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #(BIT_PERIOD * 60000);
        $display("TIMEOUT");
        $finish;
    end

endmodule
