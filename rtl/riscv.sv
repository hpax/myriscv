//
// Common RISC-V definitions
//

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
