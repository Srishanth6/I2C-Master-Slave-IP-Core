// tb_i2c_apb.v - APB wrapper test: register access + full I2C transfers driven by software sequence
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_i2c_apb;
    reg pclk = 0, presetn = 0;
    always #10 pclk = ~pclk;
    tri1 scl, sda;
    wire m_scl, m_sda, s_scl, s_sda, irq;
    assign scl = m_scl ? 1'b0 : 1'bz; assign sda = m_sda ? 1'b0 : 1'bz;
    assign scl = s_scl ? 1'b0 : 1'bz; assign sda = s_sda ? 1'b0 : 1'bz;

    reg psel = 0, penable = 0, pwrite = 0; reg [7:0] paddr = 0; reg [31:0] pwdata = 0;
    wire [31:0] prdata; wire pready, pslverr;
    reg [3:0] dbg = 0; wire [7:0] dd;

    i2c_apb dut (.pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr), .irq(irq),
        .scl_i(scl), .sda_i(sda), .scl_oe(m_scl), .sda_oe(m_sda));
    i2c_slave u_s (.clk(pclk), .rst_n(presetn), .own_addr(10'h050), .addr10_en(1'b0), .stretch_en(1'b1),
        .stretch_cycles(16'd100), .scl_i(scl), .sda_i(sda), .scl_oe(s_scl), .sda_oe(s_sda),
        .addressed(), .wr_strobe(), .dbg_addr(dbg), .dbg_data(dd));

    localparam CTRL=8'h00, PRESC=8'h04, TXD=8'h08, RXD=8'h0C, CMD=8'h10, STAT=8'h14;
    localparam C_START=1, C_STOP=2, C_READ=4, C_WRITE=8, C_NACK=16;
    i2c_monitor #(.NAME("bus")) mon (.scl(scl), .sda(sda), .en(presetn), .chk_mode(2'd0));
    integer errors = 0, checks = 0, tp = 0, tf = 0, e0;
    reg [7:0] test_id = 0; reg [31:0] r;

    task check(input c, input [8*64-1:0] m);
        begin checks = checks + 1; if (!c) begin errors = errors + 1; $display("  [FAIL] %0s (t=%0t)", m, $time); end end
    endtask
    task fin(input [8*48-1:0] n);
        begin if (errors == e0) begin tp = tp + 1; $display("TEST %0d: %0s ... PASS", test_id, n); end
              else begin tf = tf + 1; $display("TEST %0d: %0s ... FAIL", test_id, n); end end
    endtask
    task apb_w(input [7:0] a, input [31:0] d);
        begin @(posedge pclk); psel<=1; pwrite<=1; paddr<=a; pwdata<=d; penable<=0;
              @(posedge pclk); penable<=1; @(posedge pclk); psel<=0; penable<=0; pwrite<=0; end
    endtask
    task apb_r(input [7:0] a, output [31:0] d);
        begin @(posedge pclk); psel<=1; pwrite<=0; paddr<=a; penable<=0;
              @(posedge pclk); penable<=1; @(negedge pclk); d = prdata; @(posedge pclk); psel<=0; penable<=0; end
    endtask
    // software driver: write TXDATA, issue CMD, poll STATUS.done
    task i2c_op(input [7:0] c, input [7:0] d);
        begin
            apb_w(TXD, d); apb_w(CMD, c);
            r = 0; while (!r[3]) apb_r(STAT, r);
        end
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 10);
        $dumpfile("waves/tb_i2c_apb.vcd");
        $dumpvars(0, tb_i2c_apb);
        repeat (5) @(posedge pclk); presetn = 1; repeat (5) @(posedge pclk);

        test_id = 1; e0 = errors; $display("TEST 1: register reset values and read/write");
        apb_r(PRESC, r); $display("  PRESCALE reset = %0d (expected 124)", r); check(r == 124, "PRESCALE reset");
        apb_r(STAT, r);  $display("  STATUS reset = %03h (expected 340: cmd_ready, SCL=1, SDA=1)", r); check(r == 32'h340, "STATUS reset value");
        apb_w(PRESC, 32'd32); apb_r(PRESC, r); check(r == 32, "PRESCALE rw");
        apb_w(TXD, 32'h5A);   apb_r(TXD, r);   check(r == 32'h5A, "TXDATA rw");
        apb_w(CTRL, 32'h1);   apb_r(CTRL, r);  check(r == 1, "CTRL rw");
        check(pready == 1 && pslverr == 0, "PREADY=1, PSLVERR=0");
        fin("APB register access");

        test_id = 2; e0 = errors; $display("TEST 2: APB-driven 7-bit write (Fast-mode 370 kHz, slave stretching)");
        i2c_op(C_START|C_WRITE, 8'hA0); check(r[1] == 0, "addr ACK");
        check(irq == 1, "irq raised on done (irq_en=1)");
        i2c_op(C_WRITE, 8'h00);          check(r[1] == 0, "ptr ACK");
        i2c_op(C_WRITE, 8'hDE);          check(r[1] == 0, "data ACK");
        i2c_op(C_WRITE|C_STOP, 8'hAD);   check(r[1] == 0, "data ACK");
        dbg = 0; #1 check(dd == 8'hDE, "reg[0]=DE");
        dbg = 1; #1 check(dd == 8'hAD, "reg[1]=AD");
        apb_w(STAT, 32'h8); apb_r(STAT, r); check(r[3] == 0 && irq == 0, "done W1C clears irq");
        fin("APB write transfer");

        test_id = 3; e0 = errors; $display("TEST 3: APB-driven read with repeated START");
        i2c_op(C_START|C_WRITE, 8'hA0); i2c_op(C_WRITE, 8'h00);
        i2c_op(C_START|C_WRITE, 8'hA1); check(r[1] == 0, "Sr addr+R ACK");
        i2c_op(C_READ, 8'h00);           apb_r(RXD, r); $display("  RXDATA = %02h (expected de)", r[7:0]); check(r[7:0] == 8'hDE, "rd DE");
        i2c_op(C_READ|C_NACK|C_STOP, 0); apb_r(RXD, r); $display("  RXDATA = %02h (expected ad)", r[7:0]); check(r[7:0] == 8'hAD, "rd AD");
        apb_r(STAT, r); check(r[4] == 0 && r[0] == 0, "bus free, not busy");
        fin("APB read transfer");

        test_id = 4; e0 = errors; $display("TEST 4: NACK reported in STATUS");
        i2c_op(C_START|C_WRITE, 8'hE0); $display("  STATUS = %05b (bit1 rx_nack)", r[4:0]); check(r[1] == 1, "STATUS.rx_nack=1");
        i2c_op(C_STOP, 0);
        fin("NACK status");
        check(mon.errors == 0, "protocol monitor: no assertion failures");
        $display("  protocol monitor: %0d START, %0d Sr, %0d STOP, %0d bits, %0d assertion failures", mon.starts, mon.rstarts, mon.stops, mon.bits, mon.errors);

        $display("--------------------------------------------------");
        $display("SUMMARY tb_i2c_apb: %0d/%0d tests PASS, %0d checks, %0d errors", tp, tp+tf, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: FAILED");
        #2000 $finish;
    end
    initial begin #20_000_000 $display("TIMEOUT"); $finish; end
endmodule
