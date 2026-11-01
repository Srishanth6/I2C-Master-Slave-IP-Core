set sigs [list tb_i2c_core.test_id tb_i2c_core.scl tb_i2c_core.sda tb_i2c_core.u_m.sda_oe tb_i2c_core.u_s7.sda_oe tb_i2c_core.u_m.st tb_i2c_core.u_m.tx_data tb_i2c_core.u_m.rx_data tb_i2c_core.u_m.done tb_i2c_core.u_s7.st tb_i2c_core.u_s7.ptr tb_i2c_core.u_s7.rsh]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 700000000 960000000
gtkwave::setFromEntry 700000ns
gtkwave::setToEntry 960000ns
gtkwave::setMarker 830000000
