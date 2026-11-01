# I2C Master/Slave IP Core

An I2C master and slave IP core in synthesizable Verilog, written from scratch, with an AMBA APB
register interface and self-checking testbenches. The master supports START, repeated START and STOP,
7- and 10-bit addressing, reads and writes with ACK/NACK, a programmable SCL prescaler (100 kHz and
400 kHz) and multi-master arbitration. The slave has a programmable 7- or 10-bit address, a 16 x 8
register file and clock stretching. All results below are copied from the logs in [`logs/`](logs),
produced on Windows with Icarus Verilog 12.

**Author:** B. Srishanth Reddy

📄 **Full report:** [report/I2C_IP_Core_Report.pdf](report/I2C_IP_Core_Report.pdf)

## Features

**Master (`rtl/i2c_master.v`)**
- Byte-level command interface: one command = optional START (also repeated START), one WRITE or READ byte, optional STOP
- 7-bit and 10-bit addressing (10-bit header `11110 A9 A8 R/W` + low address byte)
- ACK/NACK: reports slave NACK (`rx_nack`), sends ACK or NACK after each read byte (`cmd_nack`)
- SCL = f_clk / (4 x (PRESCALE + 1)); 50 MHz: PRESCALE 124 = 100 kHz, 30 = 403 kHz
- Waits for SCL to really go high before timing the high phase, so it supports slave clock stretching and multi-master clock synchronisation
- Arbitration-loss detection: if it releases SDA but reads 0 while SCL is high, it releases the bus at once and sets `arb_lost`
- Bus-busy detection (START/STOP monitor) and 2-flop synchronisers on SCL/SDA

**Slave (`rtl/i2c_slave.v`)**
- Programmable 7-bit or 10-bit own address (`addr10_en`)
- 16 x 8 register file (parameter `NREG`) with an auto-incrementing register pointer
- Write: `S ADDR+W PTR D0 D1 .. P`; read: `S ADDR+W PTR Sr ADDR+R D0 .. Dn(NACK) P`
- Clock stretching: holds SCL low for `stretch_cycles` clocks after every ACK bit
- START / repeated START / STOP detection from any state

**APB wrapper (`rtl/i2c_apb.v`)**: AMBA 3 APB slave, zero wait states, `irq` on command done.

**Open-drain bus model**: every driver only pulls low (`assign scl = oe ? 1'b0 : 1'bz;`), and the bus wires are `tri1` (pull-ups), so the bus is a real wired-AND.

## Architecture

![Block diagram](docs/figs/block.png)

Each bit (and each START/STOP) is split into 4 phases of PRESCALE+1 clocks:

| Phase | SCL | SDA |
|---|---|---|
| ph0 | low | master sets the data bit (or releases it to read) |
| ph1 | released; the timer waits until SCL is really high (stretching / clock sync) | sampled at the end of ph1; arbitration is checked here |
| ph2 | high | held (START: SDA falls here, STOP: SDA rises here) |
| ph3 | low | held |

### Master FSM
![Master FSM](docs/figs/fsm_master.png)

### Slave FSM
![Slave FSM](docs/figs/fsm_slave.png)

## Register map (`i2c_apb`)

| Offset | Name | Access | Bits | Description |
|---|---|---|---|---|
| 0x00 | CTRL | RW | [0] `irq_en` | interrupt enable |
| 0x04 | PRESCALE | RW | [15:0] | SCL = PCLK / (4 x (PRESCALE+1)), reset 124 (100 kHz at 50 MHz) |
| 0x08 | TXDATA | RW | [7:0] | byte to send (address byte or data) |
| 0x0C | RXDATA | RO | [7:0] | last byte read |
| 0x10 | CMD | WO | [0] START [1] STOP [2] READ [3] WRITE [4] NACK | writing starts the command |
| 0x14 | STATUS | RO / W1C | [0] busy [1] rx_nack [2] arb_lost [3] done (W1C) [4] bus_busy | `irq = irq_en & done` |

Example software sequence, write 0xDE to register 0 of slave 0x50:
```
TXDATA=0xA0; CMD=START|WRITE;  poll STATUS.done, check STATUS.rx_nack==0
TXDATA=0x00; CMD=WRITE;        poll
TXDATA=0xDE; CMD=WRITE|STOP;   poll
```

## Interface

| Module | Port | Dir | Width | Description |
|---|---|---|---|---|
| master | `prescale` | in | 16 | SCL prescaler |
| master | `cmd_valid`, `cmd_start`, `cmd_stop`, `cmd_read`, `cmd_write`, `cmd_nack` | in | 1 | command strobe and fields |
| master | `tx_data` / `rx_data` | in / out | 8 | byte to send / byte received |
| master | `done`, `rx_nack`, `arb_lost`, `busy`, `bus_busy` | out | 1 | status |
| master, slave | `scl_i`, `sda_i` / `scl_oe`, `sda_oe` | in / out | 1 | open-drain pads (`oe`=1 pulls low) |
| slave | `own_addr`, `addr10_en` | in | 10, 1 | own address and mode |
| slave | `stretch_en`, `stretch_cycles` | in | 1, 16 | clock stretching control |
| slave | `addressed`, `wr_strobe` | out | 1 | selected flag, register-write pulse |

## Verification

Three self-checking testbenches. Each one prints PASS/FAIL per test and a summary line, and the
script fails if any check fails. The bus is the real open-drain model with pull-ups.

