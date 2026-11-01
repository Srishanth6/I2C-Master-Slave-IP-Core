set sigs [list tb_i2c_core.test_id tb_i2c_core.scl tb_i2c_core.sda tb_i2c_core.u_m.tx_data tb_i2c_core.u_m.rx_nack tb_i2c_core.u_s10.st tb_i2c_core.u_s10.sh tb_i2c_core.u_s10.matched10 tb_i2c_core.u_s10.addressed tb_i2c_core.u_s10.wr_strobe tb_i2c_core.u_s7.st]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 1381390000 1590000000
gtkwave::setFromEntry 1381390ns
gtkwave::setToEntry 1590000ns
gtkwave::setMarker 1388950000
