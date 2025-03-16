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

  output [width-1:0] m_mulh_o,	// High half output
  output [width-1:0] m_mull_o	// Low half output
  );

   wire		     is_mulh   = e_op == 2'b01;
   wire		     is_mulhsu = e_op == 2'b10;

   wire		     e_ssign1  = is_mulh | is_mulhsu;
   wire		     e_ssign2  = is_mulh;

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
     .clock0  (clk),
     .ena0    (clken),
     .dataa_0 (src1[15:0]),
     .datab_0 (src2[15:0]),
     .signa   (1'b0),
     .signb   (1'b0),
     .result  (ll)
     );

   altmult16 mul_lh (
     .clock0  (clk),
     .ena0    (clken),
     .dataa_0 (src1[15:0]),
     .datab_0 (src2[31:16]),
     .signa   (1'b0),
     .signb   (ssign2),
     .result  (lh)
     );

   altmult16 mul_hl (
     .clock0  (clk),
     .ena0    (clken),
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

   wire [35:0]		 ll;
   wire signed [33:0]	 lhhl;
   wire [27:0]		 hh;

   altmult18 mul_ll (
     .clock0  (clk),
     .ena0    (clken),
     .dataa_0 (src1[17:0]),
     .datab_0 (src2[17:0]),
     .signa   (1'b0),
     .signb   (1'b0),
     .result  (ll)
     );

   // Two u18 x s15 multipliers added together
   altmult18x15x2 mul_lhhl (
     .clock0  (clk),
     .ena0    (clken),
     .dataa_0 (src1[17:0]),
     .datab_0 ({src2[31] & ssign2, src2[31:18]}),
     .dataa_1 (src2[17:0]),
     .datab_1 ({src1[31] & ssign1, src1[31:18]}),
     .result  (lhhl)
     );

   altmult14 mul_hh (
     .clock0  (clk),
     .ena0    (clken),
     .dataa_0 (src1[31:18]),
     .datab_0 (src2[31:18]),
     .signa   (ssign1),
     .signb   (ssign2),
     .result  (hh)
     );

   logic [63:0]		 q;

   always @(*) begin
      q[17:0]  = ll[17:0];
      q[63:18] = $signed(lhhl) + $signed({ hh, ll[35:18] });
   end

   assign ql = q[31:0];
   assign qh = q[63:32];
endmodule

`endif
