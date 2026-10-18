`ifndef _MYRISCV_CONFIG_VH
`define _MYRISCV_CONFIG_VH 1

// Because Quartus doesn't handle type parameters, it becomes
// difficult to make op_t carry a variable array. Instead simply rely
// on register elimination, and let this variable represent the maximum
// lg2(entries) in the return stack that can be specified by parameter.
// The upper bits will be constant 0 and should be eliminated.
`define RET_STACK_MAX_LG2	12

`endif // _MYRISCV_CONFIG_V
