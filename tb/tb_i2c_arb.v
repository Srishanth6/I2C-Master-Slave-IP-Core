// tb_i2c_arb.v - multi-master arbitration: two masters start at the same time
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_i2c_arb;
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;
    tri1 scl, sda;
    wire a_scl, a_sda, b_scl, b_sda, s1_scl, s1_sda, s2_scl, s2_sda;
    assign scl = a_scl ? 1'b0 : 1'bz;  assign sda = a_sda ? 1'b0 : 1'bz;
    assign scl = b_scl ? 1'b0 : 1'bz;  assign sda = b_sda ? 1'b0 : 1'bz;
    assign scl = s1_scl? 1'b0 : 1'bz;  assign sda = s1_sda? 1'b0 : 1'bz;
    assign scl = s2_scl? 1'b0 : 1'bz;  assign sda = s2_sda? 1'b0 : 1'bz;

    reg av=0, as=0, ap=0, aw=0; reg [7:0] ad=0;
    reg bv=0, bs=0, bp=0, bw=0; reg [7:0] bd=0;
    wire a_done, a_arb, a_nack, a_busbusy, b_done, b_arb, b_nack, b_busbusy;
    reg [3:0] dbg = 0; wire [7:0] d50, d48;

    i2c_master m_a (.clk(clk), .rst_n(rst_n), .prescale(16'd30), .cmd_valid(av), .cmd_start(as),
        .cmd_stop(ap), .cmd_read(1'b0), .cmd_write(aw), .cmd_nack(1'b0), .tx_data(ad), .rx_data(),
        .rx_nack(a_nack), .done(a_done), .arb_lost(a_arb), .busy(), .bus_busy(a_busbusy),
        .scl_i(scl), .sda_i(sda), .scl_oe(a_scl), .sda_oe(a_sda));
    i2c_master m_b (.clk(clk), .rst_n(rst_n), .prescale(16'd30), .cmd_valid(bv), .cmd_start(bs),
        .cmd_stop(bp), .cmd_read(1'b0), .cmd_write(bw), .cmd_nack(1'b0), .tx_data(bd), .rx_data(),
        .rx_nack(b_nack), .done(b_done), .arb_lost(b_arb), .busy(), .bus_busy(b_busbusy),
        .scl_i(scl), .sda_i(sda), .scl_oe(b_scl), .sda_oe(b_sda));
    i2c_slave s50 (.clk(clk), .rst_n(rst_n), .own_addr(10'h050), .addr10_en(1'b0), .stretch_en(1'b0),
        .stretch_cycles(16'd0), .scl_i(scl), .sda_i(sda), .scl_oe(s1_scl), .sda_oe(s1_sda),
        .addressed(), .wr_strobe(), .dbg_addr(dbg), .dbg_data(d50));
    i2c_slave s48 (.clk(clk), .rst_n(rst_n), .own_addr(10'h048), .addr10_en(1'b0), .stretch_en(1'b0),
        .stretch_cycles(16'd0), .scl_i(scl), .sda_i(sda), .scl_oe(s2_scl), .sda_oe(s2_sda),
        .addressed(), .wr_strobe(), .dbg_addr(dbg), .dbg_data(d48));

    i2c_monitor #(.NAME("bus")) mon (.scl(scl), .sda(sda), .en(rst_n), .chk_mode(2'd0));
    integer errors = 0, checks = 0, tp = 0, tf = 0, e0;
    reg [7:0] test_id = 0;
    task check(input c, input [8*64-1:0] m);
        begin checks = checks + 1; if (!c) begin errors = errors + 1; $display("  [FAIL] %0s (t=%0t)", m, $time); end end
    endtask
    task fin(input [8*48-1:0] n);
        begin if (errors == e0) begin tp = tp + 1; $display("TEST %0d: %0s ... PASS", test_id, n); end
              else begin tf = tf + 1; $display("TEST %0d: %0s ... FAIL", test_id, n); end end
    endtask
    task acmd(input s, input p, input w, input [7:0] d);
        begin @(posedge clk); as<=s; ap<=p; aw<=w; ad<=d; av<=1; @(posedge clk); av<=0; @(posedge a_done); @(posedge clk); end
    endtask
    task bcmd(input s, input p, input w, input [7:0] d);
        begin @(posedge clk); bs<=s; bp<=p; bw<=w; bd<=d; bv<=1; @(posedge clk); bv<=0; @(posedge b_done); @(posedge clk); end
    endtask

    reg a_lost_seen;
    initial begin
        $timeformat(-9, 0, " ns", 10);
        $dumpfile("waves/tb_i2c_arb.vcd");
        $dumpvars(0, tb_i2c_arb);
        repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);

        test_id = 1; e0 = errors;
        $display("TEST 1: simultaneous START, A sends 0xA0 (0x50+W), B sends 0x90 (0x48+W)");
        // both masters get their command in the same clock cycle
        @(posedge clk); as<=1; ap<=0; aw<=1; ad<=8'hA0; av<=1; bs<=1; bp<=0; bw<=1; bd<=8'h90; bv<=1;
        @(posedge clk); av<=0; bv<=0;
        fork
            begin @(posedge a_done); a_lost_seen = a_arb; $display("  master A done at %0t, arb_lost=%0d", $time, a_arb); end
            begin @(posedge b_done); $display("  master B done at %0t, arb_lost=%0d, rx_nack=%0d", $time, b_arb, b_nack); end
        join
        check(a_lost_seen == 1'b1, "master A lost arbitration");
        check(b_arb == 1'b0, "master B did not lose");
        check(b_nack == 1'b0, "slave 0x48 ACKed master B");
        check(a_busbusy == 1'b1, "master A sees bus busy");
        // B finishes its transfer undisturbed
        bcmd(0,0,1,8'h01); check(!b_nack, "ptr ACK");
        bcmd(0,0,1,8'hBE); check(!b_nack, "data ACK");
        bcmd(0,1,1,8'hEF); check(!b_nack, "data ACK");
        repeat (10) @(posedge clk);
        dbg = 1; #1 check(d48 == 8'hBE, "s48 reg[1]=BE");
        dbg = 2; #1 check(d48 == 8'hEF, "s48 reg[2]=EF");
        dbg = 1; #1 check(d50 == 8'h00, "s50 untouched");
        check(!a_busbusy, "A sees bus free after B's STOP");
        fin("arbitration lost detected, winner completes");

        test_id = 2; e0 = errors;
        $display("TEST 2: losing master retries after STOP");
        acmd(1,0,1,8'hA0); check(!a_arb && !a_nack, "A wins idle bus, ACK");
        acmd(0,0,1,8'h01); acmd(0,1,1,8'h5A); check(!a_nack, "data ACK");
        repeat (10) @(posedge clk);
        dbg = 1; #1 check(d50 == 8'h5A, "s50 reg[1]=5A");
        fin("retry after arbitration loss");

        test_id = 3; e0 = errors;
        $display("TEST 3: same address, arbitration on data byte (A=0x33, B=0x31)");
        @(posedge clk); as<=1; ap<=0; aw<=1; ad<=8'hA0; av<=1; bs<=1; bp<=0; bw<=1; bd<=8'hA0; bv<=1;
        @(posedge clk); av<=0; bv<=0;
        fork @(posedge a_done); @(posedge b_done); join
        check(!a_arb && !b_arb, "identical address: nobody loses");
        @(posedge clk); ad<=8'h03; bd<=8'h03; av<=1; bv<=1; as<=0; bs<=0; @(posedge clk); av<=0; bv<=0;
        fork @(posedge a_done); @(posedge b_done); join
        // data byte: A=0x33 (0011_0011), B=0x31 (0011_0001) -> differ at bit 1, A loses
        @(posedge clk); ad<=8'h33; bd<=8'h31; ap<=1; bp<=1; av<=1; bv<=1; @(posedge clk); av<=0; bv<=0;
        fork
            begin @(posedge a_done); a_lost_seen = a_arb; end
            @(posedge b_done);
        join
        $display("  data-phase: A arb_lost=%0d, B arb_lost=%0d", a_lost_seen, b_arb);
        check(a_lost_seen && !b_arb, "A loses on data bit 1");
        repeat (10) @(posedge clk);
        dbg = 3; #1 $display("  s50 reg[3] = %02h (expected 31)", d50); check(d50 == 8'h31, "winner data written");
        fin("arbitration in data phase");
        check(mon.errors == 0, "protocol monitor: no assertion failures");
        $display("  protocol monitor: %0d START, %0d Sr, %0d STOP, %0d bits, %0d assertion failures", mon.starts, mon.rstarts, mon.stops, mon.bits, mon.errors);

        $display("--------------------------------------------------");
        $display("SUMMARY tb_i2c_arb: %0d/%0d tests PASS, %0d checks, %0d errors", tp, tp+tf, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: FAILED");
        #2000 $finish;
    end
    initial begin #20_000_000 $display("TIMEOUT"); $finish; end
endmodule
