`ifndef _CONFIG_VH
`define _CONFIG_VH 1

`define SYS_CONTEXTS	1
`define USER_CONTEXTS	7
`define CONTEXT_BITS	$clog2(`SYS_CONTEXTS+`USER_CONTEXTS)
`define NUM_IRQS	31

`endif // _CONFIG_V