| Testbench | Test | Result |
|---|---|---|
| `tb_i2c_core` | 1. 7-bit write, 4 bytes, 100 kHz (SCL measured 99.40 kHz) | **PASS** |
| | 2. 7-bit read with repeated START, ACK x3 + NACK on last byte | **PASS** |
| | 3. Address NACK (no slave at 0x58) | **PASS** |
| | 4. 10-bit write to 0x2A5 (7-bit slave stays untouched) | **PASS** |
| | 5. 10-bit read with repeated START (`11110_10_1`) | **PASS** |
| | 6. 10-bit NACK on wrong low address byte | **PASS** |
| | 7. Clock stretching: slave holds SCL 600 clocks; longest SCL low 12.06 µs vs 5 µs normal, data correct | **PASS** |
| | 8. 400 kHz fast mode (PRESCALE=30, SCL measured 393.70 kHz), write + 3-byte read | **PASS** |
| `tb_i2c_arb` | 1. Two masters START together; A (0xA0) loses on address bit to B (0x90); B finishes, slave 0x50 untouched | **PASS** |
| | 2. Losing master retries after STOP and succeeds | **PASS** |
| | 3. Same address, arbitration lost on data bit 1 (0x33 vs 0x31); winner's byte written | **PASS** |
| `tb_i2c_apb` | 1. APB register reset values, read/write, PREADY/PSLVERR | **PASS** |
| | 2. APB-driven write at 400 kHz with slave stretching, irq and W1C | **PASS** |
| | 3. APB-driven read with repeated START, RXDATA | **PASS** |
| | 4. NACK reported in STATUS | **PASS** |
| Negative test | `+define+INJECT_BUG` corrupts slave register writes; the core TB must fail | **Bug caught** |

**Summary: 15/15 tests PASS, 91 checks, 0 errors** (`logs/summary.log`).

## Waveforms (real GTKWave screenshots)

These are real screenshots of the laptop screen with GTKWave showing the VCDs from the runs above,
captured by `scripts/gtkwave_shots.ps1`. Each view has a GTKWave Tcl script in `scripts/gtkw/`
(signals, zoom and marker), so it can be reopened with
`gtkwave -S scripts\gtkw\<view>.tcl waves\<tb>.vcd`.

| View | Description |
|---|---|
| ![core_write](docs/screenshots/gtkwave_core_write.png) | T1 – 7-bit write of 2 bytes at 100 kHz (START, address 0xA0, ACK, data, STOP) |
| ![core_rstart](docs/screenshots/gtkwave_core_rstart.png) | Repeated-START random read |
| ![core_nack](docs/screenshots/gtkwave_core_nack.png) | Address NACK from a non-existent slave |
| ![core_10bit](docs/screenshots/gtkwave_core_10bit.png) | 10-bit address write and read |
| ![core_stretch](docs/screenshots/gtkwave_core_stretch.png) | Slave clock stretching (SCL low extended to 12.06 us) |
| ![core_400k](docs/screenshots/gtkwave_core_400k.png) | Fast-mode transfer (prescale 30, 393.7 kHz) |
| ![arb_lost](docs/screenshots/gtkwave_arb_lost.png) | Multi-master arbitration: master A loses at 9090 ns, B completes |
| ![apb_write](docs/screenshots/gtkwave_apb_write.png) | APB register-driven write sequence |


## Synthesis (Yosys 0.52, generic gates)

| Top | Cells | Flip-flops |
|---|---|---|
| `i2c_master` | 399 | 57 |
| `i2c_slave` (16 x 8 register file) | 1293 | 186 |
| `i2c_apb` (wrapper + master) | 544 | 89 |

`syn/synth.ys`, logs in `logs/synth_*.log`. These are generic Yosys cells (`synth -flatten`), not a real cell library, so there is no area or timing number. Yosys is not installed on the laptop, so synthesis was run separately with Yosys 0.52 on Linux.

## How to run (Windows, Icarus Verilog 12 in `C:\iverilog`)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1       # all testbenches + negative test -> logs\
powershell -ExecutionPolicy Bypass -File scripts\gtkwave_shots.ps1 # GTKWave screenshots -> docs\screenshots\
C:\iverilog\gtkwave\bin\gtkwave.exe -S scripts\gtkw\arb_lost.tcl waves\tb_i2c_arb.vcd
yosys -s syn/synth.ys                                               # optional, synthesis
```

Linux/macOS: `iverilog -g2012 -o sim tb/tb_i2c_core.v rtl/*.v && vvp sim`.

## Folder structure

```
rtl/      i2c_master.v, i2c_slave.v, i2c_apb.v
tb/       tb_i2c_core.v, tb_i2c_arb.v, tb_i2c_apb.v (self-checking)
scripts/  run_all.ps1, gtkwave_shots.ps1, gtkw/*.tcl (GTKWave views)
logs/     simulation logs, summary.log, synth_*.log
waves/    VCDs (regenerated by run_all.ps1, not committed)
docs/     figs/ (block diagram, FSMs), screenshots/ (GTKWave)
syn/      Yosys script
report/   report (docx, pdf)
```

## Limitations

- The master is byte-level: software (or the APB sequence) issues the address and data bytes; 10-bit addressing is two address bytes sent by software.
- No FIFO and no DMA; one byte per command.
- No glitch (spike) filter on SCL/SDA, only 2-flop synchronisers.
- Timing is set by one prescaler (50 % duty-cycle SCL); separate tLOW/tHIGH/tSU/tHD registers are not provided.
- Arbitration is checked on data/address bits, not during the START condition itself.
- Slave register file is 16 x 8 and clocked by the system clock (needs f_clk well above 8x SCL).
- Verification is simulation only (Icarus Verilog): no formal proofs, gate-level simulation or FPGA test.
