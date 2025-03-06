`ifndef _MYRISCV_VH
`define _MYRISCV_VH 1

`include "config.vh"
`include "params.vh"
`include "functions.vh"

`ifdef MODEL_TECH
// ModelSim/Questa simulation needs type definitions included here
`include "riscv.sv"
`include "types.sv"
`endif

`endif
