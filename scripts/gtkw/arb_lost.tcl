set sigs [list tb_i2c_arb.test_id tb_i2c_arb.scl tb_i2c_arb.sda tb_i2c_arb.m_a.sda_oe tb_i2c_arb.m_b.sda_oe tb_i2c_arb.m_a.scl_oe tb_i2c_arb.m_b.scl_oe tb_i2c_arb.m_a.tx_data tb_i2c_arb.m_b.tx_data tb_i2c_arb.m_a.arb_lost tb_i2c_arb.m_b.arb_lost tb_i2c_arb.m_a.st tb_i2c_arb.m_b.st tb_i2c_arb.m_a.bus_busy tb_i2c_arb.s48.addressed tb_i2c_arb.s50.addressed]
gtkwave::addSignalsFromList $sigs
gtkwave::/Edit/UnHighlight_All
gtkwave::setZoomRangeTimes 190000 30000000
gtkwave::setFromEntry 190ns
gtkwave::setToEntry 30000ns
gtkwave::setMarker 10330000
