`include "myriscv.vh"

`ifndef _TYPES_SV
`define _TYPES_SV 1

//
// Note:
// INSN_KILLED means an interruption in the flow of control, the PC
// of the instruction packet is invalid, but the next valid instruction
// received in the pipeline will contain a canonical (guaranteed
// non-speculative) PC.
// INSN_NULL means that PC should not be advanced.
// INSN_NOP means the PC should be advanced normally.
//
typedef enum logic [3:0] {
	INSN_KILLED = 4'b0000,	// Killed instruction
	INSN_NULL   = 4'b0001,	// Branch bubble
	INSN_NOP    = 4'b0010,	// No-op instruction (unless decoded as ALU)
	INSN_ALU    = 4'b0011,	// ALU instruction
	INSN_MUL    = 4'b0100,	// True multiply
	INSN_MULL   = 4'b0101,	// MULH -> MULL forward
	INSN_LD     = 4'b0110,	// Memory load
	INSN_ST     = 4'b0111,	// Memory store
	INSN_CSR    = 4'b1000,	// CSR instruction
	INSN_JAL    = 4'b1010,	// JAL, JALR
	INSN_BR     = 4'b1011,  // Conditional branch
	INSN_MRET   = 4'b1100,	// MRET, SRET
	INSN_FENCEI = 4'b1101,	// Completion fence
	INSN_ECALL  = 4'b1110,	// ECALL, EBREAK (trap)
	INSN_ERR    = 4'b1111	// Invalid instruction (trap)
} insn_type_t;

function logic insn_ldst(input insn_type_t insn);
   insn_ldst = insn[3:1] == 3'b011;
endfunction
function logic insn_real(input insn_type_t insn);
   // Not INSN_KILLED or INSN_NULL
   insn_real = |insn[3:1];
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
   logic	 i16;		// Compressed (16-bit) instruction
   mcontext_t	 mcontext;	// Machine context

   // Sub-opcodes; may be modified from the input instruction
   logic   [2:0] funct3;
   logic   [6:0] funct7;

   // CSR read and write flags (for scoreboarding)
   logic	 csrr;
   logic	 csrw;

   // Jump prediced taken?
   logic	 pred_taken;
} decoded_insn_t;

function decoded_insn_t dummy_op(
  input	       insn_type_t itype,
  input [31:0] pc,
  input	       i16,
  input	       mcontext_t mcontext
  );
   dummy_op.itype	= itype;
   dummy_op.rd		= 'bx;
   dummy_op.rd_e	= 1'b0;
   dummy_op.rd_m	= 1'b0;
   dummy_op.rs1		= 'bx;
   dummy_op.rs1_valid	= 1'b0;
   dummy_op.rs2		= 'bx;
   dummy_op.rs2_valid	= 1'b0;
   dummy_op.imm		= 'bx;
   dummy_op.funct3	= 'bx;
   dummy_op.funct7	= 'bx;

   dummy_op.csrr	= 1'b0;
   dummy_op.csrw	= 1'b0;

   dummy_op.pc		= pc;
   dummy_op.i16		= i16;
   dummy_op.mcontext    = mcontext;
   dummy_op.pred_taken	= 1'b0;
endfunction

function decoded_insn_t killed_op;
   killed_op = dummy_op(INSN_KILLED, 32'bx, 1'bx, 'bx);
endfunction

function decoded_insn_t null_op(input [31:0] pc, input mcontext_t mcontext);
   null_op = dummy_op(INSN_NULL, pc, 1'bx, mcontext);
endfunction

function decoded_insn_t err_op(input [31:0] pc, input i16,
			       input mcontext_t mcontext);
   err_op = dummy_op(INSN_ERR, pc, i16, mcontext);
endfunction

// This returns the true successor pc, without masking!
function logic [31:0] successor_pc(input decoded_insn_t op, input valid);
   successor_pc = op.pc;
   if (valid & insn_real(op.itype))
     successor_pc += op.i16 ? 3'd2 : 3'd4;
endfunction

//
// Shifter operation control.
//
//  10:9 - rcnt
//          00 = 0
//          10 = shamt
//          11 = -shamt
//   8:7 - mpos
//          00 = 0
//          01 = 1
//          10 = shamt
//          11 = -mcnt
//   6:4 - mcnt:
//         000 =  0
//         001 =  1
//         011 = -1
//         100 = -8
//         101 = -16
//         100 = shamt
//         111 = -shamt
//   3:2 - spos:
//          00 =   0
//          01 =  -1
//          10 = shamt
//          11 = -mcnt-1
//   1:0 - sign (masked) bit selection:
//	    00 =  0
//	    01 =  1
//          10 =  src[spos]
//	    11 = ~src[spos]
//

typedef struct packed {
   logic [1:0] rcnt;
   logic [1:0] mpos;
   logic [2:0] mcnt;
   logic [1:0] spos;
   logic [1:0] sbit;
} shiftop_t;

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

`endif
