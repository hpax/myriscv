//
// Fetch unit. The fetch stage is, in some respects, two stages:
// F1 - produces the fetch PC and presents it on ibus_a;
// F2 - accepts the data from ibus_rdata, and forwards it to the D stage,
//      as well as provides the input data to the PC computation of
//      the F1 stage.
//
// Because the PC-computing logic has to be combinatorial in order to
// be able to do enough decoding to do branch prediction, if f_stall is
// asserted, the F1 PC cannot be advanced and the datum needs to be
// re-fetched (or latched; this assumes that re-fetching from TCM
// or icache is "free".
//

`include "myriscv.vh"

//
// Predict the successor instruction. This (obviously) does not need
// to be perfect; however, the "take" flag needs to be set when strict
// successor flow of control is not maintained.
//
// If f2_valid is false, then next_pc reflects the successor PC
// dependent only on f2_is_16; the instruction data is ignored.
//
// XXX: if EARLY_RVC is enabled, would it be better to feed this with
// the output of the RVC parser?
//
module predict_branch #(`CONFIG)
  (
   input [31:0]	     f2_insn,
   input	     f2_is_16,
   input	     f2_valid,
   input [31:0]	     f2_pc,
   output reg	     take,
   output reg [31:0] next_pc
   );

   wire [31:0]	 i = f2_insn;

   wire signed [11:0]    i_imm = i[31:20];
   wire signed [12:0]	 b_imm = { i[31], i[7], i[30:25], i[11:8], 1'b0 };
   wire signed [20:0]	 j_imm = { i[31], i[19:12], i[20], i[30:21], 1'b0 };
   wire signed [11:0]	 cj_imm;
   assign cj_imm[0]   = 1'b0;
   assign cj_imm[5]   = i[2];
   assign cj_imm[3:1] = i[5:3];
   assign cj_imm[7]   = i[6];
   assign cj_imm[6]   = i[7];
   assign cj_imm[10]  = i[8];
   assign cj_imm[9:8] = i[10:9];
   assign cj_imm[4]   = i[11];
   assign cj_imm[11]  = i[12];
   wire signed [8:0]	 cb_imm;
   assign cb_imm[0]   = 1'b0;
   assign cb_imm[5]   = i[2];
   assign cb_imm[2:1] = i[4:3];
   assign cb_imm[7:6] = i[6:5];
   assign cb_imm[4:3] = i[11:10];
   assign cb_imm[8]   = i[12];

   function logic [31:0] add_pc
     (
     input signed [31:0] pc,
     input signed [31:0] offset
       );
      add_pc			     = (pc + offset) & PC_MASK;
   endfunction

   always @(*)
     begin
	logic signed [31:0] bj_offset;
	logic signed [31:0] bj_pc;
	logic signed [31:0] cbj_offset;
	logic signed [31:0] cbj_pc;

	next_pc    = add_pc(f2_pc, f2_is_16 ? 32'd2 : 32'd4);
	take	   = 1'b0;

	// The B and the J formats, and the CB and CJ formats, are
	// similar enough that it should be cheap to MUX between them,
	// especially since only one bit needs to be tested for that
	// specific MUX...
	bj_offset  = i[3] ? j_imm : b_imm;
	cbj_offset = i[14] ? cb_imm : cj_imm;

`ifdef EXTRA_PC_ADDERS
	bj_pc	   = add_pc(f2_pc, bj_offset);
	cbj_pc     = add_pc(f2_pc, cbj_offset);
`else
	// The CBJ ops are all in RVC quadrant 1, so just test
	// for quadrant 0/1 versus 2/3
	bj_pc      = add_pc(f2_pc, i[1] ? bj_offset : cbj_offset);
	cbj_pc     = bj_pc;
`endif

	if (f2_valid)
	  unique casez (i[6:0])
	    7'b?????01: begin		// RVC quadrant 1
	       unique casez (i[15:13])
		 3'b?01: begin		// C.J(AL)
		    take   = 1'b1;	// Unconditional
		    if (take)
		      next_pc = cbj_pc;
		 end
		 3'b11?: begin		// C.BEQZ/C.BNEZ
		    take   = cb_imm[8];	// Predict taken if backwards
		    if (take)
		      next_pc = cbj_pc;
		 end
		 default: begin
		    // Default
		 end
	       endcase // unique casez (i[15:13])
	    end
	    JAL: begin
	       take   = 1'b1;		// Unconditional
	       next_pc = bj_pc;
	    end
	    JALR: begin
	       if (PREDICT_JALR_ZERO && !i[19:12]) begin
		  // j[al]r addr(zero)
		  take		= 1'b1;	// Unconditional
		  next_pc	= add_pc(32'b0, i_imm);	// Absolute!
	       end
	    end
	    BRANCH: begin
	       take   = b_imm[12];	// Predict taken if backwards
	       if (take)
		 next_pc = bj_pc;
	    end
	    default: begin
	       // Default
	    end
	  endcase // unique casez (i[6:0])
     end
endmodule

module fetch #(`CONFIG)
  (
   input	     clk,
   input	     clken,
   input	     rst_n,

   input	     restart, // Killed in the E stage
   input [31:0]	     restart_pc, // PC to restart from
   input	     mcontext_t restart_mcontext, // Machine context to restart from
   output reg [31:0] ibus_a,
   input [31:0]	     ibus_rdata,
   output reg	     ibus_valid,
   input	     ibus_ready,

   input	     f_stall,

   //
   // Note: this units outputs already latched outputs to the D stage!
   //
   output reg [31:0] d_insn,
   output reg	     d_valid_i,
   output reg	     d_pred_taken,
   output reg [31:0] d_pc,
   output	     mcontext_t d_mcontext,
   // This flag can be clear for pair of fused 16-bit instructions;
   // the decode stage needs to consider that appropriately.
   output reg	     d_insn_16,
   // Combinatorially decoded rs1 and rs2 registers for the purpose
   // of early register file access. These are *only* valid during
   // the cycle f_valid_o is asserted.
   // XXX: may need to use the addrstall feature of the regfile
   // hard RAM blocks.
   output	     f_valid_o,
   output	     regnum_t f_rs1,
   output	     regnum_t f_rs2
   );

   wire [31:0]	     next_pc;
   reg  [15:0]	     pref_16;	// Prefetched upper halfword
   reg		     pref_valid;

   reg [31:0]	     f2_pc;

   logic [31:0]	     f2_insn;
   logic	     f2_valid;
   logic	     f2_have_16;
   logic	     f2_have_32;
   logic	     f2_is_16;

   wire		     br_take;
   // Branch prediction
   predict_branch #(`CFG) pred (
     .f2_insn	(f2_insn),
     .f2_is_16	(f2_is_16),
     .f2_valid  (f2_valid),
     .f2_pc	(f2_pc),
     .take	(br_take),
     .next_pc	(next_pc)
     );

   // Opportunistically skip padding c.nops by treating them as
   // the upper part of a 32-bit instruction for the purpose of
   // fetching, if and only those bits have already been fetched.
   function logic is_cnop(input [15:0] cinst);
      is_cnop = !cinst[15:13] && !cinst[11:7] && cinst[1:0] == 2'b01;
   endfunction

   // If there is no output yet, no need to stall
   wire		     f_stalled = f_stall & d_valid_i;

   // f2_have_data is true if ibus_rdata contains usable data
   reg	     ibus_valid_q;
   wire	     f2_have_data = ibus_valid_q & ibus_ready & ~f_stalled;

   // This benefits simulation by catching data read from the
   // bus while not ready.
   wire [31:0]	     iword = ibus_ready ? ibus_rdata : 32'bx;

   // Do we have a usable instruction for the D stage?
   always @(*)
     begin
	if (~f2_pc[1]) begin
	   f2_insn	= iword;
	   f2_have_16	= f2_have_data;
	   f2_have_32	= f2_have_data;
	end else if (pref_valid) begin
	   f2_insn	= { iword[15:0], pref_16 };
	   f2_have_16	= 1'b1;
	   f2_have_32	= f2_have_data;
	end else begin
	   f2_insn	= { 16'bx, iword[31:16] };
	   f2_have_16	= f2_have_data;
	   f2_have_32	= 1'b0;
	end

	// This skips a c.nop in the second word if we have it
	// ready...
	f2_is_16 = !(f2_insn[1:0] == 2'b11) &&
		   !(FUSE_CNOP && f2_have_32 & is_cnop(f2_insn[31:16]));

	// Note: this form is written explicitly to handle X correctly
	f2_valid = f2_have_32 | (f2_have_16 && f2_insn[1:0] != 2'b11);
     end

   // Are we actually reading?
   assign ibus_valid = rst_n & ~restart;

   reg [31:0] ibus_a_q;

   // Advance ibus_a if and only if the input was accepted.
   // Unless this is a predicted branch, always advance to the next
   // *fetch datum*, not necessarily the next *instruction*.
   wire	      f1_advance = f2_have_data & ~(pref_valid & f2_is_16);

   always @(*)
     if (f2_have_data & br_take)
       ibus_a = next_pc;
     else
       ibus_a = (ibus_a_q + {f1_advance, 2'b00}) & PC_MASK;

   // Early register file decode; this should be possible to do
   // in parallel with the branch prediction decode and possibly
   // leverage some of the same logic elements.
   decode_srcregs dsr (
		       .insn (f2_insn),
		       .mc   (d_mcontext),
		       .rs1  (f_rs1),
		       .rs2  (f_rs2)
		       );
   assign f_valid_o = f2_valid & ~f_stalled;

   // Early RVC decode, if enabled
   wire [31:0] f2_decoded_insn;
   rv32c_comb #(`CFG) rvc (.d(f2_insn), .q(f2_decoded_insn));
   wire [31:0] f2_insn_final = EARLY_RVC ? f2_decoded_insn : f2_insn;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  d_pc		<= RESET_PC & PC_MASK;
	  f2_pc		<= RESET_PC & PC_MASK;
	  ibus_a_q      <= RESET_PC & PC_MASK;
	  d_valid_i	<= 1'b0;
	  d_pred_taken	<= 1'b0;
	  d_insn	<= 32'bx;
	  d_mcontext    <= mcontext_reset();
	  pref_valid	<= 1'b0;
	  pref_16	<= 16'bx;
	  ibus_valid_q	<= 1'b0; // Data not ready yet
       end
     else if (clken)
       begin
	  if (restart)
	    begin
	       d_pc		<= restart_pc & PC_MASK;
	       f2_pc		<= restart_pc & PC_MASK;
	       ibus_a_q		<= restart_pc & PC_MASK;
	       d_valid_i	<= 1'b0;
	       d_pred_taken	<= 1'b0;
	       d_insn		<= 32'bx;
	       d_mcontext       <= restart_mcontext;
	       pref_valid	<= 1'b0;
	       pref_16		<= 16'bx;
	       ibus_valid_q	<= 1'b0; // Discard incoming data
	    end
	  else
	    begin
	       ibus_valid_q	<= ibus_valid;
	       ibus_a_q         <= ibus_a;

	       if (f2_have_data) begin
		  pref_16      <= iword[31:16];
		  pref_valid   <= f1_advance & ~br_take;
	       end

	       if (~f_stalled)
		 begin
		    d_valid_i	    <= f2_valid;

		    // Should this really be here for !f2_valid?
		    d_pred_taken    <= f2_valid & br_take;

		    // If f2_valid == 0, this is only a partial
		    // instruction fetch.
		    if (f2_valid) begin
		       d_insn       <= f2_insn_final;
		       d_pc	    <= f2_pc;
		       d_insn_16    <= f2_is_16;
		       f2_pc	    <= next_pc;
		    end
		 end
	    end
       end // if (clken)
endmodule // fetch
