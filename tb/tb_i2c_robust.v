// tb_i2c_robust.v - APB command handling and error recovery
// Author: B. Srishanth Reddy
// T1 command while busy is rejected (cmd_err), running transfer is not disturbed
// T2 invalid commands (READ+WRITE, RECOVER+START) are rejected, nothing appears on the bus
// T3 software flow using STATUS.cmd_ready polling
// T4 master reset in the middle of a read -> slave holds SDA low (bus stuck) -> RECOVER
// T5 slave holds SCL low too long -> STATUS.timeout, then RECOVER and normal transfer
// T6 monitor self-test: an illegal SDA change while SCL is high inside a byte must be flagged
`timescale 1ns/1ps
module tb_i2c_robust;
    reg pclk = 0, presetn = 0, s_rstn = 0;
    always #10 pclk = ~pclk;
    tri1 scl, sda;
    wire m_scl, m_sda, s_scl, s_sda, irq;
    assign scl = m_scl ? 1'b0 : 1'bz; assign sda = m_sda ? 1'b0 : 1'bz;
    assign scl = s_scl ? 1'b0 : 1'bz; assign sda = s_sda ? 1'b0 : 1'bz;
    reg t_scl = 0, t_sda = 0;                  // testbench driver for the monitor self-test
    assign scl = t_scl ? 1'b0 : 1'bz; assign sda = t_sda ? 1'b0 : 1'bz;

    reg psel = 0, penable = 0, pwrite = 0; reg [7:0] paddr = 0; reg [31:0] pwdata = 0;
    wire [31:0] prdata; wire pready, pslverr, s_addressed;
    reg [3:0] dbg = 0; wire [7:0] dd;
    reg s_stretch = 0; reg [15:0] s_scyc = 0; reg mon_en = 0;

    // timeout shortened to 10000 clocks (200 us) so the test runs quickly
    i2c_apb #(.TIMEOUT_CLKS(10000)) dut (.pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable),
        .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .irq(irq), .scl_i(scl), .sda_i(sda), .scl_oe(m_scl), .sda_oe(m_sda));
    i2c_slave u_s (.clk(pclk), .rst_n(s_rstn), .own_addr(10'h050), .addr10_en(1'b0), .stretch_en(s_stretch),
        .stretch_cycles(s_scyc), .scl_i(scl), .sda_i(sda), .scl_oe(s_scl), .sda_oe(s_sda),
        .addressed(s_addressed), .wr_strobe(), .dbg_addr(dbg), .dbg_data(dd));
    i2c_monitor #(.NAME("bus")) mon (.scl(scl), .sda(sda), .en(mon_en), .chk_mode(2'd0));

    localparam CTRL=8'h00, PRESC=8'h04, TXD=8'h08, RXD=8'h0C, CMD=8'h10, STAT=8'h14;
    localparam C_START=1, C_STOP=2, C_READ=4, C_WRITE=8, C_NACK=16, C_RECOVER=32;
    localparam S_BUSY=0, S_NACK=1, S_DONE=3, S_ERR=5, S_RDY=6, S_TOUT=7, S_SCL=8, S_SDA=9;
    integer errors = 0, checks = 0, tp = 0, tf = 0, e0, k, n0;
    reg [7:0] test_id = 0; reg [31:0] r;
    reg [8*48-1:0] tname;

    task check(input c, input [8*64-1:0] m);
        begin checks = checks + 1; if (!c) begin errors = errors + 1; $display("  [FAIL] %0s (t=%0t)", m, $time); end end
    endtask
    task begin_test(input [7:0] id, input [8*48-1:0] n);
        begin test_id = id; tname = n; e0 = errors; $display("TEST %0d: %0s", id, n); end
    endtask
    task fin;
        begin if (errors == e0) begin tp = tp + 1; $display("TEST %0d: %0s ... PASS", test_id, tname); end
              else begin tf = tf + 1; $display("TEST %0d: %0s ... FAIL", test_id, tname); end end
    endtask
    task apb_w(input [7:0] a, input [31:0] d);
        begin @(posedge pclk); psel<=1; pwrite<=1; paddr<=a; pwdata<=d; penable<=0;
              @(posedge pclk); penable<=1; @(posedge pclk); psel<=0; penable<=0; pwrite<=0; end
    endtask
    task apb_r(input [7:0] a, output [31:0] d);
        begin @(posedge pclk); psel<=1; pwrite<=0; paddr<=a; penable<=0;
              @(posedge pclk); penable<=1; @(negedge pclk); d = prdata; @(posedge pclk); psel<=0; penable<=0; end
    endtask
    task wait_done; begin r = 0; while (!r[S_DONE]) apb_r(STAT, r); end endtask
    task wait_ready; begin r = 0; while (!r[S_RDY]) apb_r(STAT, r); end endtask
    task op(input [7:0] c, input [7:0] d); begin apb_w(TXD, d); apb_w(CMD, c); wait_done; end endtask

    initial begin
        $timeformat(-9, 0, " ns", 10);
        if (!$test$plusargs("nodump")) begin $dumpfile("waves/tb_i2c_robust.vcd"); $dumpvars(0, tb_i2c_robust); end
        repeat (5) @(posedge pclk); presetn = 1; s_rstn = 1; mon_en = 1; repeat (5) @(posedge pclk);
        apb_w(PRESC, 32'd32); apb_w(CTRL, 1);

        // ---------------------------------------------------------------
        begin_test(1, "command while busy is rejected (cmd_err)");
        apb_w(TXD, 8'hA0); apb_w(CMD, C_START|C_WRITE);
        apb_r(STAT, r); $display("  after CMD: busy=%0d cmd_ready=%0d", r[S_BUSY], r[S_RDY]);
        check(r[S_BUSY] && !r[S_RDY], "busy=1, cmd_ready=0 during transfer");
        apb_w(TXD, 8'h77); apb_w(CMD, C_WRITE|C_STOP);             // illegal: master is busy
        apb_r(STAT, r); $display("  second CMD while busy: cmd_err=%0d irq=%0d", r[S_ERR], irq);
        check(r[S_ERR] == 1, "STATUS.cmd_err set");
        check(irq == 1, "irq raised by cmd_err");
        wait_done; check(!r[S_NACK], "first command still completes with ACK");
        check(r[S_ERR] == 1, "cmd_err is sticky");
        apb_w(STAT, 32'h20); apb_r(STAT, r); check(r[S_ERR] == 0, "cmd_err W1C");
        op(C_WRITE, 8'h00); op(C_WRITE|C_STOP, 8'h3C);
        dbg = 0; #1 check(dd == 8'h3C, "reg[0]=3C (rejected byte 77 never sent)");
        apb_w(STAT, 32'h8);
        fin;

        // ---------------------------------------------------------------
        begin_test(2, "invalid commands rejected, bus untouched");
        n0 = mon.starts;
        apb_w(CMD, C_READ|C_WRITE); apb_r(STAT, r);
        $display("  CMD=READ|WRITE    -> cmd_err=%0d busy=%0d", r[S_ERR], r[S_BUSY]);
        check(r[S_ERR] && !r[S_BUSY], "READ+WRITE rejected");
        apb_w(STAT, 32'h20);
        apb_w(CMD, C_RECOVER|C_START); apb_r(STAT, r);
        $display("  CMD=RECOVER|START -> cmd_err=%0d busy=%0d", r[S_ERR], r[S_BUSY]);
        check(r[S_ERR] && !r[S_BUSY], "RECOVER+START rejected");
        repeat (2000) @(posedge pclk);
        check(mon.starts == n0 && scl === 1'b1 && sda === 1'b1, "no START, bus idle");
        apb_w(STAT, 32'h28);
        fin;

        // ---------------------------------------------------------------
        begin_test(3, "software flow with cmd_ready polling");
        wait_ready; apb_w(TXD, 8'hA0); apb_w(CMD, C_START|C_WRITE);
        wait_ready; apb_w(TXD, 8'h04); apb_w(CMD, C_WRITE);
        for (k = 0; k < 3; k = k + 1) begin
            wait_ready; apb_w(TXD, 8'h10 + k); apb_w(CMD, C_WRITE | ((k == 2) ? C_STOP : 0));
        end
        wait_ready; apb_r(STAT, r); check(r[S_ERR] == 0, "no rejected command");
        for (k = 0; k < 3; k = k + 1) begin dbg = 4 + k; #1 check(dd == 8'h10 + k, "reg written"); end
        $display("  reg[4..6] = %02h %02h %02h (expected 10 11 12)", u_s.mem[4], u_s.mem[5], u_s.mem[6]);
        fin;

        // ---------------------------------------------------------------
        begin_test(4, "reset during read -> SDA stuck low -> RECOVER");
        op(C_START|C_WRITE, 8'hA0); op(C_WRITE, 8'h08); op(C_WRITE|C_STOP, 8'h00);   // reg[8]=00
        op(C_START|C_WRITE, 8'hA0); op(C_WRITE, 8'h08); op(C_START|C_WRITE, 8'hA1);
        apb_w(CMD, C_READ);                                   // slave starts sending 00
        repeat (3) @(posedge scl); #500;
        $display("  master reset in the middle of the data byte at %0t", $time);
        mon_en = 0; presetn = 0; repeat (4) @(posedge pclk); presetn = 1; repeat (200) @(posedge pclk);
        apb_r(STAT, r);
        $display("  after reset: SCL=%0d SDA=%0d slave addressed=%0d", r[S_SCL], r[S_SDA], s_addressed);
        check(r[S_SCL] == 1 && r[S_SDA] == 0, "bus stuck: SDA held low by slave");
        apb_w(PRESC, 32'd32);
        apb_w(CMD, C_RECOVER); wait_done;
        repeat (200) @(posedge pclk); apb_r(STAT, r);
        $display("  after RECOVER: SCL=%0d SDA=%0d bus_busy=%0d slave addressed=%0d", r[S_SCL], r[S_SDA], r[4], s_addressed);
        check(r[S_SCL] && r[S_SDA], "bus released after RECOVER");
        check(!s_addressed, "slave back to idle");
        apb_w(STAT, 32'h8); mon_en = 1;
        op(C_START|C_WRITE, 8'hA0); check(!r[S_NACK], "new transfer: addr ACK");
        op(C_WRITE, 8'h09); op(C_WRITE|C_STOP, 8'h5A);
        dbg = 9; #1 check(dd == 8'h5A, "reg[9]=5A after recovery");
        fin;

        // ---------------------------------------------------------------
        begin_test(5, "SCL held low by slave -> timeout -> RECOVER");
        s_stretch = 1; s_scyc = 16'd30000;                    // 600 us > 200 us timeout
        op(C_START|C_WRITE, 8'hA0);                           // slave stretches after this ACK
        apb_w(TXD, 8'h0A); apb_w(CMD, C_WRITE); wait_done;
        $display("  STATUS = %03h: timeout=%0d busy=%0d at %0t", r[9:0], r[S_TOUT], r[S_BUSY], $time);
        check(r[S_TOUT] == 1 && r[S_BUSY] == 0, "STATUS.timeout set, master released");
        mon_en = 0; s_stretch = 0;
        wait (s_scl == 1'b0); repeat (100) @(posedge pclk);
        apb_w(STAT, 32'h8); apb_w(CMD, C_RECOVER); wait_done;
        repeat (200) @(posedge pclk); apb_r(STAT, r);
        check(r[S_TOUT] == 0 && r[S_SCL] && r[S_SDA], "RECOVER: timeout cleared, bus idle");
        apb_w(STAT, 32'h8); mon_en = 1;
        op(C_START|C_WRITE, 8'hA0); op(C_WRITE, 8'h0B); op(C_WRITE|C_STOP, 8'hC7);
        dbg = 11; #1 check(dd == 8'hC7, "reg[11]=C7 after timeout recovery");
        fin;

        begin_test(6, "protocol assertion self-test (illegal SDA edge)");
        n0 = mon.errors;
        t_sda = 1; #2000 t_scl = 1; #2000;                    // START, then SCL low
        repeat (3) begin t_sda = ~t_sda; #1000 t_scl = 0; #2000 t_scl = 1; #2000; end   // bits 1..3
        t_scl = 0; #1000;                                     // SCL high in bit 4
        t_sda = ~t_sda; #1000;                                // SDA changes while SCL high: illegal
        $display("  monitor flagged %0d violation(s) (expected 1)", mon.errors - n0);
        check(mon.errors - n0 == 1, "illegal SDA change detected by P1");
        mon_en = 0; t_scl = 0; t_sda = 0; #5000 mon_en = 1;    // release the bus
        #5000 mon.errors = n0;
        fin;

        check(mon.errors == 0, "protocol monitor: no assertion failures");
        $display("  protocol monitor: %0d START, %0d Sr, %0d STOP, %0d bits, %0d assertion failures", mon.starts, mon.rstarts, mon.stops, mon.bits, mon.errors);
        $display("--------------------------------------------------");
        $display("SUMMARY tb_i2c_robust: %0d/%0d tests PASS, %0d checks, %0d errors", tp, tp+tf, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: FAILED");
        #2000 $finish;
    end
    initial begin #30_000_000 $display("TIMEOUT"); $finish; end
endmodule
