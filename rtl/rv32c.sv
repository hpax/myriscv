//
// RV32C decoder
//
// Converts compressed RV32 instructions to their long forms.
//
// Some instructions which have no obvious long form are re-encoded
// as 32-bit instructions with bits [1:0] != 2'b11, but with at least
// an attempt at expanding relative fields.
//

`include "myriscv.vh"

module rv32c_comb #(`CONFIG,
		    parameter logic [31:0] INVALID = { 31'bx, 1'b0 },
		    parameter bit	  MATCH_BINUTILS = 1'b0
		    )
   (
    input [31:0]  d, // Input; [31:16] used only for passthrough
    output [31:0] q
    );


   localparam [4:0] R_ZERO = 5'd0;
   localparam [4:0] R_RA   = 5'd1;
   localparam [4:0] R_SP   = 5'd2;

   function [31:0] insn_i (input [4:0]         rd,
			   input [4:0]	       rs1,
			   input signed [11:0] imm,
			   input [2:0]	       funct3,
			   op_t                base_op);
      insn_i = { imm, rs1, funct3, rd, base_op };
   endfunction // insn_i

   function [31:0] insn_r (input [4:0] rd,
			   input [4:0] rs1,
			   input [4:0] rs2,
			   input [6:0] funct7,
			   input [2:0] funct3,
			   op_t        base_op);
      insn_r = { funct7, rs2, rs1, funct3, rd, base_op };
   endfunction

   function [31:0] insn_s (input [4:0]         rs1,
			   input [4:0]         rs2,
			   input signed [11:0] imm,
			   input [2:0]         funct3,
			   op_t                base_op);
      insn_s = { imm[11:5], rs2, rs1, funct3, imm[4:0], base_op };
   endfunction // insn_s

   function [31:0] insn_b (input [4:0]         rs1,
			   input [4:0]         rs2,
			   input signed [12:0] imm,
			   input [2:0]         funct3,
			   op_t                base_op);
      insn_b = { imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], base_op };
   endfunction // insn_b

   function [31:0] insn_u (input[4:0]          rd,
			   input signed [19:0] imm,
			   op_t                base_op);
      insn_u = { imm, rd, base_op };
   endfunction // insn_u

   function [31:0] jal (input [4:0] rd,
			input signed [20:0] imm);
      jal = { imm[20], imm[10:1], imm[11], imm[19:12], rd, JAL };
   endfunction // jal

   function [31:0] addi (input [4:0]         rd,
			 input [4:0]	     rs1,
			 input signed [11:0] imm);
      addi = insn_i(rd, rs1, imm, 3'b000, OP_IMM);
   endfunction // addi

   function [31:0] andi (input [4:0]         rd,
			 input [4:0]	     rs1,
			 input signed [11:0] imm);
      andi = insn_i(rd, rs1, imm, 3'b111, OP_IMM);
   endfunction // andi

   wire [31:0]	    i = d;
   logic [31:0]	    o;
   assign q = o;

   wire [4:0]	    p1 = { 2'b01, i[9:7] }; // rs1'/rd'
   wire [4:0]	    p2 = { 2'b01, i[4:2] }; // rs2'/rd'
   wire [4:0]	    r1 = i[11:7];	    // rs1/rd
   wire [4:0]	    r2 = i[6:2];	    // rs2/rd

   always @(*)
     begin
	logic signed [5:0] ci_imm;

	ci_imm = { i[12], i[6:2] };
	o = INVALID;

	unique case (i[1:0])
	  2'b11: begin
	     // Not a compressed instruction
	     o = i;
	  end

	  2'b00: begin
	     unique case (i[15:13])
	       3'b000:		// C.ADDI4SPN or invalid
		 if (i[12:5])
		   o = addi(p2, R_SP,
			    {2'b00, i[10:7], i[12:11], i[5], i[6], 2'b00});

	       3'b001:		// C.FLD
		 if (WITH_Zcd)
		   o = insn_i(p2, p1, {i[6:5], i[12:10], 3'b0}, 3'b011, LOAD_FP);

	       3'b010:		// C.LW
		 o = insn_i(p2, p1, {i[5], i[12:10], i[6], 2'b0}, 3'b010, LOAD);

	       3'b011:		// C.FLW
		 if (WITH_Zcf)
		   o = insn_i(p2, p1, {i[5], i[12:10], i[6], 2'b0}, 3'b010, LOAD_FP);

	       3'b100: begin
		  unique casez ({i[12:10], i[6]})
		    4'b000_?:	// C.LBU
		      if (WITH_Zcb)
			o = insn_i(p2, p1, {i[5], i[6]}, 3'b100, LOAD);
		    4'b001_?:	// C.LHU, C.LH
		      if (WITH_Zcb)
			o = insn_i(p2, p1, {i[5], 1'b0}, {~i[6], 2'b01}, LOAD);
		    4'b010_?:	// C.SB
		      if (WITH_Zcb)
			o = insn_s(p1, p2, {i[5], i[6]}, 3'b000, STORE);
		    4'b011_0:	// C.SH
		      if (WITH_Zcb)
			o = insn_s(p1, p2, {i[5], 1'b0}, 3'b001, STORE);
		    default:
		      o = INVALID;
		  endcase
	       end

	       3'b101:		// C.FSD
		 if (WITH_Zcd)
		   o = insn_s(p1, p2, {i[6:5], i[12:10], 3'b0}, 3'b011, STORE_FP);

	       3'b110:		// C.SW
		 o = insn_s(p1, p2, {i[5], i[12:10], i[6], 2'b0}, 3'b010, STORE);

	       3'b111:		// C.FSW
		 if (WITH_Zcf)
		   o = insn_s(p1, p2, {i[5], i[12:10], i[6], 2'b0}, 3'b010, STORE_FP);

	       default: o = 32'bx; // For simulation
	     endcase // unique case (i[15:13])
	  end // case: 2'b00

	  2'b01: begin
	     unique casez (i[15:13])
	       3'b000:		// C.ADDI (incl C.NOP)
		 o = addi(r1, r1, ci_imm);

	       3'b?01: begin	// C.J[AL]
		  logic signed [11:0]  cj_imm;
		  cj_imm[0]     = 1'b0;
		  cj_imm[5]     = i[2];
		  cj_imm[3:1]   = i[5:3];
		  cj_imm[7]     = i[6];
		  cj_imm[6]     = i[7];
		  cj_imm[10]    = i[8];
		  cj_imm[9:8]   = i[10:9];
		  cj_imm[4]     = i[11];
		  cj_imm[11]    = i[12];
		  // rd: x0 (zero) for J, x1 (ra) for JAL
		  o = jal({4'b0, ~i[15]}, cj_imm);
	       end

	       3'b010:	// C.LI
		 o = addi(r1, R_ZERO, ci_imm);

	       3'b011: begin
		  if (r1 == R_SP)
		    begin
		       // C.ADDI16SP
		       logic signed [9:0] addi16sp_imm;
		       addi16sp_imm = {i[12], i[4:3], i[5], i[2], i[6], 4'b0};
		       if (!STRICT_UNDEFINED || MATCH_BINUTILS || ci_imm)
			 o = addi(R_SP, R_SP, addi16sp_imm);
		    end
		  else
		    begin
		       // C.LUI
		       if (!STRICT_UNDEFINED || ci_imm)
			 o = insn_u(r1, ci_imm, LUI);
		    end
	       end

	       3'b100: begin	// Arithmetic
		  o = INVALID;
		  unique casez ({i[12:10], i[6:5]})
		    5'b?_0?_??:	// C.SRLI, C.SRAI (including 63-32)
		      o = insn_i(p1, p1,  {1'b0, i[10], 4'b0, ci_imm}, 3'b101, OP_IMM);
		    5'b?_10_??:	// C.ANDI
		      o = andi(p1, p1, ci_imm);
		    5'b0_11_00:	// C.SUB
		      o = insn_r(p1, p1, p2, 7'b0100000, 3'b000, OP);
		    5'b0_11_01:	// C.XOR
		      o = insn_r(p1, p1, p2, 7'b0000000, 3'b100, OP);
		    5'b0_11_10: // C.OR
		      o = insn_r(p1, p1, p2, 7'b0000000, 3'b110, OP);
		    5'b0_11_11: // C.AND
		      o = insn_r(p1, p1, p2, 7'b0000000, 3'b111, OP);
		    5'b1_11_10:	// C.MUL
		      if (WITH_Zcb && WITH_Zmmul)
			o = insn_r(p1, p1, p2, 7'b0000001, 3'b000, OP);
		    5'b1_11_11:
		      if (WITH_Zcb)
			unique casez (i[4:2])
			  3'b000: // C.ZEXT.B
			    o = andi(p1, p1, 8'hff);
			  3'b001: // C.SEXT.B (-> SEXT.B from Zbb)
			    if (WITH_Zbb)
			      o = insn_i(p1, p1, 12'b0110000_00100, 3'b001, OP_IMM);
			  3'b010: // C.ZEXT.H (-> ZEXT.H from Zbb)
			    if (WITH_Zbb)
			      o = insn_i(p1, p1, 12'b0000100_00000, 3'b100, OP);
			  3'b011: // C.SEXT.H (-> SEXT.H from Zbb)
			    if (WITH_Zbb)
			      o = insn_i(p1, p1, 12'b0110000_00101, 3'b001, OP_IMM);
			  3'b101: // C.NOT
			    o = insn_i(p1, p1, ~12'sb0, 3'b100, OP_IMM);
			  default:
			    o = INVALID;
			endcase // unique casez (i[4:2])
		    default:
		      o = INVALID;
		  endcase
	       end

	       3'b11?:		// C.BEQZ, C.BNEZ
		 o = insn_b(p1, R_ZERO,
			    $signed({i[12], i[6:5], i[2], i[11:10], i[4:3], 1'b0}),
			    {2'b00, i[13]}, BRANCH);

	       default: o = 32'bx; // For simulation
	     endcase // unique casez (i[15:13])
	  end // case: 2'b10

	  2'b10: begin
	     unique case (i[15:13])
	       3'b000:	// C.SLLI (including 63-32)
		 o = insn_i(r1, r1, {6'b0, ci_imm}, 3'b001, OP_IMM);
	       3'b001:	// C.FLDSP
		 if (WITH_Zcd)
		   o = insn_i(r1, R_SP, {i[4:2], i[12], i[6:5], 3'b0}, 3'b011, LOAD_FP);
	       3'b010:	// C.LWSP
		 if (!STRICT_UNDEFINED || r1)
		   o = insn_i(r1, R_SP, {i[3:2], i[12], i[6:4], 2'b0}, 3'b010, LOAD);
	       3'b011:	// C.FLWSP
		 if (WITH_Zcd)
		   o = insn_i(r1, R_SP, {i[3:2], i[12], i[6:4], 2'b0}, 3'b010, LOAD_FP);

	       3'b100:
		 if (!r2)
		   if (!r1)	// C.ECALL, C.EBREAK
		     begin
			// C.ECALL is not officially defined
			if (!STRICT_UNDEFINED || i[12])
			  o = insn_i(R_ZERO, R_ZERO, i[12], 3'b000, SYSTEM);
		     end
		   else		// C.JR, C.JALR
		     o = insn_i({4'b0, i[12]}, r1, 'b0, 3'b000, JALR);
		 else		// C.MV/C.ADD
		   o = insn_r(r1, r1 & {5{i[12]}}, r2, 7'b0000000, 3'b000, OP);

	       3'b101:	// C.FSDSP
		 if (WITH_Zcd)
		   o = insn_s(R_SP, r2, {i[9:7], i[12:10], 3'b0}, 3'b011, STORE_FP);
	       3'b110:	// C.SWSP
		 o = insn_s(R_SP, r2, {i[8:7], i[12:9], 2'b0}, 3'b010, STORE);
	       3'b111:	// C.FLWSP
		 if (WITH_Zcd)
		   o = insn_s(R_SP, r2, {i[8:7], i[12:9], 2'b0}, 3'b010, STORE_FP);

	       default: o = 32'bx; // For simulation
	     endcase
	  end // case: 2'b10

	  default: o = 32'bx; // For simulation
	endcase // unique case (i[1:0])
     end
endmodule // rv32c_comb
