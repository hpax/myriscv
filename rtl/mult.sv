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

`ifdef ALTERA_RESERVED_QIS
// This seems worse than the generic result?!
`define ALTERA_MULT 1
`endif

`ifdef NORMAL

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


`ifdef ALTERA_MULT		// Altera IP

   wire [width-1:0]	      l_q;
   wire [width-1:0]	      h_q;

   altmult am (
     .clock0  ( clk ),
     .ena0    ( clken ),
     .dataa_0 ( src1 ),
     .datab_0 ( src2 ),
     .signa   ( ssign1 ),
     .signb   ( ssign2 ),
     .result  ( {h_q, l_q} )
     );

`else				// Generic

   logic signed [width:0]   a;
   logic signed [width:0]   b;

   logic [width-1:0]	      l_q;
   logic [width-1:0]	      h_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	a	<= 'bx;
	b	<= 'bx;
     end else if (clken) begin
	a	<= $signed({ src1[width-1] & ssign1, src1 });
	b	<= $signed({ src2[width-1] & ssign2, src2 });
     end

   always @(*) begin
      logic signed [2*width-1:0] m;

      m = a * b;

      l_q = m[width-1:0];
      h_q = m[2*width-1:width];
   end
`endif

   reg				 high_q;
   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       high_q <= 1'bx;
     else if (clken)
       high_q <= high;

   assign q  = ~high_q ? l_q : h_q;
   assign ql = l_q;
endmodule // mult

`endif

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

  output [width-1:0] m_mulh_o,	// Main output
  output [width-1:0] m_mull_o	// Can be forwarded to E on a subsequent MULL
  );

   wire		     is_mulh   = e_op == 2'b01;
   wire		     is_mulhsu = e_op == 2'b10;

   wire		     e_ssign1  = is_mulh | is_mulhsu;
   wire		     e_ssign2  = is_mulhsu;

   mult mult (
     .rst_n	( rst_n ),
     .clk	( clk ),
     .clken	( e_valid ),
     .src1	( e_src1 ),
     .ssign1	( e_ssign1 ),
     .src2	( e_src2 ),
     .ssign2	( e_ssign2 ),
     .qh	( m_mulh_o ),
     .ql	( m_mull_o )
     );
endmodule

// Implementation which defers all the adds to the second clock.
`ifdef MULT_BALANCED_SIZES
module mult
  #(
    parameter width = 32
    )
   (
  input			 rst_n,
  input			 clk,
  input			 clken,

  input [width-1:0]	 src1,
  input			 ssign1, // src1 is signed
  input [width-1:0]	 src2,
  input			 ssign2, // src2 is signed

  output	[width-1:0] ql,
  output	[width-1:0] qh
    );

   logic [31:0]		    ll;
   logic [31:0]		    hl;
   logic [31:0]		    lh;
   logic [31:0]		    hh;

   altmult16 mul_ll (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[15:0]),
     .datab_0 (src2[15:0]),
     .signa (1'b0),
     .signb (1'b0),
     .result (ll)
     );

   altmult16 mul_lh (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[15:0]),
     .datab_0 (src2[31:16]),
     .signa (1'b0),
     .signb (ssign2),
     .result (lh)
     );

   altmult16 mul_hl (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[31:16]),
     .datab_0 (src2[15:0]),
     .signa (ssign1),
     .signb (1'b0),
     .result (hl)
     );

   altmult16 mul_hh (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[31:16]),
     .datab_0 (src2[31:16]),
     .signa (ssign1),
     .signb (ssign2),
     .result (hh)
     );

   reg		ssign1_q;
   reg		ssign2_q;
   always @(posedge clk)
     if (clken) begin
	ssign1_q <= ssign1;
	ssign2_q <= ssign2;
     end

   wire [32:0] qlow  = ll + { lh[15:0], 16'b0 } + { hl[15:0], 16'b0 };
   wire signed [16:0] lhs = { lh[31] & ssign2_q, lh[31:16] };
   wire signed [16:0] hls = { hl[31] & ssign1_q, hl[31:16] };
   wire signed [17:0] hllh = lhs + hls;

   assign ql = qlow[31:0];
   assign qh = $signed(hh + qlow[32]) + hllh;
endmodule

`else

module mult
  #(
    parameter width = 32
    )
   (
  input			 rst_n,
  input			 clk,
  input			 clken,

  input [width-1:0]	 src1,
  input			 ssign1, // src1 is signed
  input [width-1:0]	 src2,
  input			 ssign2, // src2 is signed

  output [width-1:0]	 ql,
  output [width-1:0]	 qh
    );

   logic [35:0]	    ll;
   logic [32:0]	    hl;	// Extended by multiplier
   logic [32:0]	    lh;	// Extended by multiplier
   logic [27:0]	    hh;

   altmult18 mul_ll (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[17:0]),
     .datab_0 (src2[17:0]),
     .signa (1'b0),
     .signb (1'b0),
     .result (ll)
     );

   altmult18x14 mul_lh (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[17:0]),
     .datab_0 (src2[31:18]),
     .signa (1'b0),
     .signb (ssign2),
     .result (lh)
     );

   altmult18x14 mul_hl (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src2[17:0]),
     .datab_0 (src1[31:18]),
     .signa (1'b0),
     .signb (ssign1),
     .result (hl)
     );

   altmult14 mul_hh (
     .clock0 (clk),
     .ena0 (clken),
     .dataa_0 (src1[31:18]),
     .datab_0 (src2[31:18]),
     .signa (ssign1),
     .signb (ssign2),
     .result (hh)
     );

   always @(*) begin
      logic [18:0] lhhs_lo;
      logic [63:0] q;
      logic signed [19:0] middle;
      logic signed [15:0] lhhs_hi;

      lhhs_lo	  = lh[17:0] + hl[17:0];
      q[17:0]	  = ll[17:0];
      middle	  = ll[35:18] + lhhs_lo;
      q[35:18]	  = middle[17:0];

      lhhs_hi	  = $signed(lh[32:18] + hl[32:18]) + $signed(middle[19:18]);
      q[63:36]	  = hh + lhhs_hi;

      ql	  = q[31:0];
      qh	  = q[63:32];
   end
endmodule

`endif
