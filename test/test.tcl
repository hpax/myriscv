add log -r *
add wave *
add wave /cpu/fetch/*
add wave -radix ascii io_wdata[31:24]
add wave /cpu/pipe_ctl/*
add wave /cpu/backend/*
wave zoom range 15ns 30ns
view structure
view signals
run 1 us
