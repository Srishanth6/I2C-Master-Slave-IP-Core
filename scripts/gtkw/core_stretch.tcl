set sigs [list tb_i2c_core.test_id tb_i2c_core.scl tb_i2c_core.sda tb_i2c_core.u_m.scl_oe tb_i2c_core.u_s7.scl_oe tb_i2c_core.u_s7.scnt tb_i2c_core.u_m.st tb_i2c_core.u_m.cnt tb_i2c_core.u_m.tx_data tb_i2c_core.u_s7.st]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 2586990000 2900000000
gtkwave::setFromEntry 2586990ns
gtkwave::setToEntry 2900000ns
gtkwave::setMarker 2700000000
