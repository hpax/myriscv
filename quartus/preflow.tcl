#
# Runs before any Quartus flow
#
set cmd "make prereq || true"
post_message -type info "Command: $cmd"
qexec "$cmd"
