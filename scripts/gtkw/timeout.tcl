set sigs [list tb_i2c_robust.test_id tb_i2c_robust.scl tb_i2c_robust.sda tb_i2c_robust.dut.scl_oe tb_i2c_robust.u_s.scl_oe tb_i2c_robust.u_s.scnt tb_i2c_robust.dut.u_master.wcnt tb_i2c_robust.dut.timeout tb_i2c_robust.dut.busy tb_i2c_robust.dut.u_master.st tb_i2c_robust.mon_en]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 540000000 1250000000
gtkwave::setFromEntry 540000ns
gtkwave::setToEntry 1250000ns
gtkwave::setMarker 772970000
