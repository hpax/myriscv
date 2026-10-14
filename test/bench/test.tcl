# Default Questa waveform setup for the generic test bench.
add log -r *
add wave /cpu/rst_n
add wave /cpu/clk
add wave /cpu/mem_*
add wave /cpu/io_*
add wave -radix ascii /cpu/io_wdata[31:24]
add wave /cpu/fetch/ibus_a
add wave /cpu/fetch/d_valid_i
add wave /cpu/fetch/d_insn
add wave /cpu/pipe_ctl/d_op
add wave /cpu/pipe_ctl/e_valid_i
add wave /cpu/pipe_ctl/e_op
add wave /cpu/backend/e_src1
add wave /cpu/backend/e_src2
add wave /cpu/backend/e_addr
add wave /cpu/backend/e_dout
add wave /cpu/pipe_ctl/m_valid_i
add wave /cpu/pipe_ctl/m_op
add wave /cpu/pipe_ctl/m_busy
add wave /cpu/backend/m_dout
add wave /cpu/backend/m_kill
add wave /cpu/dbus_*
add wave /cpu/backend/mult/*
add wave /cpu/backend/mult/mult/*
add wave /cpu/backend/ldst/*
wave zoom range 15ns 30ns
view structure
view signals
run 30 us
