set sigs [list tb_i2c_timing.test_id tb_i2c_timing.prescale tb_i2c_timing.mode tb_i2c_timing.clk tb_i2c_timing.scl tb_i2c_timing.sda tb_i2c_timing.u_m.st tb_i2c_timing.u_m.ph tb_i2c_timing.u_m.cnt tb_i2c_timing.mon.nbit tb_i2c_timing.mon.errors]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 895770000 935000000
gtkwave::setFromEntry 895770ns
gtkwave::setToEntry 935000ns
gtkwave::setMarker 896000000
