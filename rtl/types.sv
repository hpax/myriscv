`ifndef _MYRISCV_TYPES_SV
`define _MYRISCV_TYPES_SV 1

`include "config.vh"

package myriscv_types;

typedef enum logic [3:0] {
	INSN_NOP    = 4'b0000,	// No-op instruction (unless decoded as ALU)
	INSN_MUL    = 4'b0001,	// Multiply
	INSN_ALU    = 4'b0010,	// ALU instruction
	INSN_XALU   = 4'b0011,	// Custom ALU instruction (CUSTOM0/1)
	// The low 2 bits of the following must be maintained.
	INSN_LD     = 4'b0100,	// Memory load
	INSN_ST     = 4'b0101,	// Memory store
	INSN_CBO    = 4'b0110,	// Cache block operation
	// 4'b0111 is exclusively RESERVED for another memory operation!
        INSN_CSR    = 4'b1000,	// CSRR, CSRW et al
	INSN_JAL    = 4'b1010,	// JAL, JALR
	INSN_BR     = 4'b1011,  // Conditional branch
	INSN_MRET   = 4'b1100,	// MRET, SRET
	INSN_FENCEI = 4'b1101,	// Completion fence
	INSN_ECALL  = 4'b1110,	// ECALL, EBREAK
	INSN_ERR    = 4'b1111,	// Invalid instruction (trap)
	INSN_X	    = 4'bxxxx
} insn_type_t;

function automatic logic insn_mem(input insn_type_t insn);
   insn_mem = insn[3:2] == INSN_LD[3:2]; // CBO, LD, ST
endfunction

// 5 bits is the maximum possible rcontext, due to the defintion of
// the CIE CSR. Variable assignments should be conditioned on CTX_MASK
// to keep the synthesizer from having to generate all bits if not needed.
typedef logic [4:0] rcontext_t;

typedef struct packed {
   rcontext_t c;		// Register context
   logic [4:0] r;		// Architectural register number
} regnum_t;

// Machine context that is subject to update/change on a pipeline kill.
// This is not restricted just to being the register context.
// This has nothing to do with the debug/trace "mcontext" CSR!!
typedef struct packed {
   rcontext_t m;		// Currently executing context
   rcontext_t u;		// Current user context (user_context csr)
} mcontext_t;

// Return stack position type
typedef logic [`RET_STACK_MAX_LG2-1:0] retstack_t;

typedef struct packed {
   logic         undead;	// It is an executable instruction

   insn_type_t   itype;

   regnum_t	 rd;		// 5-bit register number
   logic	 rd_e;		// Register written to - ready after E stage
   logic	 rd_m;		// Register written to - ready after M stage
   regnum_t	 rs1;		// 5-bit register number or immediate
   logic	 rs1_valid;	// Register number (not immediate)
   regnum_t	 rs2;		// 5-bit register number or immediate
   logic	 rs2_valid;	// Register number (not immediate)
   logic signed [31:0] imm;	// Decoded immediate (almost always signed!)

   logic  [31:0] pc;		// Address of this instruction
   logic	 pc_valid;	// This PC is meaningful, even if undead=0!
   logic	 i16;		// Compressed (16-bit) instruction
   mcontext_t	 mcontext;	// Machine context
   retstack_t    retstack;	// Position of return stack for restart

   // Sub-opcodes; may be modified from the input instruction
   logic   [2:0] funct3;
   logic   [6:0] funct7;

   // CSR read and write flags (for scoreboarding)
   logic	 csrr;
   logic	 csrw;

   // Atomic (LR/SC) memory operation
   logic	 lrsc;
} decoded_insn_t;

