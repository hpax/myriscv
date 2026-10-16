# Default Questa waveform setup for the generic test bench.
add log -r *
add wave /test/cpu/rst_n
add wave /test/cpu/clk
add wave /test/cpu/mem_*
add wave /test/cpu/io_*
add wave -radix ascii /test/cpu/io_wdata[31:24]
add wave /test/cpu/fetch/ibus_a
add wave /test/cpu/fetch/d_valid_i
add wave /test/cpu/fetch/d_insn
add wave /test/cpu/pipe_ctl/d_op
add wave /test/cpu/pipe_ctl/e_valid_i
add wave /test/cpu/pipe_ctl/e_op
add wave /test/cpu/backend/e_pc
add wave /test/cpu/backend/e_next_pc
add wave /test/cpu/backend/e_restartpc
add wave /test/cpu/backend/e_acceptable
add wave /test/cpu/backend/e_accept
add wave /test/cpu/backend/e_mispredict
add wave /test/cpu/backend/e_restart
add wave /test/cpu/backend/e_kill
add wave /test/cpu/backend/e_src1
add wave /test/cpu/backend/e_src2
add wave /test/cpu/backend/e_addr
add wave /test/cpu/backend/e_dout
add wave /test/cpu/pipe_ctl/m_valid_i
add wave /test/cpu/pipe_ctl/m_op
add wave /test/cpu/pipe_ctl/m_busy
add wave /test/cpu/backend/m_dout
add wave /test/cpu/backend/m_kill
add wave /test/cpu/dbus_*
add wave /test/cpu/backend/mult/*
add wave /test/cpu/backend/mult/mult/*
add wave /test/cpu/backend/ldst/*
wave zoom range 15ns 30ns
view structure
view signals
run 30 us
