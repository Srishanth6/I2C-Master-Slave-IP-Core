// i2c_apb.v - APB (AMBA 3) register wrapper around i2c_master
// Author: B. Srishanth Reddy
// 0x00 CTRL     [0] irq_en
// 0x04 PRESCALE [15:0]           (reset 124 = 100 kHz at 50 MHz)
// 0x08 TXDATA   [7:0]
// 0x0C RXDATA   [7:0]  RO
// 0x10 CMD      [0] START [1] STOP [2] READ [3] WRITE [4] NACK [5] RECOVER   (WO)
//               A CMD write is accepted only when STATUS.cmd_ready = 1. A write while the
//               master is busy, or an invalid command (READ+WRITE, RECOVER with other bits),
//               is rejected: nothing is sent and the sticky STATUS.cmd_err flag is set.
//               RECOVER = bus-clear: 9 SCL pulses with SDA released, then a STOP.
// 0x14 STATUS   [0] busy [1] rx_nack [2] arb_lost [3] done (W1C) [4] bus_busy
//               [5] cmd_err (W1C) [6] cmd_ready [7] timeout [8] SCL line [9] SDA line
//               Software must poll cmd_ready (or wait for done/irq) before each CMD write.
// irq = CTRL.irq_en & (done | cmd_err)
`timescale 1ns/1ps
module i2c_apb #(
    parameter TIMEOUT_CLKS = 1_250_000
)(
    input  wire        pclk,
    input  wire        presetn,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    output wire        irq,
    input  wire        scl_i,
    input  wire        sda_i,
    output wire        scl_oe,
    output wire        sda_oe
);
    reg        irq_en;
    reg [15:0] prescale;
    reg [7:0]  txdata;
    reg        cmd_valid;
    reg [4:0]  cmd;
    reg        done_st, cmd_err;
    reg [1:0]  scl_q, sda_q;
    wire [7:0] rx_data;
    wire       rx_nack, done, arb_lost, busy, bus_busy, timeout;
    wire       cmd_ready = ~busy & ~cmd_valid;
    wire       cmd_bad   = (pwdata[2] & pwdata[3]) | (pwdata[5] & (|pwdata[4:0]));

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    wire wr = psel & penable & pwrite;

    always @(posedge pclk or negedge presetn)
        if (!presetn) begin
            irq_en <= 0; prescale <= 16'd124; txdata <= 0; cmd_valid <= 0; cmd <= 0; done_st <= 0; cmd_err <= 0; scl_q <= 2'b11; sda_q <= 2'b11;
        end else begin
            cmd_valid <= 1'b0;
            scl_q <= {scl_q[0], scl_i}; sda_q <= {sda_q[0], sda_i};
            if (done) done_st <= 1'b1;
            if (wr) case (paddr[7:2])
                6'h0: irq_en   <= pwdata[0];
                6'h1: prescale <= pwdata[15:0];
                6'h2: txdata   <= pwdata[7:0];
                6'h4: if (!cmd_ready || cmd_bad) cmd_err <= 1'b1;            // rejected
                      else if (pwdata[5]) begin                              // RECOVER
                          cmd <= 5'b10110; cmd_valid <= 1'b1; done_st <= 1'b0; // 9 clocks, SDA released, STOP
                      end else begin cmd <= pwdata[4:0]; cmd_valid <= 1'b1; done_st <= 1'b0; end
                6'h5: begin if (pwdata[3]) done_st <= 1'b0; if (pwdata[5]) cmd_err <= 1'b0; end
                default: ;
            endcase
        end

    always @* begin
        case (paddr[7:2])
            6'h0: prdata = {31'd0, irq_en};
            6'h1: prdata = {16'd0, prescale};
            6'h2: prdata = {24'd0, txdata};
            6'h3: prdata = {24'd0, rx_data};
            6'h5: prdata = {22'd0, sda_q[1], scl_q[1], timeout, cmd_ready, cmd_err, bus_busy, done_st, arb_lost, rx_nack, busy};
            default: prdata = 32'd0;
        endcase
    end

    assign irq = irq_en & (done_st | cmd_err);

    i2c_master #(.TIMEOUT_CLKS(TIMEOUT_CLKS)) u_master (
        .clk(pclk), .rst_n(presetn), .prescale(prescale),
        .cmd_valid(cmd_valid), .cmd_start(cmd[0]), .cmd_stop(cmd[1]), .cmd_read(cmd[2]),
        .cmd_write(cmd[3]), .cmd_nack(cmd[4]), .tx_data(txdata),
        .rx_data(rx_data), .rx_nack(rx_nack), .done(done), .arb_lost(arb_lost),
        .busy(busy), .bus_busy(bus_busy), .timeout(timeout),
        .scl_i(scl_i), .sda_i(sda_i), .scl_oe(scl_oe), .sda_oe(sda_oe));
endmodule
