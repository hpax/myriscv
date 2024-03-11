//
// Pipeline control/hazard avoidance
//

`include "myriscv.vh"

module pipe_ctl #(
  parameter bit bypass_ctx = 1'b1
) (
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

  input	     d_busy,
  input	     e_busy,
  input	     m_busy,

  input	     e_kill, // Instruction killed in the E stage
  output     f_restart,

  output     f_stall,
  output     d_stall,
  output     e_stall,
  output     m_stall,

  // Bypass control
  output reg e_rs1_m,
  output reg e_rs1_w,
  output reg e_rs2_m,
  output reg e_rs2_w
);

   function logic regeq (input v1, regnum_t r1, input v2, regnum_t r2);
      regeq = v1 & v2 & ((r1.r == r2.r) & (!bypass_ctx || (r1.c == r2.c)));
   endfunction

   // Bubble due to W -> E forwarding necessary, for the following instruction
   // (i.e. this is a D stage signal.)
   logic	      d_me_hazard;
   always @(*)
     begin
	d_me_hazard = regeq(e_op.rd_m, e_op.rd, d_op.rs1_valid, d_op.rs1) |
		      regeq(e_op.rd_m, e_op.rd, d_op.rs2_valid, d_op.rs2);
     end

   // d_me_hazard has an effect very similar to e_busy.
   assign f_stall	= d_busy | e_busy | m_busy | d_me_hazard;
   assign d_stall	= e_busy | m_busy | d_me_hazard;
   assign e_stall	= m_busy;
   assign m_stall	= 1'b0;

   assign f_restart	= e_kill;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  e_valid_i <= 1'b0;
	  e_op      <= killed_op();
	  m_valid_i <= 1'b0;
	  m_op      <= killed_op();
	  e_rs1_m   <= 1'b0;
	  e_rs1_w   <= 1'b0;
	  e_rs2_m   <= 1'b0;
	  e_rs2_w   <= 1'b0;
       end
     else if (clken)
       begin
	  // Note: for INSN_NULL, a dummy op, PC still should reflect the
	  // expected next instruction; the E stage is allowed throw a
	  // branch mispredict kill otherwise.
	  //
	  // For INSN_KILLED, the PC is undefined, and the next valid instruction
	  // is defined to carry a new canonical PC.
	  if (e_kill) begin
	     e_valid_i <= 1'b0;
	     e_op      <= killed_op();
	  end else if (!d_valid_o) begin
	     e_valid_i <= 1'b0;
	     e_op      <= null_op(d_op.pc);
	  end else if (e_busy | (e_stall & e_valid_i)) begin
	     // Leave unchanged
	  end else begin
	     e_valid_i <= d_valid_o;
	     e_op      <= d_op;
	  end

	  if (!e_valid_o) begin
	     m_valid_i <= 1'b0;
	     m_op      <= null_op(e_op.pc);
	  end else if (m_busy | (m_stall & m_valid_i)) begin
	     // Leave unchanged
	  end else begin
	     m_valid_i <= e_valid_o;
	     m_op      <= e_op;
	  end

	  // Bypass control
	  e_rs1_m   <= regeq(e_op.rd_e, e_op.rd, d_op.rs1_valid, d_op.rs1);
	  e_rs1_w   <= regeq(e_op.rd_m, e_op.rd, d_op.rs1_valid, d_op.rs1);
	  e_rs2_m   <= regeq(e_op.rd_e, e_op.rd, d_op.rs2_valid, d_op.rs2);
	  e_rs2_w   <= regeq(e_op.rd_m, e_op.rd, d_op.rs2_valid, d_op.rs2);
       end // else: !if(~rst_n)
endmodule
