// i2c_monitor.v - passive I2C bus monitor: protocol assertions + timing measurement
// Author: B. Srishanth Reddy
// Protocol checks (always on while en=1):
//   P1 SDA may change while SCL is high only as START/STOP, i.e. only during the first
//      SCL-high period of a byte frame (bit 1 of 9) - never in bits 2..9.
//   P2 no X/Z-to-X values on SCL/SDA (pull-ups make undriven lines 1).
//   P3 a STOP or repeated START is never seen in the middle of a byte.
// Timing (measured every frame; checked against limits when chk_mode = 1 SM, 2 FM):
//   tLOW tHIGH tSU;STA tHD;STA tSU;DAT tHD;DAT (min, and max = tVD;DAT) tSU;STO tBUF
`timescale 1ns/1ps
module i2c_monitor #(parameter NAME = "mon") (
    input wire       scl,
    input wire       sda,
    input wire       en,
    input wire [1:0] chk_mode
);
    integer errors = 0, starts = 0, stops = 0, rstarts = 0, bits = 0;
    integer nbit = 0;            // SCL rising edges since START / last ACK fall
    reg     busy = 0;
    realtime t_rise = -1, t_fall = -1, t_sda = -1, t_start = -1, t_stop = -1;
    reg      first_fall = 0;     // waiting for the SCL fall after a START
    reg      sda_chg_low = 0;    // SDA changed during the current SCL-low period
    realtime m_low, m_high, m_susta, m_hdsta, m_sudat, m_hddat, x_hddat, m_susto, m_buf;

    task clear; begin
        m_low = 1e12; m_high = 1e12; m_susta = 1e12; m_hdsta = 1e12; m_sudat = 1e12;
        m_hddat = 1e12; x_hddat = 0; m_susto = 1e12; m_buf = 1e12;
    end endtask
    initial clear;

    task err(input [8*64-1:0] m); begin
        errors = errors + 1;
        $display("  [ASSERT %0s] %0s (t=%0t)", NAME, m, $time);
    end endtask

    always @(scl or sda) if (en && ((scl !== 1'b0 && scl !== 1'b1) || (sda !== 1'b0 && sda !== 1'b1)))
        err("P2 SCL/SDA is X or Z");

    // re-synchronise when (re-)enabled, e.g. after an aborted transfer
    always @(posedge en) begin busy = 0; nbit = 0; first_fall = 0; sda_chg_low = 0; end

    // SDA edges
    always @(negedge sda) if (en) begin
        if (scl === 1'b1) begin                         // START or repeated START
            if (busy && nbit > 1) err("P1/P3 START inside a byte");
            if (busy) begin rstarts = rstarts + 1; if ($realtime - t_rise < m_susta) m_susta = $realtime - t_rise; end
            else if (t_stop >= 0 && $realtime - t_stop < m_buf) m_buf = $realtime - t_stop;
            starts = starts + 1; busy = 1; nbit = 0; t_start = $realtime; first_fall = 1;
        end else sda_low_change;
    end
    always @(posedge sda) if (en) begin
        if (scl === 1'b1) begin                         // STOP
            if (busy && nbit > 1) err("P1/P3 STOP inside a byte");
            if (busy && $realtime - t_rise < m_susto) m_susto = $realtime - t_rise;
            stops = stops + 1; busy = 0; t_stop = $realtime; nbit = 0;
        end else sda_low_change;
    end
    task sda_low_change; begin
        t_sda = $realtime; sda_chg_low = 1;
        if (busy && t_fall >= 0) begin
            if ($realtime - t_fall < m_hddat) m_hddat = $realtime - t_fall;
            if ($realtime - t_fall > x_hddat) x_hddat = $realtime - t_fall;
        end
    end endtask

    // SCL edges
    always @(posedge scl) if (en) begin
        if (busy) begin
            if (t_fall >= 0 && $realtime - t_fall < m_low) m_low = $realtime - t_fall;
            if (sda_chg_low && $realtime - t_sda < m_sudat) m_sudat = $realtime - t_sda;
            nbit = nbit + 1; bits = bits + 1;
        end
        t_rise = $realtime; sda_chg_low = 0;
    end
    always @(negedge scl) if (en) begin
        if (busy) begin
            if (first_fall) begin
                if ($realtime - t_start < m_hdsta) m_hdsta = $realtime - t_start;
                first_fall = 0;
            end
            if (t_rise >= t_start && $realtime - t_rise < m_high) m_high = $realtime - t_rise;
            if (nbit == 9) nbit = 0;
        end
        t_fall = $realtime; sda_chg_low = 0;
    end

    // limits (ns): index 1 = Standard-mode, 2 = Fast-mode (UM10204 Table 10)
    function real lim(input integer k, input integer mode); begin
        case (k)
            0: lim = (mode == 2) ? 1300 : 4700;   // tLOW
            1: lim = (mode == 2) ?  600 : 4000;   // tHIGH
            2: lim = (mode == 2) ?  600 : 4700;   // tSU;STA
            3: lim = (mode == 2) ?  600 : 4000;   // tHD;STA
            4: lim = (mode == 2) ?  100 :  250;   // tSU;DAT
            5: lim = 0;                           // tHD;DAT min
            6: lim = (mode == 2) ?  900 : 3450;   // tVD;DAT max
            7: lim = (mode == 2) ?  600 : 4000;   // tSU;STO
            8: lim = (mode == 2) ? 1300 : 4700;   // tBUF
        endcase
    end endfunction

    task row(input [8*10-1:0] n, input realtime v, input integer k, input integer mx); begin
        if (v >= 1e11) $display("  | %-9s | %10s | %8s | n/a      |", n, "-", "-");
        else begin
            if (chk_mode != 0 && (mx ? (v > lim(k, chk_mode)) : (v < lim(k, chk_mode)))) err({"timing ", n});
            $display("  | %-9s | %10.1f | %s%7.0f | %-8s |", n, v, mx ? "<=" : ">=", lim(k, chk_mode == 0 ? 2 : chk_mode),
                     (chk_mode == 0) ? "info" :
                     (mx ? (v <= lim(k, chk_mode)) : (v >= lim(k, chk_mode))) ? "PASS" : "FAIL");
        end
    end endtask
    // print the table of worst-case (minimum) values since the last clear
    task report; begin
        $display("  | parameter | measured ns | limit ns | result   |   (%0s)", chk_mode == 1 ? "Standard-mode limits" : chk_mode == 2 ? "Fast-mode limits" : "Fast-mode limits, info only - not checked");
        row("tLOW",    m_low,   0, 0); row("tHIGH",   m_high,  1, 0);
        row("tSU;STA", m_susta, 2, 0); row("tHD;STA", m_hdsta, 3, 0);
        row("tSU;DAT", m_sudat, 4, 0); row("tHD;DAT", m_hddat, 5, 0);
        row("tVD;DAT", (x_hddat == 0) ? 1e12 : x_hddat, 6, 1);
        row("tSU;STO", m_susto, 7, 0); row("tBUF",    m_buf,   8, 0);
    end endtask
endmodule
