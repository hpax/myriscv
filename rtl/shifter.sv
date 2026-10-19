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

// Low-level rotator implementation
module sh_rot
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
// Rotated output
module sh_rotate
  #(
    parameter width = 32
    )
   (
    input [$clog2(width)-1:0] shamt,
    input shiftop_t           op,
    input [width-1:0]	      d,
    output [width-1:0]        q
    );

   logic [$clog2(width)-1:0]  cnt;

   always @(*)
     unique casez (op.srot)
       SROT_NONE:  cnt = 'b0;
       SROT_RIGHT: cnt = shamt;
       SROT_LEFT:  cnt = -shamt;
       default:    cnt = 'bx;
     endcase

   sh_rot rot (.cnt(cnt), .d(d), .q(q));
endmodule


//
// Construct the output mask.
// Note that a 1 here means the output is the "sign" bit
// and 0 means the output of the rotate array.
//
module sh_maskgen
  #(
    parameter width = 32
    )
   (
    input [$clog2(width)-1:0] shamt, // Shift amount operand
    input shiftop_t           op,
    output logic [width-1:0]  q
    );

   always @(*) begin
      logic [$clog2(width)-1:0] amt;

      unique case (op.smpos)
	SMPOS_CNT:  amt = shamt;
	SMPOS_WIMM: amt = op.wimm;
	default:    amt = 'bx;
      endcase

      for (int i = 0; i < width; i++) begin
	 logic [$clog2(width)-1:0] ii;
	 ii = i;
	 unique case ( op.smask )
	   SMASK_ONE:  q[i] = ii == amt;
	   SMASK_LO:   q[i] = ii < amt;
	   SMASK_HI:   q[i] = ii > ~amt;
	   SMASK_UP:   q[i] = amt && ii >= amt;
	   default:    q[i] = 1'bx;
	 endcase
      end
   end
endmodule

//
// Sign bit multiplexer
//
module sh_signmux
  #(
   parameter width = 32,
   parameter wbits = $clog2(width)
    )
   (
    input [wbits-1:0]	shamt,
    input shiftop_t	op,
    input [width-1:0]	d,
    output logic	q
    );

   always_comb begin
      logic [wbits-1:0] pos;
      logic   [wbits:0] epos;

      epos = op.wimm - 1'b1;
      if (op.spos)
	epos += shamt;

      // Saturating addition.
      pos = epos[wbits-1:0] | {wbits{epos[wbits]}};
      q = (d[pos] & op.sand) ^ op.sxor;
   end
endmodule // sign_mux

//
// Output mux
//
module sh_outmux
  #(
    parameter width = 32
  )
  (
    input [width-1:0]	       d_rot,
    input [width-1:0]	       mask,
    input		       signbit,
    output [width-1:0]	       q
  );
   assign q = (d_rot & ~mask) | ({width{signbit}} & mask);
endmodule

//
// See shiftops.odt for description of the input signals.
//
module shifter
  #(
    // Make this a non-power-of-2 at your own risk
    parameter width = 32
    )
  (
  input [$clog2(width)-1:0] shamt, // shift amount
  input			    shiftop_t op,

  input  [width-1:0]	    d,
  output [width-1:0]	    q
   );

   // "Sign" bit MUX
   wire			     signbit;
   sh_signmux #(.width(width))
   signmux (.shamt(shamt), .op(op), .d(d), .q(signbit));

   // Rotator
   wire [width-1:0]	    d_rot;
   sh_rotate #(.width(width))
   rotate (.shamt(shamt), .op(op), .d(d), .q(d_rot));

   // Mask generator
   wire [width-1:0]	    mask;
   sh_maskgen #(.width(width))
   maskgen (.shamt(shamt), .op(op), .q(mask));

   // Combine using output MUX
   sh_outmux #(.width(width))
   outmux (.d_rot(d_rot), .mask(mask), .signbit(signbit), .q(q));
endmodule // shifter
