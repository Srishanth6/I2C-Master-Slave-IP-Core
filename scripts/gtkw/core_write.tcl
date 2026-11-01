set sigs [list tb_i2c_core.test_id tb_i2c_core.clk tb_i2c_core.scl tb_i2c_core.sda tb_i2c_core.u_m.scl_oe tb_i2c_core.u_m.sda_oe tb_i2c_core.u_s7.sda_oe tb_i2c_core.u_m.st tb_i2c_core.u_m.bitn tb_i2c_core.u_m.tx_data tb_i2c_core.u_m.rx_nack tb_i2c_core.u_m.bus_busy tb_i2c_core.u_s7.st tb_i2c_core.u_s7.sh tb_i2c_core.u_s7.addressed tb_i2c_core.u_s7.wr_strobe]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 190000 200000000
gtkwave::setFromEntry 190ns
gtkwave::setToEntry 200000ns
gtkwave::setMarker 10000000
