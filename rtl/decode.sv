//
// RISC-V instruction decode
//
// This decodes 32-bit instructions. 16-bit instructions are transcoded by
// the combinatorial logic in the rv32c_comb module (rv32c.sv); this can be
// done in this pipeline stage or another one.
//

`include "myriscv.vh"

// Combinatorial decoder
module decode_comb
  #(
    parameter bit DECODE_C       = 1'b1	 // Set to 0 if not desired *OR* done before this logic.
    )
  (
   input [31:0]	d_din,		// From fetch stage
   input	d_insn_16,	// 16-bit instruction but not a fused pair!
   input	d_pred_taken,
   input [31:0]	d_pc,

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

   rv32c_comb rv32c (.d(d_din), .q(cinst));
   assign i = DECODE_C ? cinst : d_din;

   // Immediate formats
   wire signed [11:0] i_imm = i[31:20];
   wire signed [11:0] s_imm = { i[31:25], i[11:7] };
   wire signed [12:0] b_imm = { i[31], i[7], i[30:25], i[11:8], 1'b0 };
   wire signed [20:0] j_imm = { i[31], i[19:12], i[20], i[30:21], 1'b0 };
   wire signed [31:0] u_imm = { i[31:12], 12'b0 };

   wire [`CONTEXT_BITS-1:0] default_context = 'b0;

   always @(*)
     begin
	op	      = 'bx;
	op.i16        = is_16;

	op.itype      = INSN_ERR;
	op.pc	      = d_pc & core.PC_MASK;
	op.rd.r       = i[11:7];
	op.rd.c       = default_context;
	op.rd_e       = 1'b0;
	op.rd_m       = 1'b0;
	op.rs1.r      = i[19:15];
	op.rs1.c      = default_context;
	op.rs1_valid  = 1'b0;
	op.rs2.r      = i[24:20];
	op.rs2.c      = default_context;
	op.rs2_valid  = 1'b0;
	op.imm	      = 'bx;
	op.csrw       = 1'b0;
	op.csrr       = 1'b0;
	op.pred_taken = d_pred_taken;

	op.funct7     = i[31:25];
	op.funct3     = i[14:12];

	unique case (i[6:0])
	  LOAD: begin
	     if (!core.STRICT_UNDEFINED
	       || (op.funct3 != 3'b011 && op.funct3[2:1] != 2'b11))
	       op.itype      = INSN_LD;

	     op.rd_m = 1'b1;
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
	     if (!core.STRICT_UNDEFINED || op.funct3[2:1] != 2'b01)
	       op.itype	  = INSN_BR;
	     op.rs1_valid = 1'b1;
	     op.rs2_valid = 1'b1;
	     op.imm	  = b_imm + op.pc;
	  end

	  JALR: begin
	     op.itype      = INSN_JAL;
	     op.rs1_valid = 1'b1;
	     op.rd_e      = 1'b1;
	     op.imm	  = i_imm;
	  end

	  MISC_MEM: begin
	     unique casez (op.funct3)
	       3'b000,		// FENCE/PAUSE
	       3'b001: begin	// FENCE.I (Zifencei)
		  op.itype = INSN_NOP;	// Treat as NOP
	       end
	       default: begin
		  op.itype = INSN_ERR;
	       end
	     endcase
	  end

	  JAL: begin
	     op.itype     = INSN_JAL;
	     op.rd_e      = 1'b1;
	     op.imm       = j_imm + op.pc;
	  end

	  OP: begin
	     op.itype		= INSN_ALU;
	     op.rs1_valid	= 1'b1;
	     op.rs2_valid	= 1'b1;
	     op.rd_e		= 1'b1;
	  end

	  OP_IMM: begin
	     op.itype		= INSN_ALU;
	     op.rs1_valid	= 1'b1;
	     op.rs2_valid	= 1'b0;
	     op.rd_e		= 1'b1;

	     // For the SLLI and SLAI opcodes, rs2 is a short immediate
	     // and funct7 is valid; for others, the full i immediate is
	     // used and funct7 is considered zero.
	     if (op.funct3[1:0] == 2'b01) begin
	       op.imm	  = op.rs2.r;
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
		  op.csrr = |op.rd.r;
		  op.csrw = 1'b1;
		  op.itype = INSN_CSR;
	       end
	       2'b1?: begin	// CSRR[SC][I]
		  op.rd_e = 1'b1;
		  op.csrr = 1'b1;
		  op.csrw = |op.rs1.r;
		  op.itype = INSN_CSR;
	       end
	       2'b00: begin
		  // ECALL, EBREAK
		  if (!core.STRICT_UNDEFINED ||
		    (!i[31:21] && !op.rs1.r && !op.funct3[2]))
		    op.itype = INSN_ECALL;
	       end
	     endcase // unique casez (op.funct3[1:0])
	  end

	  AUIPC: begin
	     op.itype  = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rs1.r  = 5'b0;	// rs1 = immediate 0
	     op.rd_e   = 1'b1;
	     op.imm    = u_imm + op.pc;
	  end

	  LUI: begin
	     op.itype  = INSN_ALU;
	     op.funct3 = ALU_ADD;
	     op.rs1.r  = 5'b0;	// rs1 = immediate 0
	     op.rd_e   = 1'b1;
	     op.imm    = u_imm;
	  end

	  default: begin
	     // All other opcodes are invalid; this also takes care
	     // of 16-bit decode failure
	     op.itype = INSN_ERR;
	  end
	endcase // unique case (i[6:0])

	// x0 can never be written, and always is zero (effectively
	// an immediate.) This enforces that constraint.
	if (!op.rd.r)
	  begin
	     op.rd_e = 1'b0;
	     op.rd_m = 1'b0;
	  end

	// Give the synthesizer a bit more flexibility
	if (op.itype == INSN_ERR)
	  op = err_op(op.pc, op.i16);
     end // always @ (*)
endmodule

module decode_seq
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
   function logic insn_mult(input decoded_insn_t op);
      // The combinatorial decode leaves a multiply as INSN_ALU.
      insn_mult = (op.itype == INSN_ALU) &
		  op.rs1_valid & op.rs2_valid &
		  (op.funct7 == 7'b000_0001) & !op.funct3[2];
   endfunction

   reg		have_mult;
   regnum_t	mult_rs1;
   regnum_t	mult_rs2;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  have_mult <= 1'b0;
	  mult_rs1  <= 'bx;
	  mult_rs2  <= 'bx;
       end
     else if (d_clken)
       begin
	  if (d_killed) begin
	     // State rolled back
	     have_mult <= 1'b0;
	     mult_rs1  <= 'bx;
	     mult_rs2  <= 'bx;
	  end else if (op_o.itype == INSN_MUL) begin
	     if (op_o.rd != op_o.rs1 && op_o.rd != op_o.rs2) begin
		have_mult <= 1'b1;
		mult_rs1  <= op_o.rs1;
		mult_rs2  <= op_o.rs2;
	     end else begin
		have_mult <= 1'b0;
		mult_rs1  <= 'bx;
		mult_rs2  <= 'bx;
	     end
	  end else if ((op_o.rd_e | op_o.rd_m) &&
	    (!have_mult || op_o.rd == mult_rs1 || op_o.rd == mult_rs2)) begin
	     // Input registers clobbered
	     // The have_mult clause is for the benefit of simulation
	     have_mult <= 1'b0;
	     mult_rs1  <= 'bx;
	     mult_rs2  <= 'bx;
	  end
       end // if (d_clken)

   always @(*) begin
      op_o = op_i;

      // Killed instruction
      if (d_killed)
	op_o = killed_op();
      else if (!d_valid_i)
	op_o = null_op(op_i.pc);
      else if (insn_mult(op_o)) begin
	 // Multiply handling
	 if (have_mult && !op_i.funct3[1:0] &&
	   op_i.rs1 == mult_rs1 && op_i.rs2 == mult_rs2) begin
	    // Can forward old multiply low result
	    op_o.itype = INSN_MULL;
	 end else begin
	    // Need to actually multiply
	    op_o.itype = INSN_MUL;
	    // Move the output to the M stage. Note that
	    // using op_i.rd_e here handles the case of rd == x0.
	    op_o.rd_m = op_i.rd_e;	  // Output in M stage
	    op_o.rd_e = 1'b0;
	 end
      end
   end
endmodule // decode_seq

//
// Decoder pipeline stage
//
module decode (
  input			      rst_n,
  input			      clk,
  input			      clken,

  input [31:0]		      d_din,		// From fetch stage
  input			      d_insn_16,	// 16-bit instruction packet
  input			      d_pred_taken,	// F predicted taken branch
  input [31:0]		      d_pc,

  input			      d_valid_i,
  input			      d_stall,
  input			      d_killed,
  output		      d_valid_o,
  output		      d_busy,

  output		      decoded_insn_t d_op
			 );

   wire			      d_clken;

   assign d_busy    = 1'b0;
   assign d_clken   = clken & (d_busy | (d_valid_i & ~d_stall));
   assign d_valid_o = d_valid_i & ~d_killed & ~d_busy;

   decoded_insn_t c_op;		// decode_comb op out

   // Purely combinatorial decode
   decode_comb comb (
     .d_din (d_din), .d_insn_16(d_insn_16), .d_pred_taken(d_pred_taken),
     .d_pc (d_pc & core.PC_MASK), .op(c_op)
     );

   // Additional, sequence-dependent 
   decode_seq mult (
     .rst_n (rst_n), .clk(clk), .d_clken(d_clken), .d_killed(d_killed),
     .d_valid_i (d_valid_i), .op_i(c_op), .op_o(d_op)
     );
endmodule

//
// Quickly extract *possible* source registers for an instruction; this
// allows the register file lookup to be done mostly in parallel with
// the proper decode stage. It does not necessarily mean these register
// values are actually used.
//
// This is combinatorial, and should be kept as small as possible.
//
module decode_srcregs (
  input [31:0] insn,
  output reg [4:0] rs1,
  output reg [4:0] rs2
  );

   localparam [4:0] R_ZERO = 5'd0;
   localparam [4:0] R_RA   = 5'd1;
   localparam [4:0] R_SP   = 5'd2;

   always @(*)
     priority casez ({insn[15:13], insn[1:0]})
       5'b???_11: begin	  // 32-bit instruction
	  rs1 = insn[19:15];
	  rs2 = insn[24:20];
       end
       5'b000_00: begin		// C.ADDI4SPN
	  rs1 = R_SP;
	  rs2 = 5'bx;
       end
       5'b???_00: begin		// RVC quadrant 0, memory references
	  rs1 = { 2'b01, insn[9:7] };
	  rs2 = { 2'b01, insn[4:2] };
       end
       2'b0??_01: begin		// RVC quadrant 1, lower half
	  rs1 = insn[11:7];
	  rs2 = { 2'b01, insn[4:2] };
       end
       2'b1??_01: begin		// RVC quadrant 1. lower half
	  rs1 = { 2'b01, insn[9:7] };
	  rs2 = { 2'b01, insn[4:2] };
       end
       2'b?00_10: begin		// RVC quadrant 2, non-SP
	  rs1 = insn[11:7];
	  rs2 = insn[6:2];
       end
       2'b???_10: begin		// RVC quadrant 2, SP memory references
	  rs1 = R_SP;
	  rs2 = insn[6:2];
       end
       default: begin
	  rs1 = 5'bx;
	  rs2 = 5'bx;
       end
     endcase
endmodule
