foreach s [list tb_i2c_robust.test_id tb_i2c_robust.presetn tb_i2c_robust.scl tb_i2c_robust.sda tb_i2c_robust.dut.sda_oe tb_i2c_robust.u_s.sda_oe tb_i2c_robust.s_addressed tb_i2c_robust.dut.busy tb_i2c_robust.dut.u_master.st tb_i2c_robust.dut.u_master.bitn tb_i2c_robust.mon.stops tb_i2c_robust.mon.starts] { gtkwave::addSignalsFromList [list $s] }
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 420000000 500000000
gtkwave::setFromEntry 420000ns
gtkwave::setToEntry 500000ns
gtkwave::setMarker 428510000
