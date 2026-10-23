#
# Runs before any Quartus flow
#
set cmd "make -C ../rtl"
post_message -type info "Command: $cmd"
qexec "$cmd"
