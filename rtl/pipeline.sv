//
// Pipeline control/hazard avoidance
//

module pipe_ctl #(
  parameter bit bypass_ctx = 1'b1
) (
  input	     rst_n,
  input	     clk,
  input	     clken,

  input	     f_valid_o,
  input	     d_valid_o,
  input	     e_valid_o,
  input	     m_valid_o,

  output reg d_valid_i,
  output reg e_valid_i,
  output reg m_valid_i,

  input	     decoded_insn_t d_op,
  output     decoded_insn_t e_op,
  output     decoded_insn_t m_op,

  input	     e_ready,
  input	     d_ready,
  input	     m_ready,

  input	     e_kill, // Instruction killed in the E stage

  output     f_restart,

  output     f_stall,
  output     d_stall,
  output     e_stall,

  // Bypass control
  output reg e_rs1_m,
  output reg e_rs1_w,
  output reg e_rs2_m,
  output reg e_rs2_w
 );

   function logic regeq (input v1, regnum_t r1, input v2, regnum_t r2);
      regeq = (v1 & v2) && (r1.r == r2.r) && (!bypass_ctx || (r1.c == r2.c));
   endfunction

   // Bubble due to W -> E forwarding hazard when the output will
   // only have advanced to the M stage
   logic	      w_to_e_hazard;
   always @(*)
     begin
	w_to_e_hazard = regeq(e_op.rd_m, e_op.rd, d_op.rs1_valid, d_op.rs1) |
			regeq(e_op.rd_m, e_op.rd, d_op.rs2_valid, d_op.rs2);
     end

   assign f_stall    = ~d_ready | ~m_ready;
   assign d_stall    = ~m_ready;
   assign e_stall    = ~m_ready | w_to_e_hazard;

   assign f_restart  = e_kill;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  d_valid_i <= 1'b0;
	  e_op	    <= 'bx;
	  e_op.rd_e <= 1'b0;
	  e_op.rd_m <= 1'b0;
	  e_valid_i <= 1'b0;
	  m_op	    <= 'bx;
	  m_op.rd_m <= 1'b0;
	  m_valid_i <= 1'b0;
	  e_rs1_m   <= 1'b0;
	  e_rs1_w   <= 1'b0;
	  e_rs2_m   <= 1'b0;
	  e_rs2_w   <= 1'b0;
       end
     else if (clken)
       begin
	  d_valid_i <= f_valid_o & ~f_stall & ~e_kill;
	  e_valid_i <= d_valid_o & ~d_stall & ~e_kill;
	  m_valid_i <= e_valid_o & ~e_stall & ~e_kill;

	  if (~e_stall)
	    e_op     <= d_op;

	  if (m_ready)
	    m_op     <= e_op;

	  // Bypass control
	  e_rs1_m <= regeq(e_op.rd_e, e_op.rd, d_op.rs1_valid, d_op.rs1);
	  e_rs1_w <= regeq(m_op.rd_m, m_op.rd, d_op.rs1_valid, d_op.rs1);
	  e_rs2_m <= regeq(e_op.rd_e, e_op.rd, d_op.rs2_valid, d_op.rs2);
	  e_rs2_w <= regeq(m_op.rd_m, m_op.rd, d_op.rs2_valid, d_op.rs2);
       end // else: !if(~rst_n)
endmodule
