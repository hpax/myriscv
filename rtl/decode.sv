//
// RISC-V instruction decode
//
// This decodes 32-bit instructions. 16-bit instructions are transcoded by
// the combinatorial logic in the rv32c_comb module (rv32c.sv); this can be
// done in this pipeline stage or another one.
//

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
   insn_type_t   type,

   logic   [4:0] rd,		// 5-bit register number
   logic	 rd_e,		// Register written to - ready after E stage
   logic	 rd_m,		// Register written to - ready after M stage
   logic   [4:0] rs1,		// 5-bit register number or immediate
   logic	 rs1_valid,	// Register number (not immediate)
   logic   [4:0] rs2,		// 5-bit register number or immediate
   logic	 rs2_valid,	// Register number (not immediate)
   logic signed [20:0] imm,	// Immediate (permuted for U immediate)
   logic	 imm_u,		// U-type immediate
   logic         imm_pc,	// PC-relative immediate (BR, JAL, AUIPC)

   logic  [31:0] pc,		// Address of this instruction
   logic	 i16,		// Compressed (16-bit) instruction

   // Sub-opcodes; may be modified from the input instruction
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
    parameter bit STRICT_INVALID = 1'b0		 // Stricter invalid enforcement
    )
  (
   input [31:0]	d_din, // From fetch stage
   input	d_was_16, // Externally decoded 16-bit instruction
   input	d_pred_taken,
   input [31:0]	d_pc,

   output	decoded_insn_t op
   );

   // Expand RV32C instructions if applicable
   wire [31:0]	 i;

   generate
      if (DECODE_C)
	begin
	   rv32c_comb rv32c (.d(d_din), .q(i), .is_16(op.i16));
	end
      else
	begin
	   assign i      = d_din;
	   assign op.i16 = d_was_16;
	end
   endgenerate

   // Immediate formats
   wire signed [11:0] i_imm = i[31:20];
   wire signed [11:0] s_imm = { i[31:25], i[11:7] };
   wire signed [12:0] b_imm = { i[31], i[7], i[30:25], i[11:8], 1'b0 };
   wire signed [20:0] j_imm = { i[31], i[19:12], i[20], i[30:21], 1'b0 };
   // U-immediate in mangled format that mostly matches the J immediate format
   // XXX: is the D and E stages close enough that this hack is actually
   // a net loss??? Experiment.
   wire signed [20:0] u_imm = { 1'bx, i[19:12], i[31:20] };

   always @(*)
     begin
	logic valid;

	op	      = 'bx;
	op.pc         = d_pc;
	op.rd	      = i[11:7];  op.rd_e       = 1'b0; op.rd_m      = 1'b0;
	op.rs1	      = i[19:5];  op.rs1_valid  = 1'b0;
	op.rs2	      = i[16:12]; op.rs2_valid  = 1'b0;
	op.imm	      = 'bx;      op.imm_u      = 1'b0; op.imm_pc    = 1'b0;
	op.csrw       = 1'b0;     op.csrr       = 1'b0;
	op.pred_taken = d_pred_taken;
	op.type       = INSN_ERR;

	op.funct7     = i[31:25];
	op.funct3     = i[14:12];

	if (d_irq)
	  begin
	     // Inject interrupt pseudo-instruction
	     op.type	   = INSN_IRQ;
	     op.pred_taken = 1'b0; // Asynchronous, hence not predicted!
	  end
	else unique case (i[6:0])
	  LOAD: begin
	     op.type      = INSN_LD;
	     valid        = !STRICT_INVALID
			  || (op.funct3 != 3'b011 && op.funct3[2:1] != 2'b11);
	     op.rd_m      = 1'b1;
	     op.rs1_valid = 1'b1;
	     op.imm       = i_imm;
	  end

	  STORE: begin
	     op.type      = INSN_ST;
	     valid        = (op.funct3 <= 3'b010);
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.imm       = s_imm;
	  end

	  BRANCH: begin
	     op.type	  = INSN_BR;
	     valid	  = !STRICT_VALID || op.funct3[2:1] != 2'b01;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.imm	  = b_imm;
	     op.imm_pc    = 1'b1;
	  end

	  JALR: begin
	     op.type      = INSN_JAL;
	     valid        = 1'b1;
	     op.rs1_valid = 1'b1;
	     op.rd_e      = 1'b1;
	     op.imm	  = i_imm;
	  end

	  MISC_MEM: begin
	     op.type	  = INSN_NULL;

	     unique casez (op.funct3)
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
	     op.type      = INSN_JAL;
	     op.rd_e      = 1'b1;
	     op.imm       = j_imm;
	     op.imm_pc    = 1'b1;
	  end

	  OP: begin
	     op.type		= INSN_ALU;
	     op.rs1_valid	= 1'b1;
	     op.rs2_valid	= 1'b1;
	     op.rd_e		= 1'b1;
	  end

	  OP_IMM: begin
	     op.type		= INSN_ALU;
	     op.rs1_valid	= 1'b1;
	     op.rs2_valid	= 1'b0;
	     op.rd_e		= 1'b1;

	     // For the SLLI and SLAI opcodes, rs2 is a short immediate
	     // and funct7 is valid; for others, the full i immediate is
	     // used and funct7 is considered zero.
	     if (op.funct3[1:0] == 2'b01) begin
	       op.imm	  = op.rs2;
	     end else begin
		op.imm	  = i_imm;
	     end
	  end

	  SYSTEM: begin
	     op.rs1_valid = !op.funct3[2];
	     op.imm       = i_imm;
	     unique casez (op.funct3[1:0])
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
		  // ECALL, EBREAK
		  op.type = INSN_ECALL;
		  valid = !STRICT_VALID ||
			  (!i[31:21] && !op.rs1 && !op.funct3[2]);
	       end
	     endcase // unique casez (op.funct3[1:0])
	  end

	  AUIPC, LUI: begin
	     valid     = 1'b1;
	     op.type   = INSN_AGU;
	     op.rs1    = 5'b0;		// This becomes addend for LUI
	     op.rd_e   = 1'b1;
	     op.imm    = u_imm;
	     op.imm_u  = 1'b1;
	     op.imm_pc = ~i[5];		// 0 = LUI, 1 = AUIPC
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
	     op.imm    = 'bx;  op.imm_u      = 1'bx; op.imm_pc      = 1'bx;
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

   input	d_killed, // If downstream instructions are killed

   input	decoded_insn_t op_i,
   output	decoded_insn_t op_o,

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
	  logic	do_mult;

	  op_o	  = op_i;

	  do_mult = 1'b0;
	  is_mult = 1'b0;
	  is_mult =  op_i.type == INSN_ALU && op_i.rs2_valid &&
		     op_i.funct7 == 7'b000_0001 && !op_i.funct3[2];

	  if (is_mult)
	    begin
	       if (have_mult && !op_i.funct3[1:0] &&
		 op_i.rs1 == mult_rs1 && op_i.rs2 == mult_rs2) begin
		  // Can forward old multiply result
		  op_o.type = INSN_MULL;
	       end else begin
		  // Need to actually multiply
		  do_mult   = 1'b1;
		  op_o.type = INSN_MUL;
		  // Move the output to the M stage. Note that
		  // using op_i.rd_e here handles the case of rd == x0.
		  op_o.rd_m = op_i.rd_e;	  // Output in M stage
		  op_o.rd_e = 1'b0;
	       end
	    end // if (is_mult)

	  if (d_killed)
	    have_mult <= 1'b0;	// State rolled back
	  else if (is_mult)
	    have_mult <= rs1 != rd && rs2 != rd;
	  else if ((op_i.rd_e | op_i.rd_m) &&
		   (op_i.rd == mult_rs1 || op_i.rd == mult_rs2))
	    have_mult <= 1'b0;	// Input registers clobbered
       end // if (d_clken)
endmodule // decode_fast_mult

//
// Decoder pipeline stage
//

module decode #(
  parameter logic [31:0] PC_MASK = 32'hffff_fffe,
  parameter IRQ_VECTOR_BITS = 5
	    ) (
  input			      rst_n,
  input			      clk,
  input			      clken,

  input [31:0]		      d_din,		// From fetch stage
  input			      d_was_16,		// F decoded 16-bit instruction
  input			      d_pred_taken,	// F predicted taken branch
  input [31:0]		      d_pc,

  input			      d_valid_i,
  input			      d_stall,
  input			      d_killed,
  output		      d_valid_o,
  output		      d_busy,

  input			      d_irq,	// Inject interrupt strobe

  output		      decoded_insn_t d_op
			 );


   wire	d_clken = (d_valid_i | d_irq) & ~d_stall;

   assign d_busy    = d_irq;
   assign d_valid_o = d_clken & (d_valid_i | d_irq);

   decoded_insn_t c_op;		// decode_comb op out
   decoded_insn_t m_op;		// decode_fast_mult op out

   decode_comb comb (
     .d_din (d_din), .d_was_16(d_was_16), .d_pred_taken(d_pred_taken),
     .d_pc (d_pc & PC_MASK), .d_irq(d_irq), .op(c_op)
     );

   decode_fast_mult mult (
     .rst_n (rst_n), .clk(clk), .d_clken(d_clken), .d_killed(d_killed),
     .op_i(c_op), .op_o(m_op)
     );
endmodule
