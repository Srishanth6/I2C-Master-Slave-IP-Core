// i2c_apb.v - APB (AMBA 3) register wrapper around i2c_master
// Author: B. Srishanth Reddy
// 0x00 CTRL     [0] irq_en
// 0x04 PRESCALE [15:0]           (reset 124 = 100 kHz at 50 MHz)
// 0x08 TXDATA   [7:0]
// 0x0C RXDATA   [7:0]  RO
// 0x10 CMD      [0] START [1] STOP [2] READ [3] WRITE [4] NACK   (write starts command, WO)
// 0x14 STATUS   [0] busy [1] rx_nack [2] arb_lost [3] done(W1C) [4] bus_busy   RO except done
`timescale 1ns/1ps
module i2c_apb (
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
    reg        done_st;
    wire [7:0] rx_data;
    wire       rx_nack, done, arb_lost, busy, bus_busy;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    wire wr = psel & penable & pwrite;

    always @(posedge pclk or negedge presetn)
        if (!presetn) begin
            irq_en <= 0; prescale <= 16'd124; txdata <= 0; cmd_valid <= 0; cmd <= 0; done_st <= 0;
        end else begin
            cmd_valid <= 1'b0;
            if (done) done_st <= 1'b1;
            if (wr) case (paddr[7:2])
                6'h0: irq_en   <= pwdata[0];
                6'h1: prescale <= pwdata[15:0];
                6'h2: txdata   <= pwdata[7:0];
                6'h4: begin cmd <= pwdata[4:0]; cmd_valid <= 1'b1; done_st <= 1'b0; end
                6'h5: if (pwdata[3]) done_st <= 1'b0;
                default: ;
            endcase
        end

    always @* begin
        case (paddr[7:2])
            6'h0: prdata = {31'd0, irq_en};
            6'h1: prdata = {16'd0, prescale};
            6'h2: prdata = {24'd0, txdata};
            6'h3: prdata = {24'd0, rx_data};
            6'h5: prdata = {27'd0, bus_busy, done_st, arb_lost, rx_nack, busy};
            default: prdata = 32'd0;
        endcase
    end

    assign irq = irq_en & done_st;

    i2c_master u_master (
        .clk(pclk), .rst_n(presetn), .prescale(prescale),
        .cmd_valid(cmd_valid), .cmd_start(cmd[0]), .cmd_stop(cmd[1]), .cmd_read(cmd[2]),
        .cmd_write(cmd[3]), .cmd_nack(cmd[4]), .tx_data(txdata),
        .rx_data(rx_data), .rx_nack(rx_nack), .done(done), .arb_lost(arb_lost),
        .busy(busy), .bus_busy(bus_busy),
        .scl_i(scl_i), .sda_i(sda_i), .scl_oe(scl_oe), .sda_oe(sda_oe));
endmodule
