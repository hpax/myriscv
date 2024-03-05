//
// RISC-V instruction decode
//
// This decodes 32-bit instructions. 16-bit instructions are transcoded by
// the combinatorial logic in the rv32c_comb module (rv32c.sv); this can be
// done in this pipeline stage or another one.
//

typedef enum logic [3:0] {
	INSN_ZERO = 4'b0000,	// Just zero rd
	INSN_ALU  = 4'b0001,	// ALU (incl NOP)
	INSN_MUL  = 4'b0010,	// True multiply
	INSN_MULL = 4'b0011,	// MULH -> MULL forward
	INSN_LD   = 4'b0100,	// Memory load
	INSN_ST   = 4'b0101,	// Memory
	INSN_CSR  = 4'b0110,	// CSR instruction
	INSN_JMP  = 4'b1110,	// Control transfer instruction
	INSN_ERR  = 4'b1111	// Invalid instruction
} insn_type_t;

typedef struct packed {
   insn_type_t   type,

   logic   [4:0] rd,		// 5-bit register number
   logic	 rd_e,		// Register number valid and ready after E stage
   logic	 rd_m,		// Register number valid and ready after M stage
   logic   [4:0] rs1,		// 5-bit register number or 5-bit immediate
   logic	 rs1_valid,	// Register number valid and read from
   logic  [31:0] rs2,		// 5-bit register number or extended immediate
   logic	 rs2_valid,	// Register number valid and read from
   logic  [31:0] offs,		// Memory offset if applicable

   // Sub-operations; may be modified from the input instruction
   logic   [2:0] funct3,
   logic   [6:0] funct7,

   // CSR read and write flags (for scoreboarding)
   logic	 csrr,
   logic	 csrw,

   // Jump prediced taken?
   logic	 pred_taken
} decoded_insn_t;

