// i2c_slave.v - I2C slave with register file, 7/10-bit address and clock stretching
// Author: B. Srishanth Reddy
// Protocol: write  S ADDR+W PTR D0 D1 .. P          (PTR auto-increments)
//           read   S ADDR+W PTR Sr ADDR+R D0 .. Dn(NACK) P
//           10-bit S 11110,A9,A8,W  A[7:0]  PTR ...  Sr 11110,A9,A8,R  D0 ..
`timescale 1ns/1ps
module i2c_slave #(
    parameter NREG = 16                 // register file depth (power of 2)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  own_addr,        // 7-bit address in [6:0] or 10-bit address
    input  wire        addr10_en,
    input  wire        stretch_en,      // hold SCL low after every ACK bit
    input  wire [15:0] stretch_cycles,
    input  wire        scl_i,
    input  wire        sda_i,
    output reg         scl_oe,
    output reg         sda_oe,
    output reg         addressed,       // high while this slave is selected
    output reg         wr_strobe,       // 1-clock pulse per register written
    // debug/back-door read port (used by testbenches)
    input  wire [$clog2(NREG)-1:0] dbg_addr,
    output wire [7:0]  dbg_data
);
    localparam AW = $clog2(NREG);
    localparam IDLE=3'd0, ADDR=3'd1, ADDR2=3'd2, PTR=3'd3, WDATA=3'd4, RDATA=3'd5, WAITP=3'd6;

    reg [7:0] mem [0:NREG-1];
    assign dbg_data = mem[dbg_addr];

    reg [1:0] scl_sync, sda_sync;
    reg       scl_d, sda_d;
    wire scl_s = scl_sync[1], sda_s = sda_sync[1];
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin scl_sync <= 2'b11; sda_sync <= 2'b11; scl_d <= 1'b1; sda_d <= 1'b1; end
        else begin
            scl_sync <= {scl_sync[0], scl_i}; sda_sync <= {sda_sync[0], sda_i};
            scl_d <= scl_s; sda_d <= sda_s;
        end
    wire scl_rise = scl_s & ~scl_d;
    wire scl_fall = ~scl_s & scl_d;
    wire start_c  = scl_s & scl_d & sda_d & ~sda_s;
    wire stop_c   = scl_s & scl_d & ~sda_d & sda_s;

    reg [2:0]  st, nxt;
    reg [3:0]  bitcnt;
    reg [7:0]  sh, rsh;
    reg        ack_ph, mack, matched10;
    reg [AW-1:0] ptr;
    reg [15:0] scnt;
    integer i;

    wire hdr10   = (sh[7:3] == 5'b11110) && (sh[2:1] == own_addr[9:8]);
    wire match7  = !addr10_en && (sh[7:1] == own_addr[6:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE; nxt <= IDLE; bitcnt <= 0; sh <= 0; rsh <= 0; ack_ph <= 0; mack <= 0;
            matched10 <= 0; ptr <= 0; scnt <= 0; scl_oe <= 0; sda_oe <= 0; addressed <= 0;
            wr_strobe <= 0;
            for (i = 0; i < NREG; i = i + 1) mem[i] <= 8'h00;
        end else begin
            wr_strobe <= 1'b0;
            // clock stretching counter
            if (scnt != 0) begin
                scnt <= scnt - 16'd1;
                if (scnt == 16'd1) scl_oe <= 1'b0;
            end
            if (stop_c) begin
                st <= IDLE; sda_oe <= 0; ack_ph <= 0; matched10 <= 0; addressed <= 0;
            end else if (start_c) begin
                st <= ADDR; bitcnt <= 0; sda_oe <= 0; ack_ph <= 0; addressed <= 0;
            end else if (scl_rise) begin
                if (!ack_ph) begin
                    if (st == ADDR || st == ADDR2 || st == PTR || st == WDATA) begin
                        sh <= {sh[6:0], sda_s}; bitcnt <= bitcnt + 4'd1;
                    end else if (st == RDATA) bitcnt <= bitcnt + 4'd1;
                end else if (st == RDATA) mack <= sda_s;      // master ACK(0)/NACK(1)
            end else if (scl_fall) begin
                if (!ack_ph) begin
                    if (bitcnt == 4'd8) begin
                        case (st)
                            ADDR: begin
                                if (addr10_en && hdr10 && !sh[0]) begin
                                    sda_oe <= 1; ack_ph <= 1; nxt <= ADDR2;
                                end else if (addr10_en && hdr10 && sh[0] && matched10) begin
                                    sda_oe <= 1; ack_ph <= 1; nxt <= RDATA; addressed <= 1;
                                end else if (match7) begin
                                    sda_oe <= 1; ack_ph <= 1; nxt <= sh[0] ? RDATA : PTR; addressed <= 1;
                                end else st <= WAITP;                  // not for us: no ACK
                            end
                            ADDR2: if (sh == own_addr[7:0]) begin
                                    sda_oe <= 1; ack_ph <= 1; nxt <= PTR; matched10 <= 1; addressed <= 1;
                                end else st <= WAITP;
                            PTR:   begin ptr <= sh[AW-1:0]; sda_oe <= 1; ack_ph <= 1; nxt <= WDATA; end
                            WDATA: begin
`ifdef INJECT_BUG
                                mem[ptr] <= sh ^ 8'h01;           // deliberate bug for negative test
`else
                                mem[ptr] <= sh;
`endif
                                ptr <= ptr + 1'b1; wr_strobe <= 1'b1;
                                sda_oe <= 1; ack_ph <= 1; nxt <= WDATA;
                            end
                            RDATA: begin sda_oe <= 0; ack_ph <= 1; nxt <= RDATA; end
                            default: ;
                        endcase
                    end else if (st == RDATA) begin
                        sda_oe <= ~rsh[6]; rsh <= {rsh[6:0], 1'b0};
                    end
                end else begin
                    // falling edge that ends the ACK bit
                    ack_ph <= 0; bitcnt <= 0; sda_oe <= 0;
                    if (nxt == RDATA && st == RDATA && mack) st <= WAITP;   // master NACK: done
                    else begin
                        st <= nxt;
                        if (nxt == RDATA) begin
                            rsh <= mem[ptr]; sda_oe <= ~mem[ptr][7]; ptr <= ptr + 1'b1;
                        end
                        if (stretch_en && stretch_cycles != 0) begin
                            scl_oe <= 1'b1; scnt <= stretch_cycles;
                        end
                    end
                end
            end
        end
    end
endmodule