function automatic decoded_insn_t dummy_op(
  input	       undead,
  input	       insn_type_t itype,
  input [31:0] pc,
  input	       pc_valid,
  input	       i16,
  input	       mcontext_t mcontext
  );
   dummy_op.undead    = undead;
   dummy_op.itype     = itype;
   dummy_op.rd	      = 'bx;
   dummy_op.rd_e      = 1'b0;
   dummy_op.rd_m      = 1'b0;
   dummy_op.rs1       = 'bx;
   dummy_op.rs1_valid = 1'b0;
   dummy_op.rs2       = 'bx;
   dummy_op.rs2_valid = 1'b0;
   dummy_op.imm       = 'bx;
   dummy_op.funct3    = 'bx;
   dummy_op.funct7    = 'bx;

   dummy_op.csrr      = 1'b0;
   dummy_op.csrw      = 1'b0;
   dummy_op.lrsc      = 1'b0;

   dummy_op.pc	      = pc;
   dummy_op.pc_valid  = pc_valid;
   dummy_op.i16       = i16;
   dummy_op.mcontext  = mcontext;

   dummy_op.retstack  = 'bx;
endfunction

function automatic decoded_insn_t killed_op;
   killed_op = dummy_op(1'b0, INSN_X, 32'bx, 1'b0, 1'bx, 'bx);
endfunction

function automatic decoded_insn_t null_op(input [31:0] pc, input mcontext_t mcontext);
   null_op = dummy_op(1'b0, INSN_X, pc, 1'b1, 1'bx, mcontext);
endfunction

function automatic decoded_insn_t err_op(input [31:0] pc, input i16,
			       input mcontext_t mcontext);
   err_op = dummy_op(1'b1, INSN_ERR, pc, 1'b1, i16, mcontext);
endfunction

// This returns the true successor pc, without masking!
function automatic logic [31:0] successor_pc(input decoded_insn_t op, input valid);
   if (~op.pc_valid) begin
      successor_pc = 32'bx;
   end else begin
      successor_pc = op.pc;
      if (valid & op.undead)
	successor_pc += op.i16 ? 3'd2 : 3'd4;
   end
endfunction

//
// Shifter operation control. Entries in parens aren't used and may be
// x'd out.
//
typedef enum logic [1:0] {
  SROT_NONE  = 2'b00,	// No rotation
  SROT_RIGHT = 2'b10,	// Rotate right
  SROT_LEFT  = 2'b11	// Rotate left
} srot_t;


// Position of mask (see below for interpretation)
typedef enum logic {
  SMPOS_CNT   = 1'b0,	// shamt
  SMPOS_WIMM  = 1'b1,	// wimm
  SMPOS_ANY   = 1'bx
} smpos_t;

typedef enum logic [1:0] {
  SMASK_ONE  = 2'b00,  // The mpos bit only is masked
  SMASK_LO   = 2'b01,  // mpos bits at the bottom are masked
  SMASK_UP   = 2'b10,  // Bits mpos+ are masked (for mpos = 0, no bits)
  SMASK_HI   = 2'b11   // mpos bits at the top are masked
} smasktype_t;

// Pre-shift position of sign bit
typedef enum logic  {
  SPOS_WIMMm1 = 1'b0, // wimm - 1
  SPOS_CWm1   = 1'b1, // wimm + (shamt - 1) SATURATING
  SPOS_ANY    = 1'bx
} spos_t;

typedef struct packed {
   logic [4:0] wimm;		// Width immediate
   srot_t      srot;
   smpos_t     smpos;
   smasktype_t smask;
   spos_t      spos;
   logic       sand;
   logic       sxor;
} shiftop_t;

const shiftop_t SHIFTOP_SLL   = { 5'bx,  SROT_LEFT,  SMPOS_CNT,   SMASK_LO,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_SLO   = { 5'bx,  SROT_LEFT,  SMPOS_CNT,   SMASK_LO,   SPOS_ANY,    2'b01 }; // Shift left 1's
const shiftop_t SHIFTOP_SRL   = { 5'bx,  SROT_RIGHT, SMPOS_CNT,   SMASK_HI,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_SRA   = { 5'd0,  SROT_RIGHT, SMPOS_CNT,   SMASK_HI,   SPOS_WIMMm1, 2'b10 };
const shiftop_t SHIFTOP_SRO   = { 5'bx,  SROT_RIGHT, SMPOS_CNT,   SMASK_HI,   SPOS_ANY,    2'b01 }; // Shift right 1's
const shiftop_t SHIFTOP_ROL   = { 5'b0,  SROT_LEFT,  SMPOS_WIMM,  SMASK_LO,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_ROR   = { 5'b0,  SROT_RIGHT, SMPOS_WIMM,  SMASK_LO,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_ZEXTB = { 5'd8,  SROT_NONE,  SMPOS_WIMM,  SMASK_UP,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_ZEXTH = { 5'd16, SROT_NONE,  SMPOS_WIMM,  SMASK_UP,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_SEXTB = { 5'd8,  SROT_NONE,  SMPOS_WIMM,  SMASK_UP,   SPOS_WIMMm1, 2'b10 };
const shiftop_t SHIFTOP_SEXTH = { 5'd16, SROT_NONE,  SMPOS_WIMM,  SMASK_UP,   SPOS_WIMMm1, 2'b10 };
const shiftop_t SHIFTOP_BCLR  = { 5'bx,  SROT_NONE,  SMPOS_CNT,   SMASK_ONE,  SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_BSET  = { 5'bx,  SROT_NONE,  SMPOS_CNT,   SMASK_ONE,  SPOS_ANY,    2'b01 };
const shiftop_t SHIFTOP_BINV  = { 5'd1,  SROT_NONE,  SMPOS_CNT,   SMASK_ONE,  SPOS_CWm1,   2'b11 };
const shiftop_t SHIFTOP_BEXT  = { 5'd1,  SROT_RIGHT, SMPOS_WIMM,  SMASK_UP,   SPOS_ANY,    2'b00 }; // == extru ...,1
const shiftop_t SHIFTOP_EXTRU = { 5'bx,  SROT_RIGHT, SMPOS_WIMM,  SMASK_UP,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_EXTRS = { 5'b0,  SROT_RIGHT, SMPOS_WIMM,  SMASK_UP,   SPOS_CWm1,   2'b10 };
const shiftop_t SHIFTOP_ZEXTN = { 5'bx,  SROT_NONE,  SMPOS_CNT,   SMASK_UP,   SPOS_ANY,    2'b00 };
const shiftop_t SHIFTOP_SEXTN = { 5'b0,  SROT_NONE,  SMPOS_CNT,   SMASK_UP,   SPOS_CWm1,   2'b10 };

//
// ALU operation definitions
//
typedef enum logic [4:0] {
	ALUSRC_ERR,		// Invalid instruction
	ALUSRC_ADD,
	ALUSRC_LOGIC,
	ALUSRC_SET,		// Set to result of compare
	ALUSRC_MINMAX,		// compare ? src1 : src2
        ALUSRC_BITCNT,
        ALUSRC_ORC,
	ALUSRC_REV,
	ALUSRC_ZICOND,
	// These units need to get MUXed in as late as possible
	ALUSRC_SHIFT = 5'b10000
} alusrc_t;

typedef struct packed {
   alusrc_t    unit;
   logic       invert;
   logic [1:0] shadd;
   logic [1:0] bitop;
   logic [2:0] bcop;		// bitcnt operation
   logic [1:0] msign;
   shiftop_t   shiftop;
   riscv::cond_t cond;
} aluctl_t;

typedef struct packed {
   logic       data;
   logic       stb;
   logic       incr;
   logic       bist;
   logic       dead;
} rng_bus_t;

// Cache block operation types
typedef struct packed {
   logic wb;			// Write back this cache line
   logic invd;			// Invalidate this cache line
} cbo_t;

const cbo_t CBO_NONE  = 2'b00;
const cbo_t CBO_INVAL = 2'b01;
const cbo_t CBO_CLEAN = 2'b10;
const cbo_t CBO_FLUSH = 2'b11;
const cbo_t CBO_X     = 2'bxx;

function automatic logic cbo_valid(cbo_t cbo);
   cbo_valid = cbo != CBO_NONE;
endfunction

// Information forwarded from the D to F2 stages to
// allow AUIPC/LUI -> JALR prediction
typedef struct packed {
   logic  [4:0] rnum;
   logic [31:0] imm;
} d_pred_t;

// What d_insn is set to either after decoding an invalid RVC instruction
// or before the first d_valid_i assertion after reset or a pipeline kill.
// This must be selected so d_pred will not contain invalid information.
const logic [31:0] INVALID_INSN = { 27'bx, 5'b11111 };

endpackage

`endif