// Combinatorial decoder
module decode_comb
  #(
    parameter bit DECODE_C       = 1'b1,	 // Set to 0 if not desired *OR* done before this logic.
    parameter bit PC_MASK        = 32'ffff_fffe, // Valid PC bits
    parameter bit STRICT_INVALID = 1'b0		 // Stricter invalid enforcement
    )
  (
   input [31:0]	 inst,
   input	 was_16, // Externally decoded 16-bit instruction
   input [31:0]	 pc,
   input	 pred_taken,

   output [31:0] next_pc,
   output	 decoded_insn_t dc
   );

   // Expand RV32C instructions if applicable
   wire [31:0]	 i;
   wire		 is_16;

   generate
      if (decode_c)
	begin
	   rv32c_comb rv32c ( .d(inst), .q(i), .is_16(is_16) );
	end
      else
	begin
	   assign i     = inst;
	   assign is_16 = was_16;
	end
   endgenerate

   // Strictly enforce pc_mask where applicable
   wire [31:0]	 masked_pc = pc & PC_MASK;

   // The PC of the next instruction
   wire [31:0]	 next_pc = (pc + {~is_16, is_16, 1'b0}) & PC_MASK;

   // Immediate formats
   wire [31:0] i_imm   = { {20{i[31]}}, i[31:20] };
   wire [31:0] s_imm   = { {20{i[31]}}, i[31:25], i[11:7] };
   wire [31:0] b_imm   = { {20{i[31]}}, i[7], i[30:25], i[11:8], 1'b0 };
   wire [31:0] u_imm   = { i[31:12], 12'b0 };
   wire [31:0] j_imm   = { {12{i[31]}}, i[19:12], i[20], i[30:21], 1'b0 };

   always @(*)
     begin
	logic valid;

	op = 'bx;
	op.rd      =  i[11:7]; op.rd_e       = 1'b0; op.rd_m      = 1'b0;
	op.rs1     =  i[19:5]; op.rs1_valid  = 1'b0;
	op.rs2     =  i_imm;   op.rs2_valid  = 1'b0;
	op.csrw    = 1'b0;     op.csrr    = 1'b0;
	op.pred_taken = pred_taken;
	op.type    = INSN_ERR;

	op.funct7 = i[31:25];
	op.funct3 = i[14:12];

	unique case (i[6:0])
	  BRANCH:    pcbase = b_imm;
	  JAL, JALR: pcbase = j_imm;
	  AUIPC:     pcbase = u_imm;
	  default:   pcbase = 'bx;
	endcase

	pcadder_out = pc + pcbase;

	unique case (i[6:0])
	  LOAD: begin
	     op.type      = INSN_LD;
	     valid        = !STRICT_INVALID
			  || (funct3 != 3'b011 && funct3[2:1] != 2'b11);
	     op.rd_m      = 1'b1;
	     op.rs1_valid = 1'b1;
	     op.offs      = i_imm;
	  end

	  STORE: begin
	     op.type      = INSN_ST;
	     valid        = (funct3 <= 3'b010);
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.offs      = s_imm;
	  end

	  BRANCH: begin
	     op.type       = INSN_JMP;
	     valid         = !STRICT_VALID || funct3[2:1] != 2'b01;
	     op.rs1_valid  = 1'b1;
	     op.rs2_valid  = 1'b1;
	     op.offs       = pcadder_out;
	  end

	  JALR: begin
	     op.type      = INSN_JMP;
	     valid        = 1'b1;
	     op.rd_e      = 1'b1;
	     op.offs      = i_imm;
	     op.rs1_valid = 1'b1;
	     op.rs2       = next_pc;
	  end

	  MISC_MEM: begin
	     op.type = INSN_ALU;
	     unique casez (funct3)
	       3'b000,		// FENCE/PAUSE
	       3'b001: begin	// FENCE.I (Zifencei)
		  valid = 1'b1;	// Treat as NOP
	       end
	       default: begin
		 // Unknown
	       end
	     endcase
	  end

	  JAL: begin
	     op.type      = INSN_JMP;
	     op.rd_e      = 1'b1;
	     op.rs1       = 5'b0;	// Treat this the same as jalr ...(x0)
	     op.rs1_valid = 1'b1;
	     op.offs      = pcadder_out;
	  end

	  OP, OP_IMM: begin
	     op.type      = INSN_ALU;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = !i[5];	// OP, not OP_IMM
	     op.rd_e      = 1'b1;

	     if (!op.rs2_valid && op.funct3[1:0] != 2'b01)
	       op.funct7 = 7'b0;	// True 12-bit immediate, no funct7

	     // Multiply and divide are separate from the ALU and
	     // produce results from the M stage unless forwarded;
	     // see separate synchronous postprocessing logic.
	     if (op.rs2_valid && !op.funct3[2] && funct7 == 7'b000_0001)
	       op.type = INSN_MUL;
	  end

	  SYSTEM: begin
	     op.rs1_valid = !op.funct3[2];
	     unique casez (funct3[1:0])
	       2'b01: begin	// CSRRW[I]
		  op.rd_e = 1'b1;
		  op.csrr = |rd;
		  op.csrw = 1'b1;
		  valid   = 1'b1;
		  op.type = INSN_CSR;
	       end
	       2'b1?: begin	// CSRR[SC][I]
		  op.rd_e = 1'b1;
		  op.csrr = 1'b1;
		  op.csrw = |rs1;
		  valid   = 1'b1;
		  op.type = INSN_CSR;
	       end
	       2'b00: begin
		  // Treat ECALL and EBREAK the same as invalid
		  // instructions as they always trap
		  valid = 1'b0;
	       end
	     endcase // unique casez (funct3[1:0])
	  end

	  AUIPC: begin
	     valid     = 1'b1;
	     op.type   = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rd_e   = 1'b1;
	     op.rs1    = 5'b0;
	     op.rs2    = pcadder_out;
	  end

	  LUI: begin
	     valid     = 1'b1;
	     op.type   = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rd_e   = 1'b1;
	     op.rs1    = 5'b0;
	     op.rs2    = u_imm;
	  end

	  default: begin
	     // All other opcodes are invalid; this also takes care
	     // of 16-bit decode failure
	     valid = 1'b0;
	  end
	endcase // unique case (i[6:0])

	// x0 can never be written, and always is zero (effectively
	// an immediate.) This enforces that constraint.
	if (!rd)
	  begin
	     rd_e = 1'b0;
	     rd_m = 1'b0;
	  end

	// Give the synthesizer a bit more flexibility
	if (!valid)
	  begin
	     op.type   = INSN_ERR;
	     op.rd     = 'bx;  op.rd_e       = 1'b0;  op.rd_m       = 1'b0;
	     op.rs1    = 'bx;  op.rs1_valid  = 1'b0;
	     op.rs2    = 'bx;  op.rs2_valid  = 1'b0;
	     op.offs   = 'bx;
	     op.funct3 = 3'bx;
	     op.funct7 = 7'bx;
	  end
     end // always @ (*)
endmodule

//
// D stage fast multiply watcher. Looks for a multiply that
// can safely use the result of a previous multiply; this is
// allows MULH* to forward the low half of the result to MUL in
// the E stage rather than M stage.
module decode_fast_mult
  (
   input	rst_n,
   input	clk,
   input	d_clken,

   input	d_kill, // If downstream instructions are killed

   input	decoded_insn_t dc_i,
   output	decoded_insn_t dc_o,

   // 00 = not a multiply
   // 01 = zero output (can be treated as AND)
   // 10 = regular multiply
   // 11 = can forward from previous multiply
   output [1:0]	is_mult_out
);

   reg		have_mult;
   reg [4:0]	mult_rs1;
   reg [4:0]	mult_rs2;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  have_mult <= 1'b0;
	  mult_rs1  <= 5'bx;
	  mult_rs2  <= 5'bx;
       end
     else if (d_clken)
       begin
	  logic is_mult;

	  dc_o = dc_i;

	  is_mult = 1'b0;
	  if (dc_i.type == INSN_MUL)
	    begin
	       if (!dc_i.rd_e_in || !dc_i.rs1 || !dc_i.rs2) begin
		  // Zero multiply
		  dc_o.type   = INSN_ZERO;
	       end else if (have_mult && !dc_i.funct3[1:0] &&
			    dc_i.rs1 == mult_rs1 &&
			    rc_i.rs2 == mult_rs2) begin
		  // XXX: could also compare the case of rs1 and rs2 swapped
		  dc_o.type = INSN_MULL; // Forward old multiply
	       end else begin
		  // Need to actually multiply
		  dc_o.rd_m = 1'b1;		   // Output in M stage
		  dc_o.rd_e = 1'b0;
		  is_mult   = 1'b1;
	       end
	    end // if (is_mult_in)

	  if (d_kill)
	    have_mult <= 1'b0;	// State rolled back
	  else if (is_mult)
	    have_mult <= rs1 != rd && rs2 != rd;
	  else if ((op_i.rd_e_in | op_i.rd_m_in) &&
		   (op_i.rd == mult_rs1 || op_i.rd == mult_rs2))
	    have_mult <= 1'b0;	// Input registers clobbered
       end // if (d_clken)
endmodule // decode_fast_mult

//
// Decoder pipeline stage
//

module d_stage (
		input rst_n,
		input clk,
		input clken,

		input 
