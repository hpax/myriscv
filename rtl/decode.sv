//
// RISC-V instruction decode
//
// This decodes 32-bit instructions. 16-bit instructions are transcoded by
// the combinatorial logic in the rv32c_comb module (rv32c.sv); this can be
// done in this pipeline stage or another one.
//

`include "myriscv.vh"

// Combinatorial decoder
module decode_comb #(`CONFIG)
  (
   input [31:0]	d_din,		// From fetch stage
   input	d_insn_16,	// 16-bit instruction but not a fused pair!
   input	d_pred_taken,	// Control transfer predicted taken
   input [31:0]	d_pc,		// PC of instruction
   input mcontext_t d_mcontext,	// Machine context of instruction

   output	decoded_insn_t op
   );

   // Expand RV32C instructions if applicable
   // d_insn_16 doesn't necessarily match the opcode; it can be clear
   // for a fused pair, and set for an externally decoded 16-bit instruction.
   //
   // The only fused pair currently supported is a c.nop as the second
   // instruction, so it can safely be ignored.
   wire [31:0]	 i;
   wire [31:0]	 cinst;
   wire		 is_16 = d_insn_16;

   rv32c_comb #(`CFG) rvc (.d(d_din), .q(cinst));
   assign i = EARLY_RVC ? d_din : cinst;

   // Immediate formats
   wire signed [31:0] i_imm = $signed(i[31:20]);
   wire signed [31:0] s_imm = $signed({i[31:25], i[11:7]});
   wire signed [31:0] b_imm = $signed({i[31], i[7], i[30:25], i[11:8], 1'b0});
   wire signed [31:0] j_imm = $signed({i[31], i[19:12], i[20], i[30:21], 1'b0});
   wire signed [31:0] u_imm = $signed({i[31:12], 12'b0});

   always @(*)
     begin
	op	      = 'bx;
	op.i16	      = is_16;
	op.mcontext   = d_mcontext;

	op.undead     = 1'b1;	// It is assumed to be a real instruction
	op.itype      = INSN_ERR;
	op.pc	      = d_pc & PC_MASK;
	op.pc_valid   = 1'b1;
	op.rd.r       = i[11:7];
	op.rd.c       = op.mcontext.m;
	op.rd_e       = 1'b0;
	op.rd_m       = 1'b0;
	op.rs1.r      = i[19:15];
	op.rs1.c      = op.mcontext.m;
	op.rs1_valid  = 1'b0;
	op.rs2.r      = i[24:20];
	op.rs2.c      = op.mcontext.m;
	op.rs2_valid  = 1'b0;
	op.imm	      = 'bx;
	op.csrw       = 1'b0;
	op.csrr       = 1'b0;
	op.pred_taken = d_pred_taken;

	op.funct7     = i[31:25];
	op.funct3     = i[14:12];

	unique case (i[6:0])
	  LOAD: begin
	     if (!STRICT_UNDEFINED
	       || (op.funct3 != 3'b011 && op.funct3[2:1] != 2'b11))
	       op.itype      = INSN_LD;

	     op.rd_m	     = 1'b1;
	     op.rs1_valid    = 1'b1;
	     op.imm	     = i_imm;
	  end

	  STORE: begin
	     if (op.funct3 <= 3'b010)
	       op.itype      = INSN_ST;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.imm       = s_imm;
	  end

	  BRANCH: begin
	     if (!STRICT_UNDEFINED || WITH_cmpand ||
		 op.funct3[2:1] != 2'b01)
	       op.itype	  = INSN_BR;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.imm	  = op.pc + b_imm;
	  end

	  JALR: begin
	     op.itype      = INSN_JAL;
	     op.rs1_valid = 1'b1;
	     op.rd_e      = 1'b1;
	     op.imm	  = i_imm;
	  end

	  MISC_MEM: begin
	     op.imm = 32'bx;
	     unique casez (op.funct3)
	       3'b000: begin	// FENCE/PAUSE
		  op.itype = INSN_NOP;	// Treat as NOP
	       end
	       3'b001: begin	// FENCE.I (Zifencei)
		  op.itype = INSN_FENCEI;
	       end
	       3'b010: begin	// Cache block operations
		  // Treat this as a store-format instruction (which means
		  // permitting an address offset as an extension.)
		  // rs2.r contains the actual cache operation.
		  op.itype	= INSN_CBO;
		  op.imm	= s_imm;
		  op.rs1_valid	= 1'b1;
	       end default: begin
		  op.itype = INSN_ERR;
	       end
	     endcase
	  end

	  JAL: begin
	     op.itype     = INSN_JAL;
	     op.rd_e      = 1'b1;
	     op.imm       = op.pc + j_imm;
	  end

	  OP, OP_IMM: begin
	     op.itype			  = INSN_ALU;
	     op.rs1_valid		  = 1'b1;
	     op.rs2_valid		  = i[5];
	     op.rd_e			  = 1'b1;
	     op.imm			  = i_imm;

	     if (WITH_Zmmul &&
	       op.rs2_valid && op.funct7 == 7'b000_0001 && ~op.funct3[2])
	       if (|op.funct3[1:0])
		 op.itype = INSN_MULH;
	       else
		 op.itype = INSN_MULL;
	  end

	  SYSTEM: begin
	     op.imm       = i_imm;
	     unique casez ({op.funct7, op.funct3})
	       10'b???????_?01: begin	// CSRRW[I]
		  op.itype = INSN_CSR;
		  op.rd_e = 1'b1;
		  op.csrr = |op.rd.r;
		  op.csrw = 1'b1;
		  op.rs1_valid = ~op.funct3[2];
	       end
	       10'b???????_?1?: begin	// CSRR[SC][I]
		  op.itype = INSN_CSR;
		  op.rd_e = 1'b1;
		  op.csrr = 1'b1;
		  op.csrw = |op.rs1.r;
		  op.rs1_valid = ~op.funct3[2];
	       end
	       10'b0000000_000: begin		// ECALL, EBREAK
		  if (!STRICT_UNDEFINED ||
		      (!op.rs2.r[4:1] && !op.rs1.r && !op.rd.r))
		    op.itype = INSN_ECALL;
	       end
	       10'b0011000_000:	begin		// MRET
		  if (!STRICT_UNDEFINED ||
		      (!op.rs2.r == 5'b00010 && !op.rs1.r && !op.rd.r))
		    op.itype = INSN_MRET;
	       end
	       default: begin
		  // Error
	       end
	     endcase // unique casez ({op.funct7, op_funct3})
	  end

	  AUIPC: begin
	     op.itype  = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rs1.r  = 5'b0;	// rs1 = immediate 0
	     op.rd_e   = 1'b1;
	     op.imm    = op.pc + u_imm;
	  end

	  LUI: begin
	     op.itype  = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rs1.r  = 5'b0;	// rs1 = immediate 0
	     op.rd_e   = 1'b1;
	     op.imm    = u_imm;
	  end

	  // CUSTOM0 is CUSTOM1 as OP_IMM is to OP
	  CUSTOM0, CUSTOM1: begin
	     op.itype		= INSN_ALU;
	     op.rs1_valid	= 1'b1;
	     op.rs2_valid	= i[5];
	     op.rd_e		= 1'b1;
	     op.imm		= i_imm;

	     unique casez (op.funct3)
		3'b000: begin	// add.xu
		   op.itype  = INSN_ALU;
		   op.funct3 = ALU_ADD;
		   op.rs1.c  = op.mcontext.u;
		end
	       3'b001: begin	// add.ux
		  op.itype   = INSN_ALU;
		  op.funct3  = ALU_ADD;
		  op.rd.c    = op.mcontext.u;
	       end
	       default: begin
		  // Error
	       end
	     endcase
	  end

	  default: begin
	     // Error
	  end
	endcase // unique case (i[6:0])

	// x0 can never be written, and always is zero (effectively
	// an immediate.) This enforces that constraint.
	if (!op.rd.r)
	  begin
	     op.rd_e = 1'b0;
	     op.rd_m = 1'b0;
	  end

	// For the benefit of the fast register decoder, squash reading
	// rs1 if it is zero. It is not safe to do the same for rs2, without
	// introducing additional logic, as there are cases where
	// rs2 can be valid (including being x0) and there also is an
	// immediate, which would be muxed into src2. If !rs1_valid, however,
	// rs1 *itself* is the immediate, and therefore zero.
	if (!op.rs1.r)
	  op.rs1_valid = 1'b0;

	// Give the synthesizer a bit more flexibility
	if (op.itype == INSN_ERR)
	  op = err_op(op.pc, op.i16, op.mcontext);
     end // always @ (*)
endmodule

module decode_seq #(`CONFIG)
  (
   input  rst_n,
   input  clk,
   input  d_clken,

   input  d_valid_i,
   input  d_killed, // If downstream instructions are killed

   input  decoded_insn_t op_i,
   output decoded_insn_t op_o // Adjusted operation
);
   // D stage fast multiply watcher. Looks for a multiply that
   // can safely use the result of a previous multiply; this is
   // allows MULH* to forward the low half of the result to MUL in
   // the E stage rather than M stage.
   reg		have_mult;
   regnum_t	mult_rs1;
   regnum_t	mult_rs2;
   reg [1:0]	mulhifunc;
   logic [1:0]	mulhifunc_c;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	  have_mult <= 1'b0;
	  mult_rs1  <= 'bx;
	  mult_rs2  <= 'bx;
	  mulhifunc <= 2'bx;
     end else if (d_clken) begin
	if (FORWARD_MUL) begin
	   if (d_killed) begin
	      // State rolled back
	      have_mult <= 1'b0;
	      mult_rs1  <= 'bx;
	      mult_rs2  <= 'bx;
	      mulhifunc <= 2'bx;
	   end else if (insn_mult(op_o.itype)) begin
	      if (op_o.rd != op_o.rs1 && op_o.rd != op_o.rs2) begin
		 have_mult <= 1'b1;
		 mult_rs1  <= op_o.rs1;
		 mult_rs2  <= op_o.rs2;
		 mulhifunc <= mulhifunc_c;
	      end else begin
		 have_mult <= 1'b0;
		 mult_rs1  <= 'bx;
		 mult_rs2  <= 'bx;
		 mulhifunc <= 2'bx;
	      end
	   end else if ((op_o.rd_e | op_o.rd_m) &&
	     (op_o.rd == mult_rs1 || op_o.rd == mult_rs2)) begin
	      // Input registers clobbered
	      have_mult <= 1'b0;
	      mult_rs1  <= 'bx;
	      mult_rs2  <= 'bx;
	      mulhifunc <= 2'bx;
	   end
	end
     end

   always @(*) begin
      op_o = op_i;
      mulhifunc_c = 2'bx;

      // Killed instruction
      if (d_killed) begin
	 op_o.undead   = 1'b0;
	 op_o.pc_valid = 1'b0;
	 op_o.rd_e     = 1'b0;
	 op_o.rd_m     = 1'b0;
      end else if (!d_valid_i) begin
	 op_o.undead = 1'b0;
	 op_o.rd_e   = 1'b0;
	 op_o.rd_m   = 1'b0;
      end else if (insn_mult(op_o.itype)) begin
	 // MUL -> MULH (default to assuming signed)
	 // Multiply handling
	 if (FORWARD_MUL &&
	   have_mult && (!op_i.funct3[1:0] || op_i.funct3[1:0] == mulhifunc) &&
	   op_i.rs1 == mult_rs1 && op_i.rs2 == mult_rs2) begin
	    // Can forward old multiply low result
	    mulhifunc_c = mulhifunc; // Not actually doing the multiply
	 end else begin
	    // Move the output to the M stage. Note that
	    // using op_i.rd_e here handles the case of rd == x0.
	    op_o.rd_m	= op_i.rd_e;	  // Output in M stage
	    op_o.rd_e	= 1'b0;
	    // For MUL, cache a signed result
	    mulhifunc_c = { op_i.funct3[1], op_i.funct3[0] | ~op_i.funct3[1] };
	 end
      end
   end
endmodule // decode_seq

//
// Decoder pipeline stage
//
module decode #(`CONFIG)
(
  input	       rst_n,
  input	       clk,
  input	       clken,

  input [31:0] d_din, // From fetch stage
  input	       d_insn_16, // 16-bit instruction packet
  input	       d_pred_taken, // F predicted taken branch
  input [31:0] d_pc,
  input	       mcontext_t d_mcontext,

  input	       d_valid_i,
  input	       d_stall,
  input	       d_killed,
  output       d_valid_o,
  output       d_busy,

  output       decoded_insn_t d_op
			 );

   wire			      d_clken;

   assign d_busy    = 1'b0;
   assign d_clken   = clken & (d_busy | (d_valid_i & ~d_stall));
   assign d_valid_o = d_valid_i & ~d_killed & ~d_busy;

   decoded_insn_t c_op;		// decode_comb op out

   // Purely combinatorial decode
   decode_comb #(`CFG) comb (
     .d_din (d_din), .d_insn_16(d_insn_16), .d_pred_taken(d_pred_taken),
     .d_pc (d_pc & PC_MASK), .d_mcontext(d_mcontext), .op(c_op)
     );

   // Additional, sequence-dependent
   decode_seq #(`CFG) seq (
     .rst_n (rst_n), .clk(clk), .d_clken(d_clken), .d_killed(d_killed),
     .d_valid_i (d_valid_i), .op_i(c_op), .op_o(d_op)
     );
endmodule

//
// Quickly extract *possible* source registers for an instruction; this
// allows the register file lookup to be done without having to
// parse the entire instruction.
//
// This is combinatorial, and should be kept as small as possible.
// For RVC instructions, this is allowed to put a value in rs1 that
// ought to be zero (for C.LI and C.MV), but *not* rs2!
//
module decode_srcregs #(`CONFIG)
(
  input [31:0] insn,
  input	       mcontext_t mc,
  output       regnum_t rs1,
  output       regnum_t rs2
  );

   localparam [4:0] R_ZERO = 5'd0;
   localparam [4:0] R_RA   = 5'd1;
   localparam [4:0] R_SP   = 5'd2;

   always @(*) begin
      priority casez ({insn[15:13], insn[1:0]})
	5'b???_11: begin		// 32-bit instruction
	   rs1.r = insn[19:15];
	   rs2.r = insn[24:20];
	end
	5'b000_00: begin		// C.ADDI4SPN
	   rs1.r = R_SP;
	   rs2.r = 5'bx;
	end
	5'b???_00: begin		// RVC quadrant 0, memory references
	   rs1.r = { 2'b01, insn[9:7] };
	   rs2.r = { 2'b01, insn[4:2] };
	end
	5'b0??_01: begin		// RVC quadrant 1, lower half
	   rs1.r = insn[11:7];
	   rs2.r = { 2'b01, insn[4:2] };
	end
	5'b10?_01: begin		// RVC quadrant 1.2
	   rs1.r = { 2'b01, insn[9:7] };
	   rs2.r = { 2'b01, insn[4:2] };
	end
	5'b11?_01: begin		// RVC quadrant 1.3 (branch)
	   rs1.r = { 2'b01, insn[9:7] };
	   rs2.r = R_ZERO;
	end
	5'b?00_10: begin		// RVC quadrant 2, non-SP
	   rs1.r = insn[11:7];
	   rs2.r = insn[6:2];
	end
	5'b???_10: begin		// RVC quadrant 2, SP memory references
	   rs1.r = R_SP;
	   rs2.r = insn[6:2];
	end
	default: begin
	   rs1.r = 5'bx;
	   rs2.r = 5'bx;
	end
      endcase // priority casez ({insn[15:13], insn[1:0]})

      priority casez ({insn[14:12], insn[6:0]})
	10'b000_0?01011:	// add.xu
	  rs1.c = mc.u;
	default:
	  rs1.c = mc.m;
      endcase // priority casez ({insn[14:12], insn[6:0]})

      rs2.c = mc.m;
   end

   // add.ux doesn't have to be considered, because
   // rd is not begin decoded here.
endmodule
