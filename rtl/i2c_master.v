// i2c_master.v - byte-level I2C master with open-drain outputs
// Author: B. Srishanth Reddy
// SCL frequency = f_clk / (4 * (prescale + 1)).  e.g. 50 MHz: 124 -> 100 kHz, 30 -> 403 kHz
// One command = [START] then [WRITE or READ byte] then [STOP]. START also works as repeated start.
// scl_oe / sda_oe = 1 pulls the line low; 0 releases it (pull-up makes it high).
`timescale 1ns/1ps
module i2c_master (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] prescale,
    // command interface
    input  wire        cmd_valid,
    input  wire        cmd_start,
    input  wire        cmd_stop,
    input  wire        cmd_read,
    input  wire        cmd_write,
    input  wire        cmd_nack,     // for reads: 1 = send NACK after the byte (last byte)
    input  wire [7:0]  tx_data,
    output reg  [7:0]  rx_data,
    output reg         rx_nack,      // for writes: 1 = slave answered NACK
    output reg         done,         // 1-clock pulse when the command finishes
    output reg         arb_lost,     // set when arbitration is lost, cleared by next command
    output wire        busy,
    output reg         bus_busy,     // START seen on bus and no STOP yet
    // open-drain bus
    input  wire        scl_i,
    input  wire        sda_i,
    output reg         scl_oe,
    output reg         sda_oe
);
    localparam S_IDLE = 2'd0, S_START = 2'd1, S_BIT = 2'd2, S_STOP = 2'd3;

    reg [1:0] scl_sync, sda_sync;
    reg       scl_d, sda_d;
    wire      scl_s = scl_sync[1];
    wire      sda_s = sda_sync[1];

    reg [1:0]  st, ph;
    reg [15:0] cnt;
    reg [3:0]  bitn;
    reg [7:0]  sh;
    reg        f_stop, f_rd, f_wr, f_nack, own;

    // 2-flop synchronisers + edge history
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin scl_sync <= 2'b11; sda_sync <= 2'b11; scl_d <= 1'b1; sda_d <= 1'b1; end
        else begin
            scl_sync <= {scl_sync[0], scl_i}; sda_sync <= {sda_sync[0], sda_i};
            scl_d <= scl_s; sda_d <= sda_s;
        end

    wire start_seen = scl_s & scl_d & sda_d & ~sda_s;
    wire stop_seen  = scl_s & scl_d & ~sda_d & sda_s;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) bus_busy <= 1'b0;
        else if (start_seen) bus_busy <= 1'b1;
        else if (stop_seen)  bus_busy <= 1'b0;

    assign busy = (st != S_IDLE);

    // phase timer: phase 1 (SCL released) only counts once SCL is really high
    // -> slave clock stretching and multi-master clock synchronisation
    wire ph_end = (cnt == prescale);

    // the bit currently being driven on SDA (1 = released)
    wire tx_bit = (bitn == 4'd8) ? (f_rd ? f_nack : 1'b1)
                                 : (f_wr ? sh[7]  : 1'b1);
    wire driving_data = f_wr && (bitn != 4'd8);   // arbitration only on our data bits

    // next value of the open-drain outputs
    reg scl_n, sda_n;
    always @* begin
        scl_n = scl_oe; sda_n = sda_oe;
        case (st)
            S_IDLE:  begin scl_n = own; sda_n = 1'b0; end
            S_START: case (ph)
                2'd0: begin scl_n = scl_oe; sda_n = 1'b0; end
                2'd1: begin scl_n = 1'b0;   sda_n = 1'b0; end
                2'd2: begin scl_n = 1'b0;   sda_n = 1'b1; end   // SDA falls while SCL high = START
                2'd3: begin scl_n = 1'b1;   sda_n = 1'b1; end
            endcase
            S_BIT: begin
                sda_n = ~tx_bit;
                scl_n = (ph == 2'd0) || (ph == 2'd3);
            end
            S_STOP: case (ph)
                2'd0: begin scl_n = 1'b1; sda_n = 1'b1; end
                2'd1: begin scl_n = 1'b0; sda_n = 1'b1; end
                default: begin scl_n = 1'b0; sda_n = 1'b0; end // SDA rises while SCL high = STOP
            endcase
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; ph <= 2'd0; cnt <= 16'd0; bitn <= 4'd0; sh <= 8'd0;
            f_stop <= 1'b0; f_rd <= 1'b0; f_wr <= 1'b0; f_nack <= 1'b0; own <= 1'b0;
            rx_data <= 8'd0; rx_nack <= 1'b0; done <= 1'b0; arb_lost <= 1'b0;
            scl_oe <= 1'b0; sda_oe <= 1'b0;
        end else begin
            done   <= 1'b0;
            scl_oe <= scl_n;
            sda_oe <= sda_n;
            if (st == S_IDLE) begin
                cnt <= 16'd0; ph <= 2'd0;
                if (cmd_valid) begin
                    f_stop <= cmd_stop; f_rd <= cmd_read; f_wr <= cmd_write & ~cmd_read;
                    f_nack <= cmd_nack; sh <= tx_data; bitn <= 4'd0; arb_lost <= 1'b0;
                    if (cmd_start)                  st <= S_START;
                    else if (cmd_write | cmd_read)  st <= S_BIT;
                    else if (cmd_stop)              st <= S_STOP;
                    else                            done <= 1'b1;
                end
            end else begin
                if (ph == 2'd1 && !scl_s)      cnt <= 16'd0;          // wait for SCL high
                else if (ph_end)               cnt <= 16'd0;
                else                           cnt <= cnt + 16'd1;

                if (ph_end && !(ph == 2'd1 && !scl_s)) begin
                    ph <= ph + 2'd1;
                    case (st)
                        S_START: if (ph == 2'd3) begin
                            own <= 1'b1;
                            if (f_wr | f_rd) begin st <= S_BIT; bitn <= 4'd0; end
                            else if (f_stop) st <= S_STOP;
                            else begin st <= S_IDLE; done <= 1'b1; end
                        end
                        S_BIT: begin
                            if (ph == 2'd1) begin
                                // SCL is high: sample SDA
                                if (driving_data && tx_bit && !sda_s) begin
                                    arb_lost <= 1'b1; own <= 1'b0; done <= 1'b1;
                                    st <= S_IDLE;                       // release the bus at once
                                end else if (bitn == 4'd8) begin
                                    if (f_rd) rx_data <= sh; else rx_nack <= sda_s;
                                end else if (f_rd) sh <= {sh[6:0], sda_s};
                            end
                            if (ph == 2'd3) begin
                                if (f_wr) sh <= {sh[6:0], 1'b0};
                                if (bitn == 4'd8) begin
                                    if (f_stop) st <= S_STOP;
                                    else begin st <= S_IDLE; done <= 1'b1; end
                                end else bitn <= bitn + 4'd1;
                            end
                        end
                        S_STOP: if (ph == 2'd3) begin
                            own <= 1'b0; st <= S_IDLE; done <= 1'b1;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
