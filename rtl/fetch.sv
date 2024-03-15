`include "myriscv.vh"

//
// Predict the successor instruction. This does not need to be
// perfect; however, the "take" flag needs to be set when strict
// successor flow of control is not maintained.
//
module predict_branch
  (
   input [31:0]	     this_insn,
   input	     is_16,	// This can differ from the opcode
   input [31:0]	     this_pc,
   output reg	     take,
   output reg [31:0] next_pc
   );

   wire [31:0]	 i = this_insn;

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

   always @(*)
     begin
	logic absolute;
	logic [31:0] absolute_pc;
	logic signed [20:0] offset;

	absolute    = 1'b0;
	absolute_pc = 32'bx;
	take        = 1'b0;
	// Normal successor PC
	offset      = is_16 ? 3'd2 : 3'd4;

	unique casez (i[6:0])
	  7'b?????01: begin		// RVC quadrant 1
	     unique casez (i[15:13])
	       3'b?01: begin		// C.J(AL)
		  take   = 1'b1;	// Unconditional
		  if (take)
		    offset = cj_imm;
	       end
	       3'b11?: begin		// C.BEQZ/C.BNEZ
		  take   = cb_imm < 0;	// Predict taken if backwards
		  if (take)
		    offset = cb_imm;
	       end
	       default: begin
		  // Default
	       end
	     endcase // unique casez (i[15:13])
	  end
	  JAL: begin
	     take   = 1'b1;		// Unconditional
	     offset = j_imm;
	  end
	  JALR: begin
	     if (core.PREDICT_JALR_ZERO && !i[19:12]) begin
		// j[al]r addr(zero)
		take        = 1'b1;	// Unconditional
		absolute    = 1'b1;
		absolute_pc = i_imm;
	     end
	  end
	  BRANCH: begin
	     take   = b_imm < 0;	// Predict taken if backwards
	     if (take)
	       offset = b_imm;
	  end
	  default: begin
	     // Not a transfer or not predicted
	  end
	endcase // unique casez (i[6:0])

	if (!absolute)
	  absolute_pc = $signed(this_pc) + offset;

	next_pc = absolute_pc & core.PC_MASK;
     end
endmodule

module fetch
  (
   input	     clk,
   input	     clken,
   input	     rst_n,

   input	     restart, // Killed in the E stage
   input [31:0]	     restart_pc, // PC to restart from
   output reg [31:0] ibus_a,
   input [31:0]	     ibus_rdata,
   output reg	     ibus_valid,
   input	     ibus_ready,

   input	     stall,
   output reg [31:0] insn, // Actually d_din
   output reg	     valid_o, // Actually d_valid_i
   output reg	     insn_pred_taken,
   output reg [31:0] insn_pc,

   // This flag can be clear for pair of fused 16-bit instructions;
   // the decode stage needs to consider that appropriately.
   output reg	     insn_16
   );

   wire [31:0]	     next_pc;
   reg [15:0]	     pref_16;
   reg		     pref_valid;

   reg [31:0]	     this_pc;

   logic [31:0]	     this_insn;
   logic	     this_valid;
   logic	     have_16;
   logic	     have_32;
   logic	     is_16;

   wire		 br_take;
   // Branch prediction
   predict_branch pred (
     .this_insn	(this_insn),
     .is_16	(is_16),
     .this_pc	(this_pc),
     .take	(br_take),
     .next_pc	(next_pc)
     );

   // Opportunistically skip padding c.nops by treating them as
   // the upper part of a 32-bit instruction for the purpose of
   // fetching, if and only those bits have already been fetched.
   function logic is_cnop(input [15:0] cinst);
      is_cnop = !cinst[15:13] && !cinst[11:7] && cinst[1:0] == 2'b01;
   endfunction

   reg		     ibus_valid_q;
   wire		     have_data = ibus_valid_q & ibus_ready;

   always @(*)
     begin
	if (!this_pc[1])
	  begin
	     this_insn	= ibus_rdata;
	     have_16	= have_data;
	     have_32	= have_data;
	  end
	else if (pref_valid)
	  begin
	     this_insn	= { ibus_rdata[15:0], pref_16 };
	     have_16	= 1'b1;
	     have_32	= have_data;
	  end
	else
	  begin
	     this_insn = { 16'bx, ibus_rdata[31:16] };
	     have_16 = have_data;
	     have_32 = 1'b0;
	  end // else: !if(pref_valid)

	is_16 = !(this_insn[1:0] == 2'b11) &&
		!(have_32 & is_cnop(this_insn[31:16]));

	this_valid = this_insn[1:0] == 2'b11 ? have_32 : have_16;
     end

   wire advance  = this_valid & (~stall | ~valid_o);
   assign ibus_a = advance ? next_pc : this_pc;

   reg	restart_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  insn_pc	  <= 32'bx;
	  this_pc	  <= core.RESET_PC & core.PC_MASK;
	  valid_o	  <= 1'b0;
	  insn_pred_taken <= 1'b0;
	  insn		  <= 32'bx;
	  pref_valid	  <= 1'b0;
	  pref_16	  <= 16'bx;
	  ibus_valid	  <= 1'b0;
	  ibus_valid_q	  <= 1'b0;
       end
     else if (clken)
       begin
	  // Worst case, refetch the same datum. It should be harmless
	  // with TCM or an icache, but otherwise it might be good to be
	  // a bit smarter here.
	  ibus_valid <= 1'b1;

	  if (restart)
	    begin
	       insn_pc	       <= 1'bx;
	       this_pc	       <= restart_pc & core.PC_MASK;
	       valid_o	       <= 1'b0;
	       insn_pred_taken <= 1'b0;
	       insn	       <= 32'bx;
	       pref_valid      <= 1'b0;
	       pref_16	       <= 16'bx;
	       ibus_valid      <= 1'b0; // Improve timing
	       ibus_valid_q    <= 1'b0; // Discard mispredicted data
	    end
	  else
	    begin
	       ibus_valid_q	    <= ibus_valid;

	       if (advance)
		 begin
		    insn	    <= this_insn;
		    insn_pc	    <= this_pc;
		    insn_16	    <= is_16;
		    valid_o	    <= this_valid;
		    this_pc         <= next_pc;
		    insn_pred_taken <= br_take; // Should this be latched?

		  if (br_take) begin
		     pref_valid <= 1'b0;
		     pref_16    <= 16'bx;
		  end else if (!(is_16 & ~this_pc[1]) ||
		    (have_data & ~is_16 & this_pc[1])) begin
		     pref_16    <= ibus_rdata[31:16];
		     pref_valid <= is_16 | this_pc[1];
		  end
		 end
	       else if (!stall)
		 begin
		    // Consumed instruction but queue empty
		    valid_o	    <= 1'b0;
		    insn_pred_taken <= 1'b0;
		 end
	    end
       end // if (clken)
endmodule // fetch
