<!-- Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> -->

# myriscv repository instructions

## Build and test commands

- Generate `rtl/params.vh` from the parameter source: `make -C rtl`.
  `quartus/preflow.tcl` runs this before the Quartus flow; never edit the
  generated header directly.
- Build the bundled RISC-V cross toolchain (including its required
  submodules): `make -C tools gnu`. The result is installed below
  `tools/gnu/`; test builds use the `riscv32-hpa-elf-` tools from there.
- Build all bare-metal test images: `make -C test`.
- Build one test's TCM image: `make -C test tests/test1/test1.tcm.hex`.
  A test directory's basename determines its ELF and hex-file target, so use
  the corresponding path for another test.
- Run the Quartus synthesis flow from `quartus/`:
  `quartus_sh --flow compile myriscv`. The project targets a Cyclone IV E
  EP4CE15F23C8 and sets `benchmark` as its top-level entity.

The Quartus project configures a Questa NativeLink simulation around
`test/test.sv` and `test/test.tcl`.

## Architecture

`rtl/myriscv.sv` is the parameterized CPU integration point. It connects the
fetch, decode, pipeline-control, and backend units; terminates the instruction
and data buses in TCM, external RAM, or I/O; and handles interrupt latching.
`rtl/params.sv` defines the configurable ISA, memory-map, register-context,
counter, and timing parameters. The default core is RV32I with selected B, C,
Zkr, LR/SC, cache-management, and custom extensions documented in
`doc/architecture.txt`.

The global pipeline is F1/F2 fetch, decode, execute, memory, and writeback.
`rtl/fetch.sv` owns the split fetch stage and prediction, `rtl/decode.sv`
produces `decoded_insn_t`, `rtl/pipeline.sv` owns inter-stage stalls and
bypasses, and `rtl/backend.sv` implements execute through writeback, including
CSRs, the register file, loads/stores, multiplication, and traps. Shared
instruction and control types live in `rtl/types.sv`; opcode and CSR
definitions live in `rtl/riscv.sv`.

The core uses a Harvard internal interface but arbitrates I-cache fetches and
data transactions onto the external memory bus. Addresses below `tcm_base`
report a bus error; TCM occupies `[tcm_base, ram_base)`, RAM occupies
`[ram_base, io_base)`, and I/O begins at `io_base`. Instruction fetches from
I/O are errors. The external-memory integration must return `mem_ready` for
the accepted request and provide `mem_addr_i`, `mem_wr`, and `mem_cpu` for
I-cache invalidation; see the top-level port contract in `rtl/myriscv.sv`.

`test/` builds freestanding programs into separate TCM and external-memory
hex files. `test/bench/test.sv` instantiates the CPU with `extmem.sv`, prints
writes to `0xffff_fffc`, and ends simulation on a write to `0xffff_fff8`.
`make -C test run-<name>` compiles the bench with that test's image files.

## Repository-specific conventions

- Keep pipeline signal names aligned with `doc/pipeline.txt`: a register is
  named for the stage where its output is valid, and combinational signals use
  the producing register's stage name. Document any non-stage connection as a
  bypass.
- Preserve the valid/busy/stall/kill protocol. A unit with `valid_o` asserted
  must keep its output stable while stalled unless killed; a killed upstream
  stage must drive `valid_o` low by the next cycle. The E stage is the last
  stage that may abort an instruction; an instruction admitted to M must
  retire.
- Make decode changes through the shared packed types and helpers in
  `rtl/types.sv`. `INSN_LD`, `INSN_ST`, and `INSN_CBO` deliberately share the
  high bits used by `insn_mem()`, and `decoded_insn_t` separates results ready
  after E (`rd_e`) from those ready after M (`rd_m`) for forwarding.
- Parameter changes belong in `rtl/params.sv`; regenerate `params.vh` before
  compiling. Modules receive the complete parameter set through ``#(`CONFIG)``
  and pass it onward with ``#(`CFG)``.
- Maintain the source ordering in `quartus/myriscv.qsf` when introducing
  package dependencies. `myriscv.vh` imports both shared packages, and defines
  `MODEL_TECH`-specific includes required by Questa/ModelSim compilation.
- Add bare-metal tests under `test/tests/<name>/` using matching `<name>.S` or
  `<name>.c`; optional `<name>.mk` files set target-specific Make variables.
  `test/Makefile` discovers these directories and emits `tests.d`; run a test
  with `make -C test run-<name>`.
