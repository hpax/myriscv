//
// Barrel shifter/rotator/extender/bit extractor
//
// Note that zero and sign extend are exactly equivalent to
// unsigned and signed extract with a shift count of 0.
//
// Cyclone IV EP4CE15F23C8 sync_shifter sample results:
//
// width = 16: 110 LEs, 214 MHz
// width = 32: 325 LEs, 188 MHz
// width = 64: 605 LEs, 152 MHz
//
// Width must be a power of 2.
//

`include "myriscv.vh"

module rotate
  #(
    parameter width = 32
    )
   (
    input  [$clog2(width)-1:0] cnt,
    input  [width-1:0] d,
    output logic [width-1:0] q
    );
// *** Variant 1
//   wire [2*width-1:0]  in = { d, {width{1'b0}} };
//   wire [2*width-1:0]  shr = in >> cnt;
//
//   always @(*)
//     q = shr[width-1:0] | shr[2*width-1:width];

// *** Variant 2
//   always @(*)
//     for (integer i = 0; i < width; i++)
//       q[i] = d[(i+cnt) & (width-1)];

// *** Variant 3
   always @(*)
     begin
	logic [width-1:0] xa;

	xa = d;
	for (integer i = 0; i < $clog2(width); i++)
	  begin
	     if (cnt[i])
	       begin
		  logic [$clog2(width):0] ioffs;
		  logic [width-1:0] xb;

		  ioffs = 'b0;
		  ioffs[i] = 1'b1;
		  for (integer j = 0; j < width; j++)
		    begin
		       logic [$clog2(width)-1:0] joffs;
		       joffs = j + ioffs;
		       xb[j] = xa[joffs];
		    end
		  xa = xb;
	       end
	  end // for (integer i = 0; i < $clog2(width); i++)

	q = xa;
     end
endmodule

//
// Construct the output mask.
//
module maskgen
  #(
    parameter width = 32
    )
   (
    input [$clog2(width)-1:0] cnt,
    input [$clog2(width)-1:0] pos,
    output reg [width-1:0] q
    );

   // *** Variant 1
`ifdef NOT
   always @(*)
     begin
	for (integer i = 0; i < width; i = i + 1)
	  begin
	     logic [$clog2(width)-1:0] delta;
	     delta = (width+i) - pos;
	     q[i] = delta < cnt;
	  end
     end
`endif //  `ifdef NOT

   always @(*)
     begin
     end

   // *** Variant 2
`ifdef NOT
   always @(*)
     begin
	reg [width-1:0]		       qtmp;
	for (integer i = 0; i < width; i = i + 1)
	  qtmp[i] = i < cnt;
	for (integer i = 0; i < width; i = i + 1)
	  q[i] = qtmp[(i-pos) & (width-1)];
     end
`endif

   // *** Variant 3
   always @(*)
     begin
	logic [width-1:0] xa;

	// Mask of cnt bits
	for (integer i = 0; i < width; i++)
	  xa[i] = i < cnt;

	// Rotate left
	for (integer i = 0; i < $clog2(width); i++)
	  begin
	     if (cnt[i])
	       begin
		  logic [$clog2(width)-1:0] ioffs;
		  logic [width-1:0] xb;

		  ioffs = 'b0;
		  ioffs[i] = 1'b1;
		  for (integer j = 0; j < width; j++)
		    begin
		       logic [$clog2(width)-1:0] joffs;
		       joffs = j - ioffs;
		       xb[j] = xa[joffs];
		    end
		  xa = xb;
	       end
	  end // for (integer i = 0; i < $clog2(width); i++)

	q = xa;
     end // always @ (*)

   // *** Variant 4
`ifdef NOT
   always @(*)
     begin
	logic [width-1:0] xa;

	// Mask of cnt bits
	for (integer i = 0; i < width; i++)
	  xa[i] = i < cnt;

	// Shift left
	q = xa << pos;
     end
`endif
endmodule

