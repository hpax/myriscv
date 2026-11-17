# Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
#
# Default Questa waveform setup for the generic test bench.
add log -r *
# add wave /test/cpu/rst_n
# add wave /test/cpu/clk
# add wave /test/mem/*
# add wave /test/io/*
# add wave -radix ascii /test/io/wdata
# add wave /test/cpu/ibus/a
# add wave /test/cpu/fetch/d_valid_i
# add wave /test/cpu/fetch/d_insn
# add wave /test/cpu/pipe_ctl/d_op
# add wave /test/cpu/pipe_ctl/e_valid_i
# add wave /test/cpu/pipe_ctl/e_op
# add wave /test/cpu/backend/e_pc
# add wave /test/cpu/backend/e_next_pc
# add wave /test/cpu/backend/e_restartpc
# add wave /test/cpu/backend/e_acceptable
# add wave /test/cpu/backend/e_accept
# add wave /test/cpu/backend/e_mispredict
# add wave /test/cpu/backend/e_restart
# add wave /test/cpu/backend/e_kill
# add wave /test/cpu/backend/e_src1
# add wave /test/cpu/backend/e_src2
# add wave /test/cpu/backend/e_addr
# add wave /test/cpu/backend/e_dout
# add wave /test/cpu/pipe_ctl/m_valid_i
# add wave /test/cpu/pipe_ctl/m_op
# add wave /test/cpu/pipe_ctl/m_busy
# add wave /test/cpu/backend/m_dout
# add wave /test/cpu/backend/m_kill
# add wave /test/cpu/dbus/*
# add wave /test/cpu/backend/mult/*
# add wave /test/cpu/backend/mult/mult/*
# add wave /test/cpu/backend/ldst/*
add wave /test/cpu/ibus/a
add wave /test/cpu/ibus/rdata
add wave /test/cpu/fetch/f2_pc
add wave /test/cpu/fetch/pred/*
add wave /test/cpu/pipe_ctl/d_valid_i
add wave /test/cpu/pipe_ctl/e_valid_i
add wave /test/cpu/backend/e_mispredict
add wave /test/cpu/backend/e_trap
add wave /test/cpu/backend/e_kill
add wave /test/cpu/backend/e_accept
add wave /test/cpu/backend/e_pc
add wave /test/cpu/backend/e_op.pc
add wave /test/io/valid
add wave /test/io/ready
add wave /test/io_sleeping
wave zoom range 15ns 30ns
view structure
view signals
run 50 us
