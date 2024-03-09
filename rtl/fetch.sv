module predict_branch
  (
   input [31:0]		    this_insn,
   input [31:0]		    next_pc,
   output reg		    take,
   output reg signed [31:0] offset
   );

   wire [31:0]	 i = this_insn;

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
   assign cb_imm[0]   = 1'b1;
   assign cb_imm[5]   = i[2];
   assign cb_imm[2:1] = i[4:3];
   assign cb_imm[7:6] = i[6:5];
   assign cb_imm[4:3] = i[11:10];
   assign cb_imm[8]   = i[12];

   always @(*)
     begin
	unique casez ({i[15:13], i[6:0]})
	  10'b?01_?????01: begin	// C.J(AL)
	     take   = 1'b1;
	     offset = cj_imm;
	  end
	  10'b11?_?????01: begin	// C.B*
	     take   = cb_imm[8];	// Predict taken if backwards
	     offset = cb_imm;
	  end
	  10'b???_110?111: begin	// J(AL)
	     take   = 1'b1;
	     offset = j_imm;
	  end
	  10'b???_1100011: begin	// B*
	     take   = b_imm[12];	// Predict taken if backwards
	     offset = b_imm;
	  end
	  default: begin
	     take   = 1'b0;
	     offset = 32'bx;
	  end
	endcase
     end
endmodule

module fetch
  (
   input	 clk,
   input	 clken,
   input	 rst_n,

   input	 restart,	// Killed in the E stage
   input  [31:0] restart_pc,	// PC to restart from
   output [31:0] ibus_a,
   input  [31:0] ibus_rdata,
   output	 ibus_valid,
   input	 ibus_ready,

   input	 stall,
   output [31:0] insn,
   output	 valid_o,
   output	 insn_pred_taken,
   output [31:0] insn_pc
   );

   reg [31:0]	 next_pc;
   reg [15:0]	 pref_16;
   reg		 pref_valid;

   logic [31:0]	 this_insn;
   logic	 have_16;
   logic	 have_32;
   logic	 is_16;

   wire		     br_take;
   wire [31:0]	     br_offset;
   // Branch prediction
   predict_branch pred(.this_insn(this_insn), .next_pc(next_pc),
     .take(br_take), .offset(br_offset));

   // Opportunistically skip padding c.nops by treating them as
   // the upper part of a 32-bit instruction for the purpose of
   // fetching, if and only those bits have already been fetched.
   function logic is_cnop(input [15:0] cinst);
      is_cnop = !cinst[15:13] && !cinst[11:7] && cinst[1:0] == 2'b01;
   endfunction

   wire		     have_data = ibus_valid & ibus_ready;

   always @(*)
     begin
	if (!next_pc[1])
	  begin
	     this_insn = ibus_rdata;
	     have_16   = have_data;
	     have_32   = have_data;
	  end
	else if (pref_valid)
	  begin
	     this_insn = { ibus_rdata[15:0], pref_16 };
	     have_16 = 1'b1;
	     have_32 = have_data;
	  end
	else
	  begin
	     this_insn = { 16'bx, ibus_rdata[31:16] };
	     have_16 = have_data;
	     have_32 = 1'b0;
	  end // else: !if(pref_valid)

	is_16 = !(this_insn[1:0] == 2'b11) &&
		!(have_32 & is_cnop(this_insn[31:16]));
     end

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  ibus_a          <= core.RESET_PC & core.PC_MASK & ~32'b11;
	  insn_pc         <= core.RESET_PC & core.PC_MASK;
	  next_pc         <= core.RESET_PC & core.PC_MASK;
	  valid_o      <= 1'b0;
	  insn_pred_taken <= 1'bx;
	  insn            <= 32'bx;
	  pref_valid      <= 1'b0;
	  pref_16         <= 16'bx;
	  ibus_valid      <= 1'b0;
       end
     else if (clken)
       begin
	  if (restart)
	    begin
	       ibus_a     <= restart_pc & core.PC_MASK & ~32'b11;
	       insn_pc    <= restart_pc & core.PC_MASK;
	       next_pc    <= restart_pc & core.PC_MASK;
	       valid_o <= 1'b0;
	       insn_pred_taken <= 1'bx;
	       insn       <= 32'bx;
	       pref_valid <= 1'b0;
	       pref_16    <= 16'bx;
	       ibus_valid <= 1'b1;
	    end
	  else
	    begin
	       logic advance;
	       logic [31:0] pc_incr;
	       logic [31:0] pc_updated;

	       pc_incr = 32'b0;
	       advance = !stall & (have_32 | (have_16 & is_16));

	       if (advance)
		 begin
		    insn            <= this_insn;
		    insn_pc         <= next_pc;
		    valid_o      <= 1'b1;
		    insn_pred_taken <= br_take;
		    if (br_take)
		      pc_incr = br_offset;
		    else if (is_16)
		      pc_incr = 3'd2;
		    else
		      pc_incr = 3'd4;
		 end
	       else if (!stall)
		 begin
		    valid_o <= 1'b0; // Consumed instruction but queue empty
		    insn <= 32'bx;
		    insn_pred_taken <= 1'bx;
		 end

	       pc_updated = (next_pc + pc_incr) & core.PC_MASK;
	       next_pc   <= pc_updated;

	       if (advance & br_take)
		 begin
		    pref_valid <= 1'b0;
		    ibus_a     <= pc_updated & ~2'b11;
		    ibus_valid <= 1'b1;
		 end
	       else if ((advance & !(is_16 & !next_pc[1])) |
			(have_data & !is_16 & next_pc[1]))
		 begin
		    pref_16    <= ibus_rdata[31:16];
		    pref_valid <= is_16 | next_pc[1];
		    ibus_a     <= (ibus_a + 3'd4) & core.PC_MASK;
		    ibus_valid <= 1'b1;
		 end
	       else if (pref_valid & is_16 & !next_pc[0])
		 begin
		    ibus_valid <= 1'b0;
		 end
	    end
       end // if (clken)
endmodule // fetch
