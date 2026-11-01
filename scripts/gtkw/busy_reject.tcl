set sigs [list tb_i2c_robust.test_id tb_i2c_robust.pclk tb_i2c_robust.psel tb_i2c_robust.pwrite tb_i2c_robust.paddr tb_i2c_robust.pwdata tb_i2c_robust.dut.busy tb_i2c_robust.dut.cmd_ready tb_i2c_robust.dut.cmd_err tb_i2c_robust.irq tb_i2c_robust.scl tb_i2c_robust.sda tb_i2c_robust.dut.u_master.st]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 0 60000000
gtkwave::setFromEntry 0ns
gtkwave::setToEntry 60000ns
gtkwave::setMarker 610000
