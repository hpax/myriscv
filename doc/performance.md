The performance characteristics of this core at this time are:

- Most instructions complete in a single cycle, except as noted here,
  unless there are delays due to memory or I/O.

- Conditional branches (`br`) are predicted not taken if forward,
  predicted if backwards.

- Direct jumps (`j`, `jal`) are always predicted; if `PREDICT_RET` is
  configured then `jal` with a destination register of `x1` or `x5` is
  predicted to be a call and pushed to the return prediction stack.

- Indirect jumps (`jr`, `jalr`) are predicted if `PREDICT_JALR` is
  configured. If `PREDICT_RET` is configured and the instruction
  follows the RISC-V defintion of a return, the address is taken from
  the return stack, otherwise a `lui` or `auipc` instruction
  immediately preceeding the jump is taken as the base address;
  otherwise the base is predicted as zero.

- A mispredicted branch or jump takes a penalty of 6 cycles.

- A branch or jump to a misaligned 32-bit instruction requires one
  extra cycle, regardless of prediction.

- If `FUSE_CNOP` is configured, two 16-bit instructions where the
  second one is `c.nop` is executed as one.

- A multiply has a pipelined 2-cycle use latency. If `FORWARD_MUL` is
  configured, then forwarding from `mulh*` to `mul` is supported, such
  that:

~~~
	mulhu a1,a2,a3
	mul   a0,a2,a2
	/* Both a0 and a1 are immediately ready */
~~~

- A load has a pipelined 2-cycle use latency.

- Writing the `waitfor` CSR takes a minimum of 2 cycles, plus any wait time.

- The `mret` instruction takes the same penalty as a branch
  mispredict, as does any instruction which changes the `user_context`
  CSR.
