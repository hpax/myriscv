add log -r *
add wave *
add wave /cpu/fetch/*
add wave /cpu/pipe_ctl/*
add wave /cpu/backend/e_src*
add wave /cpu/backend/e_addr
add wave /cpu/backend/e_dout
add wave /cpu/backend/m_dout
view structure
view signals
run 1 us
