//
// Multiplier
//

module mult_comb
  #(
    parameter width = 32
    )
   (
    input [width-1:0]  d1,
    input	       ssign1,
    input [width-1:0]  d2,
    input	       ssign2,

    output [width-1:0] ql,
    output [width-1:0] qh
    );

   wire [width:0]      a = { d1[width-1] & ssign1, d1 };
   wire [width:0]      b = { d2[width-1] & ssign2, d2 };
   wire [2*width-1:0]  m = a * b;

   assign ql = m[width-1:0];
   assign qh = m[2*width-1:width];
endmodule // mult

module mult_sync_rtl
  #(
        parameter width = 32
    )
   (
    input	       clk,

    input [width-1:0]  d1,
    input [width-1:0]  d2,
    input [1:0]	       op, // MULL, MULH, MULHSU, MULHU
    input	       ssign2,

    output [width-1:0] q
    );

   localparam	       hw = (width/2) + 1;

   reg [width:0]       a;
   reg [width:0]       b;
   logic [2*width-1:0] m;
   reg		       is_high;

   always @(posedge clk)
     begin
	a <= { d1[width-1] & (op != 2'b11), d1 };
	b <= { d2[width-1] & ~op[1], d2 };
	is_high <= |op;

	m = a * b;
	q <= is_high ? m[2*width-1:width] : m[width-1:0];
     end
endmodule

module mult_sync_late_add
  #(
        parameter width = 32
    )
   (
    input	       clk,

    input [width-1:0]  d1,
    input [width-1:0]  d2,
    input [1:0]	       op, // MULL, MULH, MULHSU, MULHU
    input	       ssign2,

    output [width-1:0] q
    );

   localparam	       hw = (width/2) + 1;

   reg [width:0]       a;
   reg [width:0]       b;
   reg [width+1:0]     mp[0:3];
   reg		       is_high;

   always @(posedge clk)
     begin
	a <= { d1[width-1] & (op != 2'b11), d1 };
	b <= { d2[width-1] & ~op[1], d2 };
	is_high <= |op;

	mp[0] <= a[hw-1:0] * b[hw-1:0];
	mp[1] <= a[hw-1:0] * b[width:hw];
	mp[2] <= a[width:hw] * a[hw-1:0];
	mp[3] <= a[width:hw] * b[width:hw];
     end

   wire [2*width-1:0] m = mp[0]
		      + {mp[1] + mp[2], {hw{1'b0}}}
		      + {mp[3], {2*hw{1'b0}}};

   assign q = is_high ? m[2*width-1:width] : m[width-1:0];
endmodule

module mult_sync_alt
  #(
        parameter width = 32
    )
   (
    input	       clk,

    input [width-1:0]  d1,
    input [width-1:0]  d2,
    input [1:0]	       op, // MULL, MULH, MULHSU, MULHU
    input	       ssign2,

    output [width-1:0] q
    );

   localparam	       hw = (width/2) + 1;

   reg [width:0]       a;
   reg [width:0]       b;
   logic [2*width-1:0] m;
   reg		       is_high;

   altmult mult (
		 .clock0  ( clk ),
		 .dataa_0 ( d1 ),
		 .datab_0 ( d2 ),
		 .signa   ( op != 2'b11 ),
		 .signb   ( ~op[1] ),
		 .result ( m )
		 );

   always @(posedge clk)
     is_high <= |op;

   assign q = is_high ? m[2*width-1:width] : m[width-1:0];
endmodule
