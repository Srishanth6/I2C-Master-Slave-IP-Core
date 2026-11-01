set sigs [list tb_i2c_apb.test_id tb_i2c_apb.pclk tb_i2c_apb.psel tb_i2c_apb.penable tb_i2c_apb.pwrite tb_i2c_apb.paddr tb_i2c_apb.pwdata tb_i2c_apb.prdata tb_i2c_apb.irq tb_i2c_apb.scl tb_i2c_apb.sda tb_i2c_apb.dut.u_master.st tb_i2c_apb.dut.u_master.tx_data tb_i2c_apb.u_s.scl_oe tb_i2c_apb.u_s.st]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 400000 101000000
gtkwave::setFromEntry 400ns
gtkwave::setToEntry 101000ns
gtkwave::setMarker 670000
