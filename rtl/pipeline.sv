//
// Pipeline control/hazard avoidance
//

`include "myriscv.vh"

module pipe_ctl
(
  input	     rst_n,
  input	     clk,
  input	     clken,

  input	     d_valid_i,		// Actually output from the fetch unit
  input	     d_valid_o,
  input	     e_valid_o,
  input	     m_valid_o,

  output reg e_valid_i,
  output reg m_valid_i,

  input	     decoded_insn_t d_op,
  output     decoded_insn_t e_op,
  output     decoded_insn_t m_op,
  output     decoded_insn_t w_op,

  input	     d_busy,
  input	     e_busy,
  input	     m_busy,

  input	     m_kill, // Instruction killed in the E stage, but delayed one
  output     f_restart,

  output     f_stall,
  output     d_stall,
  output     e_stall,
  output     m_stall,

  // Bypass control
  output reg d_rs1_e,
  output reg d_rs1_m,
  output reg d_rs1_w,
  output reg d_rs2_e,
  output reg d_rs2_m,
  output reg d_rs2_w
);

   function automatic logic regeq (input v1, regnum_t r1, input v2, regnum_t r2);
      regeq = v1 & v2 & (r1 == r2);
   endfunction

   // Bubble due to W -> E forwarding necessary, for the following instruction
   // (i.e. this is a D stage signal.)
   reg	      d_me_hazard;
   always @(*)
     d_me_hazard = d_valid_o &
		   (regeq(e_op.rd_m, e_op.rd, d_op.rs1_valid, d_op.rs1) |
		    regeq(e_op.rd_m, e_op.rd, d_op.rs2_valid, d_op.rs2));

   // Bypass control: pick the source for the next execution of the
   // E stage.
   always @(*) begin
      d_rs1_e	  = regeq(e_op.rd_e, e_op.rd, d_op.rs1_valid, d_op.rs1);
      d_rs1_m	  = regeq(m_op.rd_m, m_op.rd, d_op.rs1_valid, d_op.rs1);
      d_rs1_w	  = regeq(w_op.rd_m, w_op.rd, d_op.rs1_valid, d_op.rs1);
      d_rs2_e	  = regeq(e_op.rd_e, e_op.rd, d_op.rs2_valid, d_op.rs2);
      d_rs2_m	  = regeq(m_op.rd_m, m_op.rd, d_op.rs2_valid, d_op.rs2);
      d_rs2_w	  = regeq(w_op.rd_m, w_op.rd, d_op.rs2_valid, d_op.rs2);
   end

   // The W stage always accepts
   wire w_busy = 1'b0;

   // d_me_hazard has an effect very similar to e_busy.

   assign m_stall	= w_busy;
   assign e_stall	= (m_valid_o & m_stall) | m_busy;
   assign d_stall	= (e_valid_o & e_stall) | e_busy | d_me_hazard;
   assign f_stall	= (d_valid_o & d_stall) | d_busy;

   assign f_restart	= m_kill;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  e_valid_i <= 1'b0;
	  e_op      <= killed_op();
	  m_valid_i <= 1'b0;
	  m_op      <= killed_op();
	  w_op      <= killed_op();
       end
     else if (clken)
       begin

	  // If the undead flag is clear, this is a dead instruction.
	  // Even if the undead flag is clear, if pc_valid is set, the
	  // PC still should reflect the expected next instruction;
	  // the E stage is allowed throw a branch mispredict kill
	  // otherwise.
	  //
	  // If pc_valid = 0, the PC is undefined, but the next
	  // instruction with pc_valid = 1 is *required* to carry a
	  // new canonical (non-speculative) PC.
	  if (m_kill) begin
	     e_valid_i   <= 1'b0;
	     e_op        <= killed_op();
	  end else if ((e_stall & e_valid_i) | e_busy) begin
	     // Leave unchanged
	  end else begin
	     e_valid_i <= 1'b1;
	     e_op      <= d_op;
	     if (~d_valid_o | d_stall) begin
		e_valid_i   <= 1'b0;
		e_op.undead <= 1'b0;
		e_op.rd_e   <= 1'b0;
		e_op.rd_m   <= 1'b0;
	     end
	  end

	  // A private flag is passed between the E stage to the M
	  // stage if the latter should ignore the instruction due to
	  // it being a trap. e_valid_o will be deasserted after the
	  // kill proper.
	  if (!e_valid_o) begin
	     m_valid_i	 <= 1'b0;
	     m_op	 <= e_op;
	     m_op.undead <= 1'b0;
	     m_op.rd_m   <= 1'b0;
	  end else if (m_busy | (m_stall & m_valid_i)) begin
	     // Leave unchanged
	  end else begin
	     m_valid_i <= e_valid_o;
	     m_op      <= e_op;
	     // Data in the E stage is forwarded to the M stage,
	     // so it isn't in the register file yet.
	     m_op.rd_m <= e_valid_o & (e_op.rd_e | e_op.rd_m);
	  end

	  // Not actually used in synthesis, but useful for debugging
	  if (m_valid_o)
	    w_op    <= m_op;
       end // else: !if(~rst_n)
endmodule
