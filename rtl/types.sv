`include "myriscv.vh"

`ifndef _TYPES_SV
`define _TYPES_SV 1

typedef enum logic [3:0] {
	INSN_NULL  = 4'b0000,	// Just zero rd
	INSN_ALU   = 4'b0001,	// ALU (incl NOP)
	INSN_MUL   = 4'b0010,	// True multiply
	INSN_MULL  = 4'b0011,	// MULH -> MULL forward
	INSN_LD    = 4'b0100,	// Memory load
	INSN_ST    = 4'b0101,	// Memory store
	INSN_JAL   = 4'b1000,	// JAL, JALR
	INSN_AGU   = 4'b1001,	// LUI, AUIPC
	INSN_BR    = 4'b1010,   // Conditional branch
	INSN_CSR   = 4'b1011,	// CSR instruction
	INSN_ECALL = 4'b1110,	// ECALL, EBREAK
	INSN_ERR   = 4'b1111	// Invalid instruction
} insn_type_t;

typedef struct packed {
   logic [4:0] r;		// Architectural register number
   logic [`CONTEXT_BITS-1:0] c;	// Register context
} regnum_t;

typedef struct packed {
   insn_type_t   itype;

   regnum_t	 rd;		// 5-bit register number
   logic	 rd_e;		// Register written to - ready after E stage
   logic	 rd_m;		// Register written to - ready after M stage
   regnum_t	 rs1;		// 5-bit register number or immediate
   logic	 rs1_valid;	// Register number (not immediate)
   regnum_t	 rs2;		// 5-bit register number or immediate
   logic	 rs2_valid;	// Register number (not immediate)
   logic signed [20:0] imm;	// Immediate (permuted for U immediate)
   logic	 imm_u;		// U-type immediate
   logic         imm_pc;	// PC-relative immediate (BR; JAL; AUIPC)

   logic  [31:0] pc;		// Address of this instruction
   logic	 i16;		// Compressed (16-bit) instruction

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
  input	       i16
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
   dummy_op.imm_u	= 1'bx;
   dummy_op.imm_pc	= 'bx;
   dummy_op.funct3	= 'bx;
   dummy_op.funct7	= 'bx;

   dummy_op.csrr	= 1'b0;
   dummy_op.csrw	= 1'b0;

   dummy_op.pc		= pc;
   dummy_op.i16		= i16;
   dummy_op.pred_taken	= 1'bx;
endfunction

function decoded_insn_t reset_op(input [31:0] reset_pc);
   reset_op = dummy_op(INSN_NULL, reset_pc - 3'd4, 1'b0);
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
//     1 - sand
//     0 - sxor

typedef struct packed {
   logic [1:0] rcnt;
   logic [2:0] mpos;
   logic [2:0] mcnt;
   logic [1:0] spos;
   logic       sand;
   logic       sxor;
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
   logic	bc_l;		// bitcnt count leading
   logic	bc_t;		// bitcnt count trailing
   logic	bc_s;		// bitcnt count set
   logic [1:0] msign;
   shiftop_t   shiftop;
   cond_t      cond;
} aluctl_t;

`endif
