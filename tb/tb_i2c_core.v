// tb_i2c_core.v - self-checking testbench: master + 7-bit slave + 10-bit slave
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_i2c_core;
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;                     // 50 MHz

    tri1 scl, sda;                             // open-drain bus with pull-ups
    wire m_scl_oe, m_sda_oe, s7_scl_oe, s7_sda_oe, s10_scl_oe, s10_sda_oe;
    assign scl = m_scl_oe  ? 1'b0 : 1'bz;  assign sda = m_sda_oe  ? 1'b0 : 1'bz;
    assign scl = s7_scl_oe ? 1'b0 : 1'bz;  assign sda = s7_sda_oe ? 1'b0 : 1'bz;
    assign scl = s10_scl_oe? 1'b0 : 1'bz;  assign sda = s10_sda_oe? 1'b0 : 1'bz;

    reg [15:0] prescale = 16'd124;
    reg cmd_valid = 0, c_start = 0, c_stop = 0, c_read = 0, c_write = 0, c_nack = 0;
    reg [7:0] tx_data = 0;
    wire [7:0] rx_data; wire rx_nack, done, arb_lost, busy, bus_busy;
    reg s7_stretch = 0; reg [15:0] s7_scyc = 16'd0;
    reg [3:0] dbg7 = 0, dbg10 = 0; wire [7:0] d7, d10;

    i2c_master u_m (.clk(clk), .rst_n(rst_n), .prescale(prescale), .cmd_valid(cmd_valid),
        .cmd_start(c_start), .cmd_stop(c_stop), .cmd_read(c_read), .cmd_write(c_write),
        .cmd_nack(c_nack), .tx_data(tx_data), .rx_data(rx_data), .rx_nack(rx_nack), .done(done),
        .arb_lost(arb_lost), .busy(busy), .bus_busy(bus_busy),
        .scl_i(scl), .sda_i(sda), .scl_oe(m_scl_oe), .sda_oe(m_sda_oe));
    i2c_slave u_s7 (.clk(clk), .rst_n(rst_n), .own_addr(10'h050), .addr10_en(1'b0),
        .stretch_en(s7_stretch), .stretch_cycles(s7_scyc), .scl_i(scl), .sda_i(sda),
        .scl_oe(s7_scl_oe), .sda_oe(s7_sda_oe), .addressed(), .wr_strobe(), .dbg_addr(dbg7), .dbg_data(d7));
    i2c_slave u_s10 (.clk(clk), .rst_n(rst_n), .own_addr(10'h2A5), .addr10_en(1'b1),
        .stretch_en(1'b0), .stretch_cycles(16'd0), .scl_i(scl), .sda_i(sda),
        .scl_oe(s10_scl_oe), .sda_oe(s10_sda_oe), .addressed(), .wr_strobe(), .dbg_addr(dbg10), .dbg_data(d10));

    i2c_monitor #(.NAME("bus")) mon (.scl(scl), .sda(sda), .en(rst_n), .chk_mode(2'd0));
    integer errors = 0, checks = 0, tests_pass = 0, tests_fail = 0, test_err0;
    reg [8*48-1:0] tname;
    // ---- for the waveform: test number visible in GTKWave
    reg [7:0] test_id = 0;

    task check(input cond, input [8*64-1:0] msg);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("  [FAIL] %0s  (t=%0t)", msg, $time); end
        end
    endtask
    task begin_test(input [7:0] id, input [8*48-1:0] n);
        begin test_id = id; tname = n; test_err0 = errors; $display("TEST %0d: %0s", id, n); end
    endtask
    task end_test;
        begin
            if (errors == test_err0) begin tests_pass = tests_pass + 1; $display("TEST %0d: %0s ... PASS", test_id, tname); end
            else begin tests_fail = tests_fail + 1; $display("TEST %0d: %0s ... FAIL", test_id, tname); end
        end
    endtask

    task cmd(input s, input p, input r, input w, input n, input [7:0] d);
        begin
            @(posedge clk); c_start <= s; c_stop <= p; c_read <= r; c_write <= w; c_nack <= n;
            tx_data <= d; cmd_valid <= 1;
            @(posedge clk); cmd_valid <= 0;
            @(posedge done); @(posedge clk);
        end
    endtask
    // write n bytes to register ptr of 7-bit slave addr7
    task wr7(input [6:0] a, input [7:0] ptr, input integer n, input [8*16-1:0] data);
        integer k;
        begin
            cmd(1,0,0,1,0,{a,1'b0}); check(!rx_nack, "address ACK");
            cmd(0,0,0,1,0,ptr);      check(!rx_nack, "pointer ACK");
            for (k = 0; k < n; k = k + 1) begin
                cmd(0,(k==n-1),0,1,0,data[8*(15-k) +: 8]); check(!rx_nack, "data ACK");
            end
        end
    endtask

    // SCL measurement
    realtime t_rise_prev = 0, period_min = 1e9, period_max = 0, low_max = 0, t_fall = 0;
    always @(posedge scl) begin
        if (t_rise_prev > 0 && ($realtime - t_rise_prev) < 2000000) begin
            if ($realtime - t_rise_prev < period_min) period_min = $realtime - t_rise_prev;
            if ($realtime - t_rise_prev > period_max) period_max = $realtime - t_rise_prev;
        end
        if (t_fall > 0 && ($realtime - t_fall) > low_max) low_max = $realtime - t_fall;
        t_rise_prev = $realtime;
    end
    always @(negedge scl) t_fall = $realtime;
    task reset_meas; begin t_rise_prev = 0; period_min = 1e9; period_max = 0; low_max = 0; t_fall = 0; end endtask

    integer k; reg [7:0] exp;
    initial begin
        $timeformat(-9, 0, " ns", 10);
        if (!$test$plusargs("nodump")) begin $dumpfile("waves/tb_i2c_core.vcd"); $dumpvars(0, tb_i2c_core); end
        repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);

        // ---------------------------------------------------------------
        begin_test(1, "7-bit write, 4 bytes, 100 kHz");
        reset_meas;
        wr7(7'h50, 8'h02, 4, {32'hA53C7E81, 96'd0});
        dbg7 = 2; #1 check(d7 == 8'hA5, "reg[2]=A5");
        dbg7 = 3; #1 check(d7 == 8'h3C, "reg[3]=3C");
        dbg7 = 4; #1 check(d7 == 8'h7E, "reg[4]=7E");
        dbg7 = 5; #1 check(d7 == 8'h81, "reg[5]=81");
        $display("  SCL period min %0.1f ns max %0.1f ns -> %0.2f kHz", period_min, period_max, 1e6/period_min);
        check(period_min == 10060.0, "SCL = 50 MHz/(4*125+3) = 99.40 kHz");
        check(!bus_busy, "bus free after STOP");
        end_test;

        // ---------------------------------------------------------------
        begin_test(2, "7-bit read, repeated START, ACK/NACK");
        cmd(1,0,0,1,0,8'hA0); check(!rx_nack, "addr+W ACK");
        cmd(0,0,0,1,0,8'h02); check(!rx_nack, "ptr ACK");
        cmd(1,0,0,1,0,8'hA1); check(!rx_nack, "Sr addr+R ACK");
        for (k = 0; k < 4; k = k + 1) begin
            cmd(0,(k==3),1,0,(k==3),8'h00);
            exp = (k==0)?8'hA5:(k==1)?8'h3C:(k==2)?8'h7E:8'h81;
            $display("  read byte %0d = %02h (expected %02h)", k, rx_data, exp);
            check(rx_data == exp, "read data");
        end
        check(!bus_busy, "bus free after STOP");
        end_test;

        // ---------------------------------------------------------------
        begin_test(3, "NACK: no slave at address 0x58");
        cmd(1,0,0,1,0,{7'h58,1'b0});
        $display("  rx_nack = %0d (expected 1)", rx_nack);
        check(rx_nack == 1'b1, "address NACK detected");
        cmd(0,1,0,0,0,8'h00);
        check(!bus_busy, "STOP after NACK");
        end_test;

        // ---------------------------------------------------------------
        begin_test(4, "10-bit write to 0x2A5");
        cmd(1,0,0,1,0,8'hF4); check(!rx_nack, "10-bit header ACK");   // 11110_10_0
        cmd(0,0,0,1,0,8'hA5); check(!rx_nack, "10-bit 2nd byte ACK");
        cmd(0,0,0,1,0,8'h05); check(!rx_nack, "ptr ACK");
        cmd(0,0,0,1,0,8'h11); check(!rx_nack, "data ACK");
        cmd(0,1,0,1,0,8'h22); check(!rx_nack, "data ACK");
        dbg10 = 5; #1 check(d10 == 8'h11, "s10 reg[5]=11");
        dbg10 = 6; #1 check(d10 == 8'h22, "s10 reg[6]=22");
        dbg7 = 5;  #1 check(d7 == 8'h81, "7-bit slave untouched");
        end_test;

        // ---------------------------------------------------------------
        begin_test(5, "10-bit read with repeated START");
        cmd(1,0,0,1,0,8'hF4); check(!rx_nack, "header ACK");
        cmd(0,0,0,1,0,8'hA5); check(!rx_nack, "2nd byte ACK");
        cmd(0,0,0,1,0,8'h05); check(!rx_nack, "ptr ACK");
        cmd(1,0,0,1,0,8'hF5); check(!rx_nack, "Sr header+R ACK");
        cmd(0,0,1,0,0,8'h00); $display("  read %02h (expected 11)", rx_data); check(rx_data == 8'h11, "rd 11");
        cmd(0,1,1,0,1,8'h00); $display("  read %02h (expected 22)", rx_data); check(rx_data == 8'h22, "rd 22");
        end_test;

        // ---------------------------------------------------------------
        begin_test(6, "10-bit NACK: wrong low address byte");
        cmd(1,0,0,1,0,8'hF4); check(!rx_nack, "header ACK");
        cmd(0,0,0,1,0,8'hA6); $display("  rx_nack = %0d (expected 1)", rx_nack); check(rx_nack, "2nd byte NACK");
        cmd(0,1,0,0,0,8'h00);
        end_test;

        // ---------------------------------------------------------------
        begin_test(7, "clock stretching by slave (600 clk = 12 us)");
        s7_stretch = 1; s7_scyc = 16'd600;
        reset_meas;
        wr7(7'h50, 8'h08, 2, {16'hC3D4, 112'd0});
        $display("  longest SCL low time %0.1f ns (normal low = %0d ns)", low_max, 2*(prescale+1)*20);
        check(low_max > 600*20, "SCL held low by slave >= 12 us");
        dbg7 = 8; #1 check(d7 == 8'hC3, "reg[8]=C3");
        dbg7 = 9; #1 check(d7 == 8'hD4, "reg[9]=D4");
        cmd(1,0,0,1,0,8'hA0); cmd(0,0,0,1,0,8'h08); cmd(1,0,0,1,0,8'hA1);
        cmd(0,1,1,0,1,8'h00); check(rx_data == 8'hC3, "read back under stretching");
        s7_stretch = 0;
        end_test;

        // ---------------------------------------------------------------
        begin_test(8, "Fast-mode 370 kHz (prescale=32)");
        prescale = 16'd32; reset_meas;
        wr7(7'h50, 8'h0C, 3, {24'h0F1E2D, 104'd0});
        $display("  SCL period min %0.1f ns max %0.1f ns -> %0.2f kHz", period_min, period_max, 1e6/period_min);
        check(period_min == 2700.0, "SCL = 50 MHz/(4*33+3) = 370.37 kHz");
        cmd(1,0,0,1,0,8'hA0); cmd(0,0,0,1,0,8'h0C); cmd(1,0,0,1,0,8'hA1);
        cmd(0,0,1,0,0,0); check(rx_data == 8'h0F, "rd 0F");
        cmd(0,0,1,0,0,0); check(rx_data == 8'h1E, "rd 1E");
        cmd(0,1,1,0,1,0); check(rx_data == 8'h2D, "rd 2D");
        end_test;
        check(mon.errors == 0, "protocol monitor: no assertion failures");
        $display("  protocol monitor: %0d START, %0d Sr, %0d STOP, %0d bits, %0d assertion failures", mon.starts, mon.rstarts, mon.stops, mon.bits, mon.errors);

        $display("--------------------------------------------------");
        $display("SUMMARY tb_i2c_core: %0d/%0d tests PASS, %0d checks, %0d errors",
                 tests_pass, tests_pass+tests_fail, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: FAILED");
        #2000 $finish;
    end
    initial begin #50_000_000 $display("TIMEOUT"); $finish; end
endmodule
