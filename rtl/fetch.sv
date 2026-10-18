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

module retstack_ram #(`CONFIG)
   (
   input		   clk,
   input		   clken,
   input [31:0]		   d,
   input [PREDICT_RET-1:0] a,
   input		   we,
   output [31:0]	   q
);
   reg [31:0] ram [0:(1 << PREDICT_RET)-1];
   reg [PREDICT_RET-1:0] a_q = 'b0;

`ifndef SYNTHESIS
   // The retstack can be used speculatively, so make sure it
   // doesn't contain x on startup.
   initial begin
     for (int i = 0; i < (1 << PREDICT_RET); i++)
       ram[i] = PC_MASK;
   end
`endif

   always @(posedge clk)
     if (clken) begin
	if (we)
	  ram[a] <= d & PC_MASK;
	a_q	 <= a;
     end

   assign q = ram[a_q];
endmodule

//
// Predict the successor instruction. This (obviously) does not need
// to be perfect; however, the "take" flag MUST to be set when strict
// successor flow of control is not maintained, as otherwise the fetch
// unit will advance to the next fetch datum rather than to the exact
// PC address. It is always safe to set "take", at a possible
// performance cost.
//
// If f2_valid is false, then next_pc reflects the successor PC
// dependent only on f2_is_16; the instruction data is ignored.
//
// For timing reasons, this is fed the instruction data pre-RVC-decode,
// even if EARLY_RVC is enabled.
//
module predict_branch #(`CONFIG)
  (
   input	     rst_n,
   input	     clk,
   input	     clken,
   input	     restart,
   input	     retstack_t restart_retstack,
   input [31:0]	     f2_insn,
   input	     f2_is_16,
   input	     f2_valid,
   input             f1_advance,
   input             f2_advance,
   input [31:0]	     f2_pc,
   input	     d_pred_t d_pred,
   output reg	     br_take,
   output reg [31:0] next_pc,
   output	     retstack_t d_retstack
   );

   parameter bit EXTRA_PC_ADDERS     = 1'b1;
   parameter bit RET_STACK_SKIPS_ADD = 1'b1;

   function automatic logic [31:0] add_pc
     (
      input signed [31:0] pc,
      input signed [31:0] offset
   );
      add_pc  = (pc + offset) & PC_MASK;
   endfunction

   wire [31:0]	 i 		 = f2_insn;

   wire signed [11:0] i_imm 	 = i[31:20];
   wire signed [12:0] b_imm 	 = { i[31], i[7], i[30:25], i[11:8], 1'b0 };
   wire signed [20:0] j_imm 	 = { i[31], i[19:12], i[20], i[30:21], 1'b0 };
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

   logic is_call;
   logic is_ret;
   logic take;
   logic [31:0]	succ_pc;
   logic [31:0]	ret_pc;
   logic [31:0]	pred_pc;
   logic [31:0]	lui_addr;
   logic [31:0]	lui_addr_q;

   reg [31:0]	next_pc_q;
   reg		br_take_q;

   localparam bit do_predict_ret = PREDICT_RET >= 0;

   generate
      if (do_predict_ret) begin : ret_stack
	 logic [PREDICT_RET-1:0] ret_stack_ptr;

	 retstack_ram #(`CFG) ram (
	    .clk   (clk),
	    .clken (clken),
	    .d     (succ_pc & PC_MASK),
	    .a     (ret_stack_ptr),
	    .we    (f2_advance & is_call),
	    .q     (ret_pc)
	 );

	 always_comb
	   ret_stack_ptr = d_retstack - is_ret + is_call;

	 always @(posedge clk or negedge rst_n)
	   if (~rst_n) begin
	      d_retstack <= 'b0;
	   end else if (clken) begin
	      if (restart) begin
		 d_retstack <= restart_retstack;
	      end else if (f2_advance) begin
		 d_retstack <= ret_stack_ptr;
	      end
	   end
      end else begin : no_ret_stack
	 assign d_retstack = 'bx;
	 assign ret_pc     = 'bx;
      end
   endgenerate

   // True if the register number is one of the architectural
   // link registers x1 or x5.
   function automatic logic is_link (input [4:0] r);
      is_link = { r[4:3], r[1:0] } == 4'b0001;
   endfunction

   always @(*)
     begin
	logic signed [31:0] bj_offset;
	logic signed [31:0] bj_pc;
	logic signed [31:0] cbj_offset;
	logic signed [31:0] cbj_pc;
	logic		    rd_is_link;

	succ_pc    = add_pc(f2_pc, f2_is_16 ? 32'd2 : 32'd4);
	pred_pc    = succ_pc;
	take	   = 1'b0;
	is_call    = 1'b0;
	is_ret	   = 1'b0;
	lui_addr   = 'b0;

	// The B and the J formats, and the CB and CJ formats, are
	// similar enough that it should be cheap to MUX between them,
	// especially since only one bit needs to be tested for that
	// specific MUX...
	bj_offset  = i[3] ? j_imm : b_imm;
	cbj_offset = i[14] ? cb_imm : cj_imm;

	if (EXTRA_PC_ADDERS) begin
	   bj_pc      = add_pc(f2_pc, bj_offset);
	   cbj_pc     = add_pc(f2_pc, cbj_offset);
	end else begin
	   // The CBJ ops are all in RVC quadrant 1, so just test
	   // for quadrant 0/1 versus 2/3
	   bj_pc      = add_pc(f2_pc, i[1] ? bj_offset : cbj_offset);
	   cbj_pc     = bj_pc;
	end

	// This is valid for non-RVC JAL and JALR
	rd_is_link = is_link(i[11:7]);

	unique casez (i[6:0])
	  7'b?????01: if (WITH_RVC) begin	// RVC quadrant 1
	     unique casez (i[15:13])
	       3'b?01: begin		// C.J(AL)
		  take    = 1'b1;	// Unconditional
		  is_call = ~i[15];	// C.JAL is always a call
		  if (take)
		    pred_pc = cbj_pc;
	       end
	       3'b11?: begin		// C.BEQZ/C.BNEZ
		  take   = cb_imm[8];	// Predict taken if backwards
		  if (take)
		    pred_pc = cbj_pc;
	       end
	       default: begin
		  // Default
	       end
	     endcase // unique casez (i[15:13])
	  end
	  7'b0000010: if (WITH_RVC) begin // RVC quadrant 2 with rs2 = 0
	     if (PREDICT_JALR && i[15:13] == 3'b100) begin
		// if rs1 is zero this is not J(AL)R, but it doesn't
		// matter, as it is EBREAK or ECALL/illegal which
		// are treated as exceptions and thus will always abort
		// the pipeline anyway.
		take	  = 1'b1; // Unconditional

		// This is a call if it is JALR not targeting x0 or x1
		is_call = i[12] & (|i[11:8]);

		// It is a return if JR (x1), JR (x5) or JALR (x5)
		unique casez (i[12:7])
		  6'b0_00z01,		// JR (x1), JR (x5)
			 6'b1_00101:
			   is_ret = 1'b1;
		  default:
		    is_ret = 1'b0;
		endcase

		if (do_predict_ret & is_ret)
		  pred_pc = ret_pc & PC_MASK;
		else
		  pred_pc = lui_addr_q & PC_MASK;
	     end
	  end
	  JAL: begin
	     take    = 1'b1;		// Unconditional
	     is_call = rd_is_link;
	     pred_pc = bj_pc;
	  end
	  JALR: if (PREDICT_JALR) begin
	     logic  [4:0] rs1;
	     logic  [4:0] rd;

	     rs1	  = i[19:12];
	     rd	  = i[11:7];

	     is_call = rd_is_link;
	     is_ret  = is_link(rs1) && (!is_call || (rs1[2] != rd[2]));

	     take	  = 1'b1;	// Unconditional

	     if (!do_predict_ret) begin
		pred_pc = add_pc(lui_addr_q, i_imm);
	     end else if (RET_STACK_SKIPS_ADD) begin
		if (is_ret)
		  pred_pc = ret_pc & PC_MASK;
		else
		  pred_pc = add_pc(lui_addr_q, i_imm);
	     end else begin
		logic [31:0] jalr_pc;

		if (do_predict_ret & is_ret)
		  jalr_pc = ret_pc & PC_MASK;
		else
		  jalr_pc = lui_addr_q & PC_MASK;

		pred_pc   = add_pc(jalr_pc, i_imm);
	     end
	  end
	  BRANCH: begin
	     take   = b_imm[12];	// Predict taken if backwards
	     if (take)
	       pred_pc = bj_pc;
	  end
	  LUI: begin
	     lui_addr = { i[31:12], 12'b0 } & PC_MASK;
	  end
	  AUIPC: begin
	     lui_addr = add_pc(f2_pc, { i[31:12], 12'b0 });
	  end
	  default: begin
	     // Default
	  end
	endcase // unique casez (i[6:0])

	next_pc = pred_pc;
	br_take = take;

	if (~f2_valid) begin
	   next_pc = succ_pc;
	   br_take = 1'b0;
	end
     end

   always @(posedge clk or negedge rst_n)
     if (~rst_n) begin
	next_pc_q  <= RESET_PC & PC_MASK;
	br_take_q  <= 1'b1;
	lui_addr_q <= 'b0;
     end else if (clken) begin
	next_pc_q <= next_pc & PC_MASK;
	br_take_q <= br_take;
	if (f2_advance)
	  lui_addr_q <= lui_addr & PC_MASK;
     end
endmodule

module fetch #(`CONFIG)
   (
   input	     clk,
   input	     clken,
   input	     rst_n,

   input	     restart,			  // Killed in the E stage
   input [31:0]	     restart_pc,		  // PC to restart from
   input	     retstack_t restart_retstack, // Retstack ptr on restart
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
   output reg [31:0] d_pc,
   output	     mcontext_t d_mcontext,
   output	     retstack_t d_retstack,
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
   output	     regnum_t f_rs2,

   // Combinatorial inputs from the D stage for the purpose of helping
   // predicting J(AL)R
   input	     d_pred_t d_pred
);

   function automatic logic [31:0] add_pc
     (
      input signed [31:0] pc,
      input signed [31:0] offset
   );
      add_pc  = (pc + offset) & PC_MASK;
   endfunction

   wire [31:0]	     next_pc;
   reg [15:0]	     pref_16;	// Prefetched upper halfword
   reg		     pref_valid;

   reg [31:0]	     f2_pc;

   logic [31:0]	     f2_insn;
   logic	     f2_valid;
   logic	     f2_advance;
   logic	     f2_have_16;
   logic	     f2_have_32;
   logic	     f2_is_16;
   logic	     br_take;

   // Branch prediction
   predict_branch #(`CFG) pred (
      .rst_n        (rst_n),
      .clk          (clk),
      .clken        (clken),
      .restart      (restart),
      .restart_retstack (restart_retstack),
      .f2_insn	    (f2_insn),
      .f2_is_16	    (f2_is_16),
      .f2_valid     (f2_valid),
      .f1_advance   (f1_advance),
      .f2_advance   (f2_advance),
      .f2_pc	    (f2_pc),
      .d_pred       (d_pred),
      .br_take	    (br_take),
      .next_pc	    (next_pc),
      .d_retstack   (d_retstack)
   );

   // Opportunistically skip padding c.nops by treating them as
   // the upper part of a 32-bit instruction for the purpose of
   // fetching, if and only those bits have already been fetched.
   function automatic logic is_cnop(input [15:0] cinst);
      is_cnop = !cinst[15:13] && !cinst[11:7] && cinst[1:0] == 2'b01;
   endfunction

   // If there is no output yet, no need to stall
   wire		     f_stalled = f_stall & d_valid_i;

   // f2_have_data is true if ibus_rdata contains usable data
   reg		     ibus_valid_q;
   wire		     f2_have_data = ibus_valid_q & ibus_ready & ~f_stalled;

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
   assign f1_advance = f2_have_data & ~(pref_valid & f2_is_16);

   always @(*)
     if (br_take) begin
	ibus_a = next_pc & PC_MASK;
	ibus_a[1:0] = 2'b00;	// Meaningless bits
     end else begin
	ibus_a = add_pc(ibus_a_q, {f1_advance, 2'b00});
     end

   // Early register file decode; this should be possible to do
   // in parallel with the branch prediction decode and possibly
   // leverage some of the same logic elements.
   decode_srcregs dsr (
      .insn (f2_insn),
      .mc   (d_mcontext),
      .rs1  (f_rs1),
      .rs2  (f_rs2)
   );

   assign f2_advance = f2_valid & ~f_stalled;
   assign f_valid_o  = f2_advance;

   // Early RVC decode, if enabled
   wire [31:0] f2_insn_final;
   rv32c_comb #(`CFG, .enabled(WITH_RVC && EARLY_RVC))
   rvc (.d(f2_insn), .q(f2_insn_final));

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  d_pc	       <= RESET_PC & PC_MASK;
	  f2_pc        <= RESET_PC & PC_MASK;
	  ibus_a_q     <= RESET_PC & PC_MASK;
	  d_valid_i    <= 1'b0;
	  d_insn       <= INVALID_INSN;
	  d_mcontext.m <= CTX_MACHINE;
	  d_mcontext.u <= CTX_MIN_USER;
	  pref_valid   <= 1'b0;
	  pref_16      <= 16'bx;
	  ibus_valid_q <= 1'b0; // Data not ready yet
       end
     else if (clken)
       begin
	  if (restart)
	    begin
	       d_pc		<= restart_pc & PC_MASK;
	       f2_pc		<= restart_pc & PC_MASK;
	       ibus_a_q		<= restart_pc & PC_MASK;
	       d_valid_i	<= 1'b0;
	       d_insn		<= INVALID_INSN;
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
		    d_valid_i	 <= f2_valid;

		    // If f2_valid == 0, this is only a partial
		    // instruction fetch. ~f_stalled & f2_valid
		    // is the same as f2_advance.
		    if (f2_valid) begin
		       d_insn	  <= f2_insn_final;
		       d_pc	  <= f2_pc;
		       d_insn_16  <= f2_is_16;
		       f2_pc	  <= next_pc;
		    end
		 end
	    end
       end // if (clken)
endmodule // fetch
