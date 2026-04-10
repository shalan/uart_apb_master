`timescale 1ns/1ps

module uart_apb_master_tb;

    // Clock: 16 MHz => 62.5ns period
    localparam CLK_PERIOD  = 62.5;
    localparam DIVISOR     = 3;   // fast divisor for simulation
    // Bit period = DIVISOR * 16 * CLK_PERIOD
    localparam BIT_PERIOD  = DIVISOR * 16 * CLK_PERIOD;

    reg         clk;
    reg         rst_n;
    reg         uart_rx_pin;
    wire        uart_tx_pin;
    wire [31:0] PADDR;
    wire        PSEL;
    wire        PENABLE;
    wire        PWRITE;
    wire [31:0] PWDATA;
    reg  [31:0] PRDATA;
    reg         PREADY;
    reg         PSLVERR;
    wire        locked;

    // Simple APB slave memory
    reg [31:0] slave_mem [0:255];

    integer test_num;
    integer pass_count;
    integer fail_count;

    uart_apb_master #(
        .DEFAULT_DIVISOR(DIVISOR),
        .TIMEOUT_CYCLES(32'd1000)  // short timeout for simulation
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx_pin),
        .uart_tx (uart_tx_pin),
        .PADDR   (PADDR),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR),
        .locked  (locked)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // APB slave responder
    always @(posedge clk) begin
        if (PSEL && PENABLE) begin
            PREADY <= 1'b1;
            if (PWRITE)
                slave_mem[PADDR[9:2]] <= PWDATA;
            else
                PRDATA <= slave_mem[PADDR[9:2]];
        end else begin
            PREADY <= 1'b0;
        end
    end

    // Task: send one UART byte (8N1)
    task uart_send_byte(input [7:0] byte_val);
        integer i;
        begin
            // Start bit
            uart_rx_pin = 1'b0;
            #(BIT_PERIOD);
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = byte_val[i];
                #(BIT_PERIOD);
            end
            // Stop bit
            uart_rx_pin = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    // Task: receive one UART byte
    task uart_recv_byte(output [7:0] byte_val);
        integer i;
        begin
            // Wait for start bit
            @(negedge uart_tx_pin);
            #(BIT_PERIOD / 2); // align to middle of start bit
            #(BIT_PERIOD);     // skip to middle of first data bit
            for (i = 0; i < 8; i = i + 1) begin
                byte_val[i] = uart_tx_pin;
                if (i < 7) #(BIT_PERIOD);
            end
            #(BIT_PERIOD); // stop bit
        end
    endtask

    // Task: send APB write command
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

    // Task: send APB read command
    task send_read_cmd(input [31:0] addr);
        begin
            $display("[%0t] TX READ: addr=0x%08h", $time, addr);
            uart_send_byte(8'hDE);
            uart_send_byte(8'hAD);
            uart_send_byte(8'h5A);
            uart_send_byte(addr[31:24]);
            uart_send_byte(addr[23:16]);
            uart_send_byte(addr[15:8]);
            uart_send_byte(addr[7:0]);
        end
    endtask

    // Task: receive write response, return status byte
    task recv_write_resp(output [7:0] status);
        begin
            uart_recv_byte(status);
            if (status == 8'hAC)
                $display("[%0t] RX: Write ACK", $time);
            else
                $display("[%0t] RX: Write ERROR (0x%02h)", $time, status);
        end
    endtask

    // Task: receive read response
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

    // Helper: check and report
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

    // Main test sequence
    reg [31:0] read_data;
    reg [7:0]  status;
    integer    i;

    initial begin
        $dumpfile("uart_apb_master_tb.vcd");
        $dumpvars(0, uart_apb_master_tb);

        uart_rx_pin = 1'b1;
        PRDATA      = 32'd0;
        PREADY      = 1'b0;
        PSLVERR     = 1'b0;
        rst_n       = 1'b0;
        test_num    = 0;
        pass_count  = 0;
        fail_count  = 0;

        for (i = 0; i < 256; i = i + 1)
            slave_mem[i] = 32'd0;

        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        $display("\n=== UART-APB Master Bridge Tests ===\n");

        // ---- Test 1: Basic write ----
        fork
            send_write_cmd(32'h0000_0000, 32'hCAFE_BABE);
            recv_write_resp(status);
        join
        check("Basic write ACK", status == 8'hAC);
        #(BIT_PERIOD * 2);

        // ---- Test 2: Read back ----
        fork
            send_read_cmd(32'h0000_0000);
            recv_read_resp(read_data, status);
        join
        check("Read back matches write", status == 8'hAC && read_data == 32'hCAFE_BABE);
        #(BIT_PERIOD * 2);

        // ---- Test 3: Write to different address ----
        fork
            send_write_cmd(32'h0000_0010, 32'h1234_5678);
            recv_write_resp(status);
        join
        check("Write to addr 0x10", status == 8'hAC);
        #(BIT_PERIOD * 2);

        // ---- Test 4: Read from second address ----
        fork
            send_read_cmd(32'h0000_0010);
            recv_read_resp(read_data, status);
        join
        check("Read addr 0x10 matches", status == 8'hAC && read_data == 32'h1234_5678);
        #(BIT_PERIOD * 2);

        // ---- Test 5: Verify first address unchanged ----
        fork
            send_read_cmd(32'h0000_0000);
            recv_read_resp(read_data, status);
        join
        check("Addr 0x00 unchanged", status == 8'hAC && read_data == 32'hCAFE_BABE);
        #(BIT_PERIOD * 2);

        // ---- Test 6: Verify bridge is not locked yet ----
        check("Bridge unlocked before lock cmd", locked == 1'b0);

        // ---- Test 7: Lock the bridge ----
        fork
            send_write_cmd(32'hFFFF_FFF0, 32'hDEAD_10CC);
            recv_write_resp(status);
        join
        // The lock command itself goes through to APB (lock latches on cmd_valid)
        #(BIT_PERIOD * 2);
        check("Bridge locked after lock cmd", locked == 1'b1);

        // ---- Test 8: Write after lock should get error ----
        fork
            send_write_cmd(32'h0000_0000, 32'hBAAD_F00D);
            recv_write_resp(status);
        join
        check("Write rejected when locked", status == 8'hEE);
        #(BIT_PERIOD * 2);

        // ---- Test 9: Read after lock should get error ----
        fork
            send_read_cmd(32'h0000_0000);
            begin
                uart_recv_byte(status);
                $display("[%0t] RX: status=0x%02h (expected 0xEE)", $time, status);
            end
        join
        check("Read rejected when locked", status == 8'hEE);
        #(BIT_PERIOD * 2);

        // ---- Test 10: Original data untouched after locked write attempt ----
        // Reset to unlock and verify
        rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        fork
            send_read_cmd(32'h0000_0000);
            recv_read_resp(read_data, status);
        join
        check("Data intact after lock+reset", status == 8'hAC && read_data == 32'hCAFE_BABE);
        #(BIT_PERIOD * 2);

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
        #(BIT_PERIOD * 20000);
        $display("TIMEOUT - simulation took too long");
        $finish;
    end

endmodule
