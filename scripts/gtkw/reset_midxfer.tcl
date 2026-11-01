foreach s [list tb_i2c_robust.test_id tb_i2c_robust.presetn tb_i2c_robust.scl tb_i2c_robust.sda tb_i2c_robust.dut.scl_oe tb_i2c_robust.dut.sda_oe tb_i2c_robust.u_s.sda_oe tb_i2c_robust.u_s.st tb_i2c_robust.s_addressed tb_i2c_robust.dut.u_master.st tb_i2c_robust.dut.busy tb_i2c_robust.mon_en] { gtkwave::addSignalsFromList [list $s] }
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 395000000 440000000
gtkwave::setFromEntry 395000ns
gtkwave::setToEntry 440000ns
gtkwave::setMarker 424250000
