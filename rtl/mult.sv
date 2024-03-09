//
// Multiplier
//

//
// This is the hardware-dependent module; it can be reimplemented
// using device-specific idioms if desired. It is expected to present
// the outputs after one cycle, but is allowed a fairly significant
// combinatorial latecy after the clock.
//
// The clock enable MUST BE HONORED; the outputs MUST NOT CHANGE if the
// clock enable is disabled.
//
module mult
  #(
    parameter width = 32,
    parameter bit mux_late = 1'b1 // High/low as combinatorial MUX
    )
   (
  input			 rst_n,
  input			 clk,
  input			 clken,

  input [width-1:0]	 src1,
  input			 ssign1, // src1 is signed
  input [width-1:0]	 src2,
  input			 ssign2, // src2 is signed
  input			 high, // q should contains the high half result

  output	[width-1:0] q,
  output	[width-1:0] ql
    );

   wire signed [width:0]      a = { src1[width-1] & ssign1, src1 };
   wire signed [width:0]      b = { src2[width-1] & ssign2, src2 };
   wire signed [2*width-1:0]  m = a * b;

   reg [width-1:0]	      l_q;
   reg [width-1:0]	      h_q;
   reg			      high_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	l_q    <= 'bx;
	h_q    <= 'bx;
	high_q <= 1'bx;
     end else if (clken) begin
	high_q <= high;
	l_q <= m[width-1:0];
	h_q <= (high | mux_late) ? m[2*width-1:width] : m[width-1:0];
     end

   assign q  = (~high_q & mux_late) ? l_q : h_q;
   assign ql = l_q;
endmodule // mult

module multiplier
  #(
        parameter width = 32
    )
   (
  input		     rst_n,
  input		     clk,

  input		     e_valid,	// Start operation and save results
  input [width-1:0]  e_src1,
  input [width-1:0]  e_src2,
  input [1:0]	     e_op,	// MULL, MULH, MULHSU, MULHU

  output [width-1:0] m_mul_o,	// Main output
  output [width-1:0] m_mull_o	// Can be forwarded to E on a subsequent MULL
  );

   wire		       e_ssign1 = ~&e_op;	// MULL, MULH, MULHSU
   wire		       e_ssign2 = ~e_op[1];	// MULL, MULH
   wire		       e_high = |e_op;		// MULH, MULHSU, MULHU

   mult mult (
     .rst_n	( rst_n ),
     .clk	( clk ),
     .clken	( e_valid ),
     .src1	( e_src1 ),
     .ssign1	( e_ssign1 ),
     .src2	( e_src2 ),
     .ssign2	( e_ssign2 ),
     .high	( e_high ),
     .q		( m_mul_o ),
     .ql	( m_mull_o )
     );
endmodule
