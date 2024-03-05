//
// Pipeline control
//

module pipe_ctl
  #(
    parameter	  contexts   = 1,
    parameter	  ctx_bits   = $min($clog2(contexts), 1),
    parameter	  reg_bits   = ctx_bits+5,
    parameter bit bypass_ctx = contexts > 1
    )
(
 input			   rst_n,
 input			   clk,

 input			   f_valid_out,
 input			   d_valid_out,
 input			   e_valid_out,
 input			   m_valid_out,

 output reg		   d_valid_in,
 output reg		   e_valid_in,
 output reg		   m_valid_in,

 input [4:0]		   d_rs1,
 input			   d_rs1_valid,
 input [ctx_bits-1:0]	   d_rs1_ctx,

 input [4:0]		   d_rs2, // Only the register part
 input			   d_rs2_valid,
 input [ctx_bits-1:0]	   d_rs2_ctx,

 input [4:0]		   d_rd,
 input			   d_rd_valid,
 input [ctx_bits-1:0]	   d_rd_ctx,
 input			   d_rd_e, // rd data ready from E stage output
 input			   d_rd_m, // rd data ready from M stage output

 input			   d_csrw,
 input			   d_csrr,
 input			   d_jump,

 input			   d_ready,
 input			   m_ready,

 input			   e_kill, // Instruction killed in the E stage

 output			   f_restart,

 output			   f_stall,
 output			   d_stall,
 output			   e_stall,

 // Note: this logic may assert _m == _w; in that case the _m bypass
 // should prevail.
 output reg		   e_rs1_m, // E stage get rs1 from M stage input
 output reg		   e_rs1_w, // E stage get rs1 from W stage input
 output reg		   e_rs2_m, // E stage get rs2 from M stage input
 output reg		   e_rs2_w, // E stage get rs2 from W stage input

 output reg [4:0]	   e_rd,
 output reg		   e_rd_valid,
 output reg [ctx_bits-1:0] e_rd_ctx,
 output reg [4:0]	   m_d,
 output reg		   m_rd_valid,
 output reg [4:0]	   m_rd_ctx
 );

   function logic regeq (input v1, input [4:0] r1, input [ctx_bits-1:0] c1,
			 input v2, input [4:0] r2, input [ctx_bits-1:0] c2);
      regeq = (v1 & v2) && (r1 == r2) && (!bypass_ctx || (c1 == c2));
   endfunction

   // Bubble due to W -> E forwarding hazard when the output will
   // only have advanced to the M stage
   logic	      w_to_e_hazard;
   always @(*)
     begin
	w_to_e_hazard = regeq(e_rd_m,      e_rd,  e_rd_ctx,
			      d_rs1_valid, d_rd1, d_rs1_ctx) |
			regeq(e_rd_m,      e_rd,  e_rd_ctx,
			      d_rs2_valid, d_rs2, d_rs2_ctx);
     end

   assign f_stall    = ~d_ready | ~m_ready;
   assign d_stall    = ~m_ready;
   assign e_stall    = ~m_ready | w_to_e_hazard;

   assign f_restart  = e_kill;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  e_rd     <=  'bx;
	  e_rd_ctx <= 1'b0;
	  e_rd_e   <= 1'b0;
	  e_rd_m   <= 1'b0;
	  m_rd     <=  'bx;
	  m_rd_m   <= 1'b0;
	  e_rs1_m  <= 1'b0;
	  e_rs1_w  <= 1'b0;
	  e_rs2_m  <= 1'b0;
	  e_rs2_w  <= 1'b0;
       end
     else
       begin
	  d_valid_in <= f_valid_out & ~f_stall & ~e_kill;
	  e_valid_in <= d_valid_out & ~d_stall & ~e_kill;
	  m_valid_in <= e_valid_out & ~e_stall & ~e_kill;

	  if (~e_stall)
	    begin
	       e_rd     <= d_rd;
	       e_rd_ctx <= d_rd_ctx;
	       e_rd_e   <= d_rd_e & ~d_stall & ~e_kill;
	       e_rd_m   <= d_rd_m & ~d_stall & ~e_kill;
	    end
	  if (m_ready)
	    begin
	       m_rd     <= e_rd;
	       m_rd_ctx <= e_rd_ctx;
	       m_rd_m   <= e_rd_m;
	    end

	  // Bypass control
	  e_rs1_m <= regeq(e_rd_e,      e_rd,  e_rd_ctx,
			   d_rs1_valid, d_rs1, d_rs1_ctx);
	  e_rs1_w <= regeq(m_rd_m,      m_rd,  m_rd_ctx,
			   d_rs1_valid, d_rs1, d_rs1_ctx);
	  e_rs2_m <= regeq(e_rd_e,      e_rd,  e_rd_ctx,
			   d_rs2_valid, d_rs2, d_rs2_ctx);
	  e_rs2_w <= regeq(m_rd_m,      m_rd,  m_rd_ctx,
			   d_rs2_valid, d_rs2, d_rs2_ctx);
       end // else: !if(~rst_n)
endmodule
