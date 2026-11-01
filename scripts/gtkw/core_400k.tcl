set sigs [list tb_i2c_core.test_id tb_i2c_core.scl tb_i2c_core.sda tb_i2c_core.u_m.prescale tb_i2c_core.u_m.st tb_i2c_core.u_m.bitn tb_i2c_core.u_m.tx_data tb_i2c_core.u_s7.sh]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 3411030000 3500000000
gtkwave::setFromEntry 3411030ns
gtkwave::setToEntry 3500000ns
gtkwave::setMarker 3420000000
