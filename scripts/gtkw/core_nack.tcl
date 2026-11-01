set sigs [list tb_i2c_core.test_id tb_i2c_core.scl tb_i2c_core.sda tb_i2c_core.u_m.sda_oe tb_i2c_core.u_s7.sda_oe tb_i2c_core.u_m.st tb_i2c_core.u_m.bitn tb_i2c_core.u_m.tx_data tb_i2c_core.u_m.rx_nack tb_i2c_core.u_m.done tb_i2c_core.u_s7.st tb_i2c_core.u_m.bus_busy]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 1258170000 1380000000
gtkwave::setFromEntry 1258170ns
gtkwave::setToEntry 1380000ns
gtkwave::setMarker 1265730000