//
// Sign bit multiplexer
//
module sign_mux
  #(
    parameter width = 32
    )
   (
    input [$clog2(width)-1:0] pos,
    input sand,
    input sxor,
    input [width-1:0] d,
    output reg q
    );

   always @(*)
     q = (d[pos] & sand) ^ sxor;
endmodule // sign_mux

//
// See shiftops.odt for description of the input signals.
//
module shifter_core
  #(
    // Note: a width that is not a power of 2 is theoretically
    // supported, but is likely to produce a very inefficient circuit.
    parameter width = 32
    )
  (
   input [$clog2(width)-1:0] rcnt, // Rotation count
   input [$clog2(width)-1:0] mpos, // First output bit to be masked
   input [$clog2(width)-1:0] mcnt, // Number of output bits to be masked
   input [$clog2(width)-1:0] spos, // Sign bit position
   input		     sand, // Sign bit ANDed with this value
   input		     sxor, // Sign bit XORed with this value

   input  [width-1:0]	     d,
   output [width-1:0]	     q
   );

   wire			     sign_bit;
   sign_mux #(.width(width)) sign_mux (.pos(spos), .sand (sand), .sxor(sxor),
				       .d(d), .q(sign_bit));

   // Rotation using crossbar
   wire [width-1:0]	    d_rot;
   rotate #(.width(width)) rotate (.cnt(rcnt), .d(d), .q(d_rot));

   // Note: for a left shift, only invert the mask if the mask would not
   // end up zero.
   wire [width-1:0]	    mask;
   maskgen #(.width(width)) maskgen (.cnt(mcnt), .pos(mpos), .q(mask));

   assign q = (d_rot & ~mask) | ({width{sign_bit}} & mask);
endmodule // shifter

module shifter
  #(
    parameter width = 32
    )
   (
    input [$clog2(width)-1:0] shamt, // Shift amount operand
    input		      shiftop_t op,

    input [width-1:0]	      d,
    output [width-1:0]	      q
    );

   logic [$clog2(width)-1:0]  rcnt;
   logic [$clog2(width)-1:0]  mpos;
   logic [$clog2(width)-1:0]  mcnt;
   logic [$clog2(width)-1:0]  spos;
   logic		      sand;
   logic		      sxor;

   always @(*)
     begin
	unique case (op.rcnt)
	  2'b00:   rcnt = 'b0;
	  2'b10:   rcnt = shamt;
	  2'b11:   rcnt = -shamt;
	  default: rcnt = 'bx;
	endcase // unique case (op.rcnt)

	unique case (op.mcnt)
	  3'b000:  mcnt = 'd0;
	  3'b001:  mcnt = 'd1;
	  3'b011:  mcnt = -'sd1;
	  3'b100:  mcnt = -'sd8;
	  3'b101:  mcnt = -'sd16;
	  3'b110:  mcnt = shamt;
	  3'b111:  mcnt = -shamt;
	  default: mcnt = 'bx;
	endcase // unique case (op.mcnt)

	unique case (op.mpos)
	  2'b00:   mpos = 'b0;
	  2'b01:   mpos = 'b1;
	  2'b10:   mpos = shamt;
	  2'b11:   mpos = -mcnt;
	  default: mpos = 'bx;
	endcase // unique case (op.mpos)

	unique case (op.spos)
	  2'b00:   spos = 'b0;
	  2'b01:   spos = -'sb1;
	  2'b10:   spos = shamt;
	  2'b11:   spos = -mcnt-1'b1;
	  default: spos = 'bx;
	endcase

	sand = op.sbit[1];
	sxor = op.sbit[0];
     end // always @ (*)

   shifter_core core (
		      .rcnt (rcnt),
		      .mpos (mpos),
		      .mcnt (mcnt),
		      .spos (spos),
		      .sand (sand),
		      .sxor (sxor),
		      .d    (d),
		      .q    (q));
endmodule
