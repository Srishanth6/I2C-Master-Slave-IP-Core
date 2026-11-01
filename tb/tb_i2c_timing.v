// tb_i2c_timing.v - exact SCL frequency vs formula, and I2C timing compliance (UM10204)
// Author: B. Srishanth Reddy
// For each prescale: write 3 bytes, then a repeated-START read of 2 bytes, then STOP, then a
// second transfer (for tBUF). The bus monitor measures the worst case of every parameter.
`timescale 1ns/1ps
module tb_i2c_timing;
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;                         // 50 MHz
    tri1 scl, sda;
    wire m_scl, m_sda, s_scl, s_sda;
    assign scl = m_scl ? 1'b0 : 1'bz; assign sda = m_sda ? 1'b0 : 1'bz;
    assign scl = s_scl ? 1'b0 : 1'bz; assign sda = s_sda ? 1'b0 : 1'bz;
    reg [15:0] prescale = 124;
    reg cv = 0, cs = 0, cp = 0, cr = 0, cw = 0, cn = 0; reg [7:0] td = 0;
    wire [7:0] rd; wire rx_nack, done, arb_lost, busy, bus_busy, tout;
    reg [1:0] mode = 0;
    i2c_master u_m (.clk(clk), .rst_n(rst_n), .prescale(prescale), .cmd_valid(cv), .cmd_start(cs),
        .cmd_stop(cp), .cmd_read(cr), .cmd_write(cw), .cmd_nack(cn), .tx_data(td), .rx_data(rd),
        .rx_nack(rx_nack), .done(done), .arb_lost(arb_lost), .busy(busy), .bus_busy(bus_busy), .timeout(tout),
        .scl_i(scl), .sda_i(sda), .scl_oe(m_scl), .sda_oe(m_sda));
    i2c_slave u_s (.clk(clk), .rst_n(rst_n), .own_addr(10'h050), .addr10_en(1'b0), .stretch_en(1'b0),
        .stretch_cycles(16'd0), .scl_i(scl), .sda_i(sda), .scl_oe(s_scl), .sda_oe(s_sda),
        .addressed(), .wr_strobe(), .dbg_addr(4'd0), .dbg_data());
    i2c_monitor #(.NAME("bus")) mon (.scl(scl), .sda(sda), .en(rst_n), .chk_mode(mode));

    integer errors = 0, checks = 0, tp = 0, tf = 0, e0, k;
    reg [7:0] test_id = 0;
    task check(input c, input [8*64-1:0] m);
        begin checks = checks + 1; if (!c) begin errors = errors + 1; $display("  [FAIL] %0s (t=%0t)", m, $time); end end
    endtask
    task cmd(input s, input p, input r, input w, input n, input [7:0] d);
        begin @(posedge clk); cs <= s; cp <= p; cr <= r; cw <= w; cn <= n; td <= d; cv <= 1;
              @(posedge clk); cv <= 0; @(posedge done); @(posedge clk); end
    endtask
    // SCL period of normal data bits (rise to rise, inside bytes only)
    realtime tr = 0, pmin = 1e12, pmax = 0;
    always @(posedge scl) begin
        if (tr > 0 && mon.busy && mon.nbit > 1 && mon.nbit <= 9) begin
            if ($realtime - tr < pmin) pmin = $realtime - tr;
            if ($realtime - tr > pmax) pmax = $realtime - tr;
        end
        tr = $realtime;
    end

    task run(input [7:0] id, input [15:0] p, input [1:0] m, input [8*32-1:0] n, input integer exp_viol);
        real fexp, fmeas; integer e1;
        begin
            test_id = id; e0 = errors; e1 = mon.errors; prescale = p; mode = m;
            $display("TEST %0d: %0s, prescale=%0d", id, n, p);
            mon.clear; pmin = 1e12; pmax = 0; tr = 0;
            cmd(1,0,0,1,0,8'hA0); cmd(0,0,0,1,0,8'h03); cmd(0,0,0,1,0,8'h55); cmd(0,1,0,1,0,8'hAA);
            cmd(1,0,0,1,0,8'hA0); cmd(0,0,0,1,0,8'h03); cmd(1,0,0,1,0,8'hA1);
            cmd(0,0,1,0,0,0); check(rd == 8'h55, "read back 55");
            cmd(0,1,1,0,1,0); check(rd == 8'hAA, "read back AA");
            fexp  = 50.0e3 / (4.0 * (p + 1) + 3.0);            // kHz
            fmeas = 1.0e6 / pmin;
            $display("  SCL period min %0.1f ns max %0.1f ns -> %0.2f kHz (formula f_clk/(4(p+1)+3) = %0.2f kHz)",
                     pmin, pmax, fmeas, fexp);
            check(pmin == pmax, "SCL period constant");
            check(pmin == 20.0 * (4 * (p + 1) + 3), "SCL period matches formula exactly");
            mon.report;
            if (exp_viol == 0) check(mon.errors == e1, "bus monitor: no protocol/timing violation");
            else begin
                $display("  expected: monitor must flag %0d timing violation(s) (tLOW < 1300 ns) -> flagged %0d", exp_viol, mon.errors - e1);
                check(mon.errors - e1 == exp_viol, "monitor detects the tLOW violation");
                mon.errors = e1;
            end
            if (errors == e0) begin tp = tp + 1; $display("TEST %0d: %0s ... PASS", id, n); end
            else begin tf = tf + 1; $display("TEST %0d: %0s ... FAIL", id, n); end
        end
    endtask

    initial begin
        $timeformat(-9, 1, " ns", 10);
        if (!$test$plusargs("nodump")) begin $dumpfile("waves/tb_i2c_timing.vcd"); $dumpvars(0, tb_i2c_timing); end
        repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);
        run(1, 16'd124, 2'd1, "Standard-mode 100 kHz", 0);
        run(2, 16'd32,  2'd2, "Fast-mode, fastest compliant", 0);
        run(3, 16'd30,  2'd2, "prescale 30 violates Fast-mode", 1);
        run(4, 16'd10,  2'd0, "formula check only (no limits)", 0);
        $display("--------------------------------------------------");
        $display("SUMMARY tb_i2c_timing: %0d/%0d tests PASS, %0d checks, %0d errors", tp, tp+tf, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: FAILED");
        #2000 $finish;
    end
    initial begin #20_000_000 $display("TIMEOUT"); $finish; end
endmodule
