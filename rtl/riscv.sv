//
// Common RISC-V definitions
//

`ifndef _RISCV_SV
`define _RISCV_SV 1

// Base opcode spaces
typedef enum logic [6:0] {
	LOAD     = 7'b0000011,
	LOAD_FP  = 7'b0000111,
	CUSTOM0  = 7'b0001011,
	MISC_MEM = 7'b0001111,
	OP_IMM   = 7'b0010011,
	AUIPC    = 7'b0010111,
	OP_IMM32 = 7'b0011011,
	STORE    = 7'b0100011,
	STORE_FP = 7'b0100111,
	CUSTOM1  = 7'b0101011,
	AMO      = 7'b0101111,
	OP       = 7'b0110011,
	LUI      = 7'b0110111,
	OP32     = 7'b0111011,
	MADD     = 7'b1000011,
	MSUB     = 7'b1000111,
	NMADD    = 7'b1001011,
	NMSUB    = 7'b1001111,
	OP_FP    = 7'b1010011,
	RESV25   = 7'b1010111,
	CUSTOM2  = 7'b1011011,
	BRANCH   = 7'b1100011,
	JALR     = 7'b1100111,
	RESV32   = 7'b1101011,
	JAL      = 7'b1101111,
	SYSTEM   = 7'b1110011,
	RESV35	 = 7'b1110111,
	CUSTOM3	 = 7'b1111011
} op_t;

// Condition selections
typedef enum logic [2:0] {
	COND_EQ	 = 3'b000,
	COND_NE	 = 3'b001,
	COND_LT	 = 3'b100,
	COND_GE	 = 3'b101,
	COND_LTU = 3'b110,
	COND_GEU = 3'b111
} cond_t;

// ALU funct3 operations codes
typedef enum logic [2:0] {
	ALU_ADD	 = 3'b000,	// SUB if sign
	ALU_SLL	 = 3'b001,
	ALU_SLT  = 3'b010,
	ALU_SLTU = 3'b011,
	ALU_XOR  = 3'b100,	// XNOR if sign
	ALU_SRL  = 3'b101,	// SRA if sign - applies even to immediate
	ALU_OR   = 3'b110,	// ORN if sign
	ALU_AND	 = 3'b111	// ANDN if inverted
} aluop_t;

// CSR register numbers
typedef enum logic [11:0] {
	// Standard CSRs
	CSR_CYCLE		= 12'hc00,
	CSR_CYCLEH		= 12'hc80,
	CSR_TIME		= 12'hc01,
	CSR_TIMEH		= 12'hc81,
	CSR_INSTRET		= 12'hc02,
	CSR_INSTRETH		= 12'hc82,

	CSR_SEED		= 12'h015,

	CSR_MVENDORID		= 12'hf11,
	CSR_MARCHID		= 12'hf12,
	CSR_MIMPID		= 12'hf13,
	CSR_MHARTID		= 12'hf14,

	CSR_MSTATUS		= 12'h300,
	CSR_MISA		= 12'h301,
	CSR_MIE			= 12'h304,
	CSR_MTVEC		= 12'h305,
	CSR_MSTATUSH		= 12'h310,
	CSR_MSCRATCH		= 12'h340,
	CSR_MEPC		= 12'h341,
	CSR_MCAUSE		= 12'h342,
	CSR_MTVAL		= 12'h343,
	CSR_MIP			= 12'h344,
	CSR_MTINST		= 12'h34a,

	CSR_MENVCFG		= 12'h30a,
	CSR_MENVCFGH		= 12'h31a,

	CSR_MCYCLE		= 12'hb00,
	CSR_MINSTRET		= 12'hb02,
	CSR_MCYCLEH		= 12'hb80,
	CSR_MINSTRETH		= 12'hb82,

	CSR_TSELECT		= 12'h7a0,
	CSR_TDATA1		= 12'h7a1,
	CSR_TDATA2		= 12'h7a2,
	CSR_TDATA3		= 12'h7a3,
	CSR_MCONTEXT		= 12'h7a8,

	CSR_DCSR		= 12'h7b0,
	CSR_DPC			= 12'h7b1,
	CSR_DSCRATCH0		= 12'h7b2,
	CSR_DSCRATCH1		= 12'h7b3,

	// Extensions CSRs
	CSR_USER_CONTEXT	= 12'h7f0,
	CSR_CIE			= 12'h7f1 // Interrupt enable by context
} csr_t;

typedef enum logic [31:0] {
	     MCAUSE_BADPC   = 32'd0,
	     MCAUSE_IBUSERR = 32'd1,
	     MCAUSE_BADINSN = 32'd2,
	     MCAUSE_BREAK   = 32'd3,
	     MCAUSE_LALIGN  = 32'd4,
	     MCAUSE_LBUSERR = 32'd5,
	     MCAUSE_SALIGN  = 32'd6,
	     MCAUSE_SBUSERR = 32'd7,
	     MCAUSE_ECALLU  = 32'd8,
	     MCAUSE_ECALLS  = 32'd9,
	     // 10 reserved
	     MCAUSE_ECALLM  = 32'd11,
	     MCAUSE_IPAGE   = 32'd12,
	     MCAUSE_LPAGE   = 32'd13,
	     // 14 reserved
	     MCAUSE_SPAGE   = 32'd15,

	     // 16-23 reserved
	     // 24-31 custom
	     // 32-47 reserved
	     // 48-63 custom

	     MCAUSE_IRQ     = 32'h8000_0000,

	     MCAUSE_FIXED_MASK = MCAUSE_IRQ | 32'd63
} csr_mcause_t;

`endif
