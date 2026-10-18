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
   input [31:0]	d_din,		       // From fetch stage
   input	d_insn_16,	       // 16-bit instruction but not a fused pair!
   input [31:0]	d_pc,		       // PC of instruction
   input	mcontext_t d_mcontext, // Machine context of instruction
   input retstack_t d_retstack,	       // Return stack ptr for rollbacks

   output	decoded_insn_t op,
   output	d_pred_t d_pred
   );

   // Expand RV32C instructions if applicable
   // d_insn_16 doesn't necessarily match the opcode; it can be clear
   // for a fused pair, and set for an externally decoded 16-bit instruction.
   //
   // The only fused pair currently supported is a c.nop as the second
   // instruction, so it can safely be ignored.
   wire [31:0]	 i;
   wire		 is_16 = d_insn_16;

   rv32c_comb #(`CFG, .enabled(WITH_RVC & !EARLY_RVC)) rvc (.d(d_din), .q(i));

   // Immediate formats
   wire signed [31:0] i_imm = $signed(i[31:20]);
   wire signed [31:0] s_imm = $signed({i[31:25], i[11:7]});
   wire signed [31:0] b_imm = $signed({i[31], i[7], i[30:25], i[11:8], 1'b0});
   wire signed [31:0] j_imm = $signed({i[31], i[19:12], i[20], i[30:21], 1'b0});
   wire signed [31:0] u_imm = $signed({i[31:12], 12'b0});

   function automatic logic csr_is_indirect(logic [6:0] funct7);
      logic indirect;
      indirect = 1'b0;
      if (WITH_indcsr)
	indirect      = funct7 == 7'b1011_111; // Equivalent to CSR 0xBE0-0xBFF
      csr_is_indirect = indirect;
   endfunction

   always @(*)
     begin
	logic can_pred;

	op	     = 'bx;
	op.i16	     = is_16;
	op.mcontext  = d_mcontext;
	op.retstack  = d_retstack;

	op.undead    = 1'b1; // It is assumed to be a real instruction
	op.itype     = INSN_ERR;
	op.pc	     = d_pc & PC_MASK;
	op.pc_valid  = 1'b1;
	op.rd.r      = i[11:7];
	op.rd.c      = op.mcontext.m;
	op.rd_e      = 1'b0;
	op.rd_m      = 1'b0;
	op.rs1.r     = i[19:15];
	op.rs1.c     = op.mcontext.m;
	op.rs1_valid = 1'b0;
	op.rs2.r     = i[24:20];
	op.rs2.c     = op.mcontext.m;
	op.rs2_valid = 1'b0;
	op.imm	     = 'bx;
	op.lrsc      = 1'b0;
	op.csrw      = 1'b0;
	op.csrr      = 1'b0;

	op.funct7    = i[31:25];
	op.funct3    = i[14:12];

	can_pred     = 1'b0;

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
	     if (!STRICT_UNDEFINED || op.funct3 <= 3'b010)
	       op.itype   = INSN_ST;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.imm	  = s_imm;
	  end

	  AMO: begin
	     if (WITH_Zalrsc) begin
		if (!STRICT_UNDEFINED ||
		  (op.funct7[6:3] == 4'b0001 & op.funct7[1:0] == 2'b11 &
		   op.funct3 == 3'b010 & (op.funct7[2] | !op.rd.r))) begin
		   op.imm          = 'b0;
		   op.rs1_valid    = 1'b1;
		   op.lrsc         = 1'b1;
		   if (op.funct7[2]) begin
		      op.itype	   = INSN_ST;
		      op.rs2_valid = 1'b1;
		      op.rd_e	   = 1'b1;
		   end else begin
		      op.itype	   = INSN_LD;
		      op.rs2_valid = 1'b0;
		      op.rd_m	   = 1'b1;
		   end
		end
	     end
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
	     op.itype     = INSN_JAL;
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
	       op.itype = INSN_MUL;
	  end

	  SYSTEM: begin
	     op.imm       = i_imm;
	     unique casez ({op.funct7, op.funct3})
	       10'b???????_?01: begin	// CSRRW[I]
		  op.itype     = INSN_CSR;
		  op.rd_e      = 1'b1;
		  op.csrr      = |op.rd.r;
		  op.csrw      = 1'b1;
		  op.rs1_valid = ~op.funct3[2];
		  op.rs2_valid = csr_is_indirect(op.funct7);
	       end
	       10'b???????_?1?: begin	// CSRR[SC][I]
		  op.itype     = INSN_CSR;
		  op.rd_e      = 1'b1;
		  op.csrr      = 1'b1;
		  op.csrw      = |op.rs1.r;
		  op.rs1_valid = ~op.funct3[2];
		  op.rs2_valid = csr_is_indirect(op.funct7);
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
	     op.rs1.r  = 5'b0; // rs1 = immediate 0
	     op.rd_e   = 1'b1;
	     op.imm    = op.pc + u_imm;
	     can_pred  = 1'b1;
	  end

	  LUI: begin
	     op.itype  = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rs1.r  = 5'b0; // rs1 = immediate 0
	     op.rd_e   = 1'b1;
	     op.imm    = u_imm;
	     can_pred  = 1'b1;
	  end

	  // CUSTOM0 is CUSTOM1 as OP_IMM is to OP
	  CUSTOM0, CUSTOM1: begin
	     logic [4:0] altcontext;
	     
	     op.itype 	  = INSN_XALU;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = i[5];
	     op.rd_e 	  = 1'b1;
	     op.imm 	  = i_imm;

	     altcontext   = op.mcontext.u;
	     if (op.rs2_valid & i[31])
	       altcontext = i[29:25] & CTX_MASK;
	     
	     unique casez (op.funct3)
	       3'b0?0: begin	// .xu, .xc
		  		// funct3 == 010 not currently used
		  op.rs1.c  = altcontext;
	       end
	       3'b0?1: begin	// .ux, .cx, .su, .sc
		  op.rd.c   = altcontext;
	       end
	       default: begin
		  // Nothing special here
	       end
	     endcase
	  end

	  default: begin
	     // Undefined major opcode
	  end
	endcase // unique case (i[6:0])

	// x0 can never be written, and always is zero (effectively
	// an immediate.) This enforces that constraint.
	if (!op.rd.r) begin
	   op.rd_e  = 1'b0;
	   op.rd_m  = 1'b0;
	   can_pred = 1'b0;
	end

	if (can_pred) begin
	   d_pred.rnum = op.rd.r;
	   d_pred.imm  = op.imm;
	end else begin
	   d_pred.rnum = 5'b0;
	   d_pred.imm  = 32'b0;
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
   //
   // This takes advantage of the fact that .xu and .ux are not supported
   // for MUL, so in many cases it is only necessary to compare the
   // architectural register numbers.
   typedef struct packed {
      logic	  valid;
      rcontext_t  ctx;
      logic [4:0] rs1;
      logic [4:0] rs2;
      logic [1:0] hifunc;
   } multinfo_t;

   multinfo_t mult_invalid = { 1'b0, CTX_X, 5'bx, 5'bx, 2'bx };
   multinfo_t mult;
   logic [1:0]	mulhifunc_c;

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
      end else if (op_o.itype == INSN_MUL) begin
	 // Multiply cache handling handling
	 logic is_mull;
	 is_mull = !op_i.funct3[1:0];
	 if (FORWARD_MUL && mult.valid && mult.ctx == op_i.mcontext.m &&
	   (is_mull || op_i.funct3[1:0] == mult.hifunc) &&
           op_i.rs1.r == mult.rs1 && op_i.rs2.r == mult.rs2) begin
	    // Can forward old multiply low result
	    mulhifunc_c = mult.hifunc;	  // Not actually doing the multiply
	 end else begin
	    // Move the output to the M stage. Note that
	    // using op_i.rd_e here handles the case of rd == x0.
	    op_o.rd_m	= op_i.rd_e;	  // Output in M stage
	    op_o.rd_e	= 1'b0;
	    // For MUL, speculatively cache an unsigned result
	    // (MULHU seems to be the most common form of MULH.)
	    mulhifunc_c = is_mull ? 2'b11 : op_i.funct3[1:0];
	 end
      end
   end

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	mult <= mult_invalid;
     end else if (d_clken) begin
	if (FORWARD_MUL) begin
	   if (d_killed) begin
	      // State rolled back
	      mult <= mult_invalid;
	   end else if (op_o.itype == INSN_MUL) begin
	      if (op_o.rd.r != op_o.rs1.r && op_o.rd.r != op_o.rs2.r) begin
		 mult.valid  <= 1'b1;
		 mult.ctx    <= op_o.mcontext.m;
		 mult.rs1    <= op_o.rs1.r;
		 mult.rs2    <= op_o.rs2.r;
		 mult.hifunc <= mulhifunc_c;
	      end else begin
		 mult <= mult_invalid;
	      end
	   end else if ((op_o.rd_e | op_o.rd_m) &&
	     (op_o.rd.c == mult.ctx) &&
	     (op_o.rd.r == mult.rs1 || op_o.rd.r == mult.rs2)) begin
	      // Input registers clobbered
	      mult <= mult_invalid;
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

  input [31:0] d_din,	  // From fetch stage
  input	       d_insn_16, // 16-bit instruction packet
  input [31:0] d_pc,
  input	       mcontext_t d_mcontext,
  input	       retstack_t d_retstack,

  input	       d_valid_i,
  input	       d_stall,
  input	       d_killed,
  output       d_valid_o,
  output       d_busy,

  output       decoded_insn_t d_op,
  output       d_pred_t d_pred
);

   wire			      d_clken;

   assign d_busy    = 1'b0;
   assign d_clken   = clken & (d_busy | (d_valid_i & ~d_stall));
   assign d_valid_o = d_valid_i & ~d_killed & ~d_busy;

   decoded_insn_t c_op;		// decode_comb op out

   // Purely combinatorial decode
   decode_comb #(`CFG) comb (
     .d_din (d_din), .d_insn_16(d_insn_16),
     .d_pc (d_pc & PC_MASK), .d_mcontext(d_mcontext), .d_retstack(d_retstack),
     .op(c_op), .d_pred (d_pred)
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
      rs1.c = mc.m;
      rs2.c = mc.m;

      priority casez ({insn[15:13], insn[1:0]})
	5'b???_11: begin		// 32-bit instruction
	   rs1.r = insn[19:15];
	   rs2.r = insn[24:20];
	   unique casez ({insn[31], insn[14:12], insn[6:0]})
	     { 1'b?, 3'b000, CUSTOM0 },
	     { 1'b0, 3'b000, CUSTOM1 }: begin
		rs1.c = mc.u;			// .xu instruction
	     end
	     { 1'b1, 3'b000, CUSTOM1 }: begin
		rs1.c = insn[29:25] & CTX_MASK; // .xc instruction
	     end

	     // .ux, .cx, .su and .sc don't have to be considered, because
	     // rd is not begin decoded here.
	     default: begin
		// Default contexts
	     end
	   endcase
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
   end
endmodule
