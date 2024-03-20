# -*- tcl -*-

# Clock constraints

create_clock -name "clk" -period 62.5ns [get_ports {clk}]
derive_clock_uncertainty
derive_pll_clocks
