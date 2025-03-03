`include "myriscv.vh"

`ifndef _TYPES_SV
`define _TYPES_SV 1

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
	INSN_CSR    = 4'b1000,	// CSR instruction
	INSN_JAL    = 4'b1010,	// JAL, JALR
	INSN_BR     = 4'b1011,  // Conditional branch
	INSN_MRET   = 4'b1100,	// MRET, SRET
	INSN_FENCEI = 4'b1101,	// Completion fence
	INSN_ECALL  = 4'b1110,	// ECALL, EBREAK
	INSN_ERR    = 4'b1111,	// Invalid instruction (trap)
	INSN_X	    = 4'bxxxx
} insn_type_t;

function logic insn_mem(input insn_type_t insn);
   insn_mem = insn[3:2] == INSN_LD[3:2]; // CBO, LD, ST
endfunction

// Register bank and machine mode context
typedef enum logic [`CONTEXT_BITS-1:0] {
	CTX_MACHINE	= `CONTEXT_BITS ' (0),
	CTX_USER_MIN	= `CONTEXT_BITS ' (1),
	CTX_USER_MAX	= `CONTEXT_BITS ' (CTX_USER_MIN + `USER_CONTEXTS - 1)
} rcontext_t;

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

function mcontext_t mcontext_reset;
   mcontext_reset.m = CTX_MACHINE;
   mcontext_reset.u = CTX_USER_MAX;
endfunction // mcontext_reset

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

   // Sub-opcodes; may be modified from the input instruction
   logic   [2:0] funct3;
   logic   [6:0] funct7;

   // CSR read and write flags (for scoreboarding)
   logic	 csrr;
   logic	 csrw;

   // Atomic (LR/SC) memory operation
   logic	 lrsc;

   // Jump prediced taken?
   logic	 pred_taken;
} decoded_insn_t;

function decoded_insn_t dummy_op(
  input	       undead,
  input	       insn_type_t itype,
  input [31:0] pc,
  input	       pc_valid,
  input	       i16,
  input	       mcontext_t mcontext
  );
   dummy_op.undead     = undead;
   dummy_op.itype      = itype;
   dummy_op.rd	       = 'bx;
   dummy_op.rd_e       = 1'b0;
   dummy_op.rd_m       = 1'b0;
   dummy_op.rs1        = 'bx;
   dummy_op.rs1_valid  = 1'b0;
   dummy_op.rs2        = 'bx;
   dummy_op.rs2_valid  = 1'b0;
   dummy_op.imm        = 'bx;
   dummy_op.funct3     = 'bx;
   dummy_op.funct7     = 'bx;

   dummy_op.csrr       = 1'b0;
   dummy_op.csrw       = 1'b0;
   dummy_op.lrsc       = 1'b0;

   dummy_op.pc	       = pc;
   dummy_op.pc_valid   = pc_valid;
   dummy_op.i16        = i16;
   dummy_op.mcontext   = mcontext;
   dummy_op.pred_taken = 1'b0;
endfunction

function decoded_insn_t killed_op;
   killed_op = dummy_op(1'b0, INSN_X, 32'bx, 1'b0, 1'bx, 'bx);
endfunction

function decoded_insn_t null_op(input [31:0] pc, input mcontext_t mcontext);
   null_op = dummy_op(1'b0, INSN_X, pc, 1'b1, 1'bx, mcontext);
endfunction

function decoded_insn_t err_op(input [31:0] pc, input i16,
			       input mcontext_t mcontext);
   err_op = dummy_op(1'b1, INSN_ERR, pc, 1'b1, i16, mcontext);
endfunction

// This returns the true successor pc, without masking!
function logic [31:0] successor_pc(input decoded_insn_t op, input valid);
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

typedef enum logic {
  SMPOS_CNT   = 1'b0,	// shamt
  SMPOS_mWIMM = 1'b1,	// -wimm
  SMPOS_ANY   = 1'bx
} smpos_t;

typedef enum logic [1:0] {
  SMASK_NONE = 2'b00,  // Nothing is masked
  SMASK_ONE  = 2'b01,  // The mpos bit only is masked
  SMASK_HI   = 2'b10,  // mpos bits at the top are masked
  SMASK_LO   = 2'b11   // mpos bits at the bottom are masked
} smasktype_t;

typedef enum logic [1:0] {
  SPOS_CNT    = 2'b00, // shamt
  SPOS_WIMMm1 = 2'b01, // wimm - 1
  SPOS_mCNT   = 2'b10, // -shamt
  SPOS_1mWC   = 2'b11, // -(shamt + wimm - 1)
  SPOS_ANY    = 2'bxx
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

typedef enum shiftop_t {
	     SHIFTOP_SLL   = { 5'bx,  SROT_LEFT,  SMPOS_CNT,   SMASK_LO,   SPOS_ANY,    2'b00 },
	     SHIFTOP_SRL   = { 5'bx,  SROT_RIGHT, SMPOS_CNT,   SMASK_HI,   SPOS_ANY,    2'b00 },
	     SHIFTOP_SRA   = { 5'bx,  SROT_RIGHT, SMPOS_CNT,   SMASK_HI,   SPOS_mCNT,   2'b10 },
	     SHIFTOP_ROL   = { 5'bx,  SROT_LEFT,  SMPOS_ANY,   SMASK_NONE, SPOS_ANY,    2'b00 },
	     SHIFTOP_ROR   = { 5'bx,  SROT_RIGHT, SMPOS_ANY,   SMASK_NONE, SPOS_ANY,    2'b00 },
	     SHIFTOP_ZEXTB = { 5'd8,  SROT_NONE,  SMPOS_mWIMM, SMASK_HI,   SPOS_ANY,    2'b00 },
	     SHIFTOP_ZEXTH = { 5'd16, SROT_NONE,  SMPOS_mWIMM, SMASK_HI,   SPOS_ANY,    2'b00 },
	     SHIFTOP_SEXTB = { 5'd8,  SROT_NONE,  SMPOS_mWIMM, SMASK_HI,   SPOS_WIMMm1, 2'b10 },
	     SHIFTOP_SEXTH = { 5'd16, SROT_NONE,  SMPOS_mWIMM, SMASK_HI,   SPOS_WIMMm1, 2'b10 },
	     SHIFTOP_BCLR  = { 5'bx,  SROT_NONE,  SMPOS_CNT,   SMASK_ONE,  SPOS_ANY,    2'b00 },
	     SHIFTOP_BSET  = { 5'bx,  SROT_NONE,  SMPOS_CNT,   SMASK_ONE,  SPOS_ANY,    2'b01 },
	     SHIFTOP_BINV  = { 5'bx,  SROT_NONE,  SMPOS_CNT,   SMASK_ONE,  SPOS_CNT,    2'b11 },
	     SHIFTOP_BEXT  = { 5'd1,  SROT_RIGHT, SMPOS_mWIMM, SMASK_HI,   SPOS_ANY,    2'b00 },
	     SHIFTOP_EXTRU = { 5'bx,  SROT_RIGHT, SMPOS_mWIMM, SMASK_HI,   SPOS_ANY,    2'b00 },
	     SHIFTOP_EXTRS = { 5'bx,  SROT_RIGHT, SMPOS_mWIMM, SMASK_HI,   SPOS_1mWC,   2'b10 }
} shiftop_enum_t;

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
   cond_t      cond;
} aluctl_t;

typedef struct packed {
   logic       data;
   logic       stb;
   logic       incr;
   logic       bist;
   logic       dead;
} rng_bus_t;

`endif
