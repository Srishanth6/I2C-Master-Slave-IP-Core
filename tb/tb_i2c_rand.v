// tb_i2c_rand.v - seeded constrained-random transactions with a scoreboard
// Author: B. Srishanth Reddy
// Each transaction picks at random: target (7-bit slave 0x50, 10-bit slave 0x2A5, or an empty
// address that must NACK), write burst or random-access read, start pointer, length 1..6,
// data bytes, SCL speed (prescale 32/49/124) and slave clock stretching on/off.
// A reference model of both register files predicts every read byte and the final contents.
// Run: vvp tb_i2c_rand.vvp +seed=<n> +ntx=<n>   (defaults seed=1, ntx=150)
`timescale 1ns/1ps
module tb_i2c_rand;
    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk;
    tri1 scl, sda;
    wire m_scl, m_sda, s7_scl, s7_sda, s10_scl, s10_sda;
    assign scl = m_scl  ? 1'b0 : 1'bz; assign sda = m_sda  ? 1'b0 : 1'bz;
    assign scl = s7_scl ? 1'b0 : 1'bz; assign sda = s7_sda ? 1'b0 : 1'bz;
    assign scl = s10_scl? 1'b0 : 1'bz; assign sda = s10_sda? 1'b0 : 1'bz;
    reg [15:0] prescale = 124;
    reg cv = 0, cs = 0, cp = 0, cr = 0, cw = 0, cn = 0; reg [7:0] td = 0;
    wire [7:0] rd; wire rx_nack, done, arb_lost, busy, bus_busy, tout;
    reg st7 = 0; reg [15:0] sc7 = 0;
    i2c_master u_m (.clk(clk), .rst_n(rst_n), .prescale(prescale), .cmd_valid(cv), .cmd_start(cs),
        .cmd_stop(cp), .cmd_read(cr), .cmd_write(cw), .cmd_nack(cn), .tx_data(td), .rx_data(rd),
        .rx_nack(rx_nack), .done(done), .arb_lost(arb_lost), .busy(busy), .bus_busy(bus_busy), .timeout(tout),
        .scl_i(scl), .sda_i(sda), .scl_oe(m_scl), .sda_oe(m_sda));
    i2c_slave u_s7 (.clk(clk), .rst_n(rst_n), .own_addr(10'h050), .addr10_en(1'b0), .stretch_en(st7),
        .stretch_cycles(sc7), .scl_i(scl), .sda_i(sda), .scl_oe(s7_scl), .sda_oe(s7_sda),
        .addressed(), .wr_strobe(), .dbg_addr(4'd0), .dbg_data());
    i2c_slave u_s10 (.clk(clk), .rst_n(rst_n), .own_addr(10'h2A5), .addr10_en(1'b1), .stretch_en(1'b0),
        .stretch_cycles(16'd0), .scl_i(scl), .sda_i(sda), .scl_oe(s10_scl), .sda_oe(s10_sda),
        .addressed(), .wr_strobe(), .dbg_addr(4'd0), .dbg_data());
    i2c_monitor #(.NAME("bus")) mon (.scl(scl), .sda(sda), .en(rst_n), .chk_mode(2'd0));

    reg [7:0] m7 [0:15], m10 [0:15];       // scoreboard reference model
    integer seed0, seed = 1, ntx = 150, errors = 0, checks = 0, i, t, len, tgt, ptr, b;
    integer n_wr = 0, n_rd = 0, n_nack = 0, n_bytes = 0, n_10 = 0, n_str = 0;
    reg [7:0] exp, d;
    reg [7:0] test_id = 0;

    task check(input c, input [8*64-1:0] m);
        begin checks = checks + 1; if (!c) begin errors = errors + 1; $display("  [FAIL] %0s (t=%0t)", m, $time); end end
    endtask
    task cmd(input s, input p, input r, input w, input n, input [7:0] dd);
        begin @(posedge clk); cs <= s; cp <= p; cr <= r; cw <= w; cn <= n; td <= dd; cv <= 1;
              @(posedge clk); cv <= 0; @(posedge done); @(posedge clk); end
    endtask
    task addr_w(input integer tg); begin           // address phase for a write, returns rx_nack
        if (tg == 1) begin cmd(1,0,0,1,0,8'hF4); if (!rx_nack) cmd(0,0,0,1,0,8'hA5); end
        else if (tg == 0) cmd(1,0,0,1,0,8'hA0);
        else cmd(1,0,0,1,0,8'hB6);                   // 0x5B: nobody there
    end endtask

    initial begin
        $timeformat(-9, 0, " ns", 10);
        if ($value$plusargs("seed=%d", seed)) ; if ($value$plusargs("ntx=%d", ntx)) ; seed0 = seed;
        $display("TEST 1: %0d random transactions, seed=%0d", ntx, seed0);
        for (i = 0; i < 16; i = i + 1) begin m7[i] = 0; m10[i] = 0; end
        repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);
        for (t = 0; t < ntx; t = t + 1) begin
            test_id = t[7:0];
            case ($unsigned($random(seed)) % 3) 0: prescale = 32; 1: prescale = 49; default: prescale = 124; endcase
            st7 = ($unsigned($random(seed)) % 4) == 0; sc7 = 50 + $unsigned($random(seed)) % 400; n_str = n_str + st7;
            b = $unsigned($random(seed)) % 10;  tgt = (b < 6) ? 0 : (b < 9) ? 1 : 2;
            ptr = $unsigned($random(seed)) % 16; len = 1 + $unsigned($random(seed)) % 6;
            if (tgt == 2) begin                                    // must NACK
                addr_w(2); check(rx_nack, "NACK from empty address"); cmd(0,1,0,0,0,0); n_nack = n_nack + 1;
            end else if ($unsigned($random(seed)) % 2) begin      // write burst
                addr_w(tgt); check(!rx_nack, "address ACK");
                cmd(0,0,0,1,0,ptr[7:0]); check(!rx_nack, "pointer ACK");
                for (i = 0; i < len; i = i + 1) begin
                    d = $random(seed);
                    cmd(0,(i==len-1),0,1,0,d); check(!rx_nack, "data ACK");
                    if (tgt == 0) m7[(ptr+i)%16] = d; else m10[(ptr+i)%16] = d;
                    n_bytes = n_bytes + 1;
                end
                n_wr = n_wr + 1; n_10 = n_10 + tgt;
            end else begin                                         // random-access read
                addr_w(tgt); check(!rx_nack, "address ACK");
                cmd(0,0,0,1,0,ptr[7:0]); check(!rx_nack, "pointer ACK");
                cmd(1,0,0,1,0, tgt ? 8'hF5 : 8'hA1); check(!rx_nack, "Sr read address ACK");
                for (i = 0; i < len; i = i + 1) begin
                    cmd(0,(i==len-1),1,0,(i==len-1),0);
                    exp = tgt ? m10[(ptr+i)%16] : m7[(ptr+i)%16];
                    if (rd !== exp) $display("  tx %0d: read %s[%0d] = %02h expected %02h", t, tgt ? "s10" : "s7", (ptr+i)%16, rd, exp);
                    check(rd === exp, "read data matches scoreboard");
                    n_bytes = n_bytes + 1;
                end
                n_rd = n_rd + 1; n_10 = n_10 + tgt;
            end
            check(!bus_busy, "bus free after each transaction");
        end
        // final register-file comparison
        for (i = 0; i < 16; i = i + 1) begin
            check(u_s7.mem[i] === m7[i], "final s7 register file");
            check(u_s10.mem[i] === m10[i], "final s10 register file");
        end
        check(mon.errors == 0, "protocol monitor: no assertion failures");
        $display("  %0d writes, %0d reads, %0d NACK probes, %0d data bytes, %0d to 10-bit slave, %0d with stretching",
                 n_wr, n_rd, n_nack, n_bytes, n_10, n_str);
        $display("  protocol monitor: %0d START, %0d Sr, %0d STOP, %0d bits, %0d assertion failures", mon.starts, mon.rstarts, mon.stops, mon.bits, mon.errors);
        if (errors == 0) $display("TEST 1: %0d random transactions, seed=%0d ... PASS", ntx, seed);
        else $display("TEST 1: %0d random transactions, seed=%0d ... FAIL", ntx, seed);
        $display("--------------------------------------------------");
        $display("SUMMARY tb_i2c_rand: %0d/1 tests PASS, %0d checks, %0d errors", errors == 0, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED"); else $display("RESULT: FAILED");
        #2000 $finish;
    end
    initial begin #2_000_000_000 $display("TIMEOUT"); $finish; end
endmodule
