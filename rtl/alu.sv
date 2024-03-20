//
// ALU operations
//
// Standard extensions: Zba Zbb Zbs Zicond
// WITH_extensions enables some additional features:
//	sh[123]sub	- same opcodes as sh[123]add but with funct7[5] = 1
//	cpopz, cto, clo	- count the inverse; opcodes imm[4] = 1
//			  -> only available if BITCNT_SEPARATE = 0
//
// Note: M/Zmmul is done separately due to timing.
//

`include "myriscv.vh"

module alu_decode
(
    input  decoded_insn_t op,
    output aluctl_t ctl
    );

   always @(*)
     begin
	ctl	     = 'bx;
	ctl.unit     = ALUSRC_ERR;
	ctl.shadd    = 2'b00;		// No preshift
	ctl.cond     = cond_t'(op.funct3);
	ctl.bcop     = {op.rs2.r[4], op.rs2.r[1:0]};

	unique case (op.itype)
	  INSN_BR: begin
	     // A branch is an SET as far as the ALU is
	     // concerned...
	     ctl.unit   = ALUSRC_SET;
	  end

	  INSN_ALU: begin
	     logic [6:0] funct7;

	     if (!op.rs2_valid && op.funct3[1:0] != 2'b01)
	       funct7 = 7'b0;
	     else
	       funct7 = op.funct7;

	     unique casez ({funct7, op.funct3})
	       { 7'b0?0_0000, ALU_ADD }: begin
		  ctl.unit = ALUSRC_ADD;
		  ctl.invert = funct7[5];
	       end
	       { 7'b0?1_0000, 3'b??0 }: begin // shXadd, shXsub
		  if (core.WITH_Zba &&
		      (core.WITH_Zbasub || !funct7[5])) begin
		     ctl.unit   = ALUSRC_ADD;
		     ctl.shadd  = op.funct3[2:1];
		     ctl.invert = funct7[5];
		  end
	       end
	       { 7'b000_0000, ALU_SLL }: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b11_00_100_xx_0_0; // SLL
	       end
	       { 7'b001_0100, ALU_SLL },
		 { 7'b01?_0100, ALU_SLL }: begin // BSET, BCLR, BINV
		    ctl.unit = ALUSRC_SHIFT;
		    ctl.shiftop = { 9'b00_10_001_10,
		      funct7[5:4] == 2'b11, funct7[5:4] != 2'b10 };
		 end
	       { 7'b011_0000, ALU_SLL }: begin
		  unique casez ({!op.rs2_valid, op.rs2.r})
		    6'b1_?00??: begin // CTZ, CLZ, CPOP (+inverses)
		       if (!core.STRICT_UNDEFINED ||
			 op.rs2.r[1:0] != 2'b11)
			 if (core.WITH_bitcntinv || !op.rs2.r[4])
			   ctl.unit = ALUSRC_BITCNT;
		    end
		    6'b1_0010?: begin	// SEXT.B/H
		       ctl.unit = ALUSRC_SHIFT;
		       ctl.shiftop = { 4'b00_11, op.rs2.r[2:0], 4'b11_1_0 };
		    end
		    6'b0_?????: begin
		       ctl.unit = ALUSRC_SHIFT;
		       ctl.shiftop = 11'b11_xx_000_xx_x_x; // ROL
		    end
		    default: begin
		       // Do nothing
		    end
		  endcase // unique casez ({!op.rs2_valid, op.rs2.r})
	       end // case: { 7'b011_0000, ALU_SLL }

	       { 7'b000_0000, ALU_SRL }: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b10_11_100_xx_0_0; // SRL
	       end
	       { 7'b010_0000, ALU_SRL }: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b10_11_100_11_1_0; // SRA
	       end
	       { 7'b001_0100, ALU_SRL }: begin
		  unique casez ({~op.rs2_valid, op.rs2.r})
		    6'b1_00111: begin // ORC.B
		       // In the future, rs2 might be a control mask for a more
		       // advanced combination instruction
		       ctl.unit = ALUSRC_ORC;
		    end
		    default: begin
		       // Do nothing
		    end
		  endcase
	       end
	       { 7'b010_0100, ALU_SRL }: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b10_01_011_xx_0_0; // BEXT(U)
	       end
	       { 7'b011_0000, ALU_SRL }: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b10_xx_000_xx_x_x; // ROR
	       end
	       { 7'b011_0100, ALU_SRL }: begin
		  unique casez ({~op.rs2_valid, op.rs2.r})
		    6'b1_11000: begin // REV8
		       // In the future, rs2 might be a control mask for a more
		       // advanced bitswap instruction
		       ctl.unit = ALUSRC_REV;
		    end
		    default: begin
		       // Do nothing
		    end
		  endcase
	       end
	       { 7'b000_00??, ALU_SLT },
	       { 7'b000_00??, ALU_SLTU }: begin
		  if (core.WITH_setext || !funct7[1:0]) begin
		     // bits 1:0 in funct7 can be used to obtain the
		     // other possible condition codes
		     ctl.cond[2:1]  = funct7[1:0] ^ 2'b01;
		     ctl.unit	    = ALUSRC_SET;
		  end
	       end
	       { 7'b0?0_0000, ALU_XOR },
		 { 7'b0?0_0000, ALU_OR },
		 { 7'b0?0_0000, ALU_AND }: begin
		    ctl.unit   = ALUSRC_LOGIC;
		    ctl.invert = funct7[5];
		    ctl.bitop  = op.funct3[1:0];
		 end
	       { 7'b000_0100, ALU_XOR }: begin
		  unique casez (op.rs2.r)
		    5'b00000: begin
		       ctl.unit = ALUSRC_SHIFT;
		       ctl.shiftop = 11'b00_11_101_xx_0_0; // ZEXT.H
		    end
		    default: begin
		       // Do nothing
		    end
		  endcase // unique casez (op.rs2.r)
	       end
	       { 7'b000_0101, 3'b1?? }: if (core.WITH_minmax) begin
		  ctl.unit = ALUSRC_MINMAX;
	       end
	       { 7'b000_0111, 3'b1?1 }: if (core.WITH_Zicond) begin
		  ctl.unit = ALUSRC_ZICOND;
	       end
	       default: begin
		  // Do nothing
	       end
	     endcase // unique casez ({funct7, op.funct3})
	  end

	  default: begin
	     // Not an ALU instruction
	  end
	endcase
     end // always @ (*)
endmodule // alu_decode

//
// Add/subtract with pre-shift support
// src2 must be already 1's-complemented for subtract
//
module adder (
	      input [31:0] src1,
	      input [31:0] src2,
	      input [1:0]  src1shift,
	      input        sub,
	      output reg [31:0] q,
	      output reg   ucout, // Unsigned (true) carry
	      output reg   scout  // Signed carry (for signed comparison)
	      );
   always @(*)
     begin
	logic [31:0]      s1;
	logic [31:0]	  s2;

	s1 = src1 << src1shift;
	s2 = src2;

	{ ucout, q } = s1 + s2 + sub;

	// XXX: make the generation of scout saner; this is
	// just intended to be a temporary hack. The 1'bx might
	// help the synthesizer merge this with the adder.
	scout = sub ? $signed(s1) >= $signed(~s2) : 1'bx;
     end
endmodule // adder

//
// Bitwise logic
//
module bitwise (
		input [31:0]  src1,
		input [31:0]  src2,
		input [1:0]   op,
		output reg [31:0] q
		);
   always @(*)
     begin
	unique case (op)
	  2'b01: q = src1 ^ src2;
	  2'b10: q = src1 | src2;
	  2'b11: q = src1 & src2;
	  default: q = 'bx;
	endcase // unique case (op)
     end
endmodule // bitwise

//
// 2:1 multiplexer as a separate module (for resource tracking)
//
module mux2
  #(
    parameter width = 1
    )
   (
    input [width-1:0]  d0,
    input [width-1:0]  d1,
    output [width-1:0] q,
    input	       sel
    );
   assign q = sel ? d1 : d0;
endmodule

//
// Mask the output to zero unless enabled
//
module mask
  #(
  parameter width = 32
  )
   (
  input [width-1:0] d,
  input enable,
  output [width-1:0] q
	    );
   assign q = d & {width{enable}};
endmodule

//
// Zbb operations
//

//  Generic count module (slow, even with constant config?)
//  cpop: ones = 1, cl = 1, ct = 1
//  ctz:  ones = 0, cl = 0, ct = 1
//  clz:  ones = 0, cl = 1, ct = 0
module bitcnt #(
  parameter width = 32
	    ) (
  input [width-1:0]	   d,
  output [$clog2(width):0] q,

  input			   ones,	// Count ones (not zeroes)
  input			   cl,		// Count leading
  input			   ct		// Count trailing
	    );

   localparam		     hw = width >> 1; // Half width
   localparam		     hb = $clog2(hw); // Half number of bits

   generate
      if (width < 2)
	begin
	   assign q = ~ones ^ d;
	end
      else
	begin
	   wire [hw-1:0]  dl = d[hw-1:0];
	   wire [hw-1:0]  dh = d[width-1:hw];
	   wire [hb:0]  ql;
	   wire [hb:0]  qh;

	   bitcnt #(hw) l (.d(dl), .q(ql), .ones(ones), .cl(cl), .ct(ct));
	   bitcnt #(hw) h (.d(dh), .q(qh), .ones(ones), .cl(cl), .ct(ct));

	   wire [hb:0]	xl = {hb+1{ct | qh[$clog2(hw)]}} & ql;
	   wire [hb:0]	xh = {hb+1{cl | ql[$clog2(hw)]}} & qh;

	   assign q = xl + xh;
	end
   endgenerate
endmodule // bitcnt

// Separate bit count ops
// XXX: could this simply be implemented by invoking the above with
// fixed values?
module clz #(
  parameter width = 32
	    ) (
  input [width-1:0]	   d,
  output [$clog2(width):0] q
	       );

   localparam		     hw = width >> 1;

   generate
      if (width < 2)
	begin
	   assign q = ~d;
	end
      else
	begin
	   wire [hw-1:0]  dl = d[hw-1:0];
	   wire [hw-1:0]  dh = d[width-1:hw];
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   clz #(hw) l (.d(dl), .q(ql));
	   clz #(hw) h (.d(dh), .q(qh));

	   assign q = qh[$clog2(hw)] ? { 1'b1, ql } : { 1'b0, qh };
	end
   endgenerate
endmodule // clz

module ctz #(
  parameter width = 32
	    ) (
  input [width-1:0]	   d,
  output [$clog2(width):0] q
	       );

   localparam		     hw = width >> 1;

   generate
      if (width < 2)
	begin
	   assign q = ~d;
	end
      else
	begin
	   wire [hw-1:0]  dl = d[hw-1:0];
	   wire [hw-1:0]  dh = d[width-1:hw];
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   ctz #(hw) l (.d(dl), .q(ql));
	   ctz #(hw) h (.d(dh), .q(qh));

	   assign q = ql[$clog2(hw)] ? { 1'b1, qh } : { 1'b0, ql };
	end
   endgenerate
endmodule // ctz

module cpop #(
  parameter width = 32
	    ) (
  input [width-1:0]	   d,
  output [$clog2(width):0] q
	       );

   localparam		     hw = width >> 1;

   generate
      if (width < 2)
	begin
	   assign q = d;
	end
      else
	begin
	   wire [hw-1:0]  dl = d[hw-1:0];
	   wire [hw-1:0]  dh = d[width-1:hw];
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   cpop #(hw) l (.d(dl), .q(ql));
	   cpop #(hw) h (.d(dh), .q(qh));

	   assign q = ql + qh;
	end
   endgenerate
endmodule // cpop

module orc
#(
  parameter width = 32,
  parameter grain = 8
  )
  (
   input  [width-1:0] d,
   output [width-1:0] q
   );

   genvar	      i;
   generate
      for (i = 0; i < width; i += grain)
	begin : og
	   assign q[i+grain-1:i] = {grain{|d[i+grain-1:i]}};
	end
   endgenerate
endmodule

module rev
#(
  parameter width = 32,
  parameter grain = 8
  )
  (
   input  [width-1:0] d,
   output [width-1:0] q
   );

   genvar	      i;
   generate
      for (i = 0; i < width; i += grain)
	begin : og
	   assign q[i+grain-1:i] = d[width-i-1:width-i-grain];
	end
   endgenerate
endmodule

// Comparator, parallelizing the logic by breaking it down into
// multiple carry chains for the less than, using the
// partial equality comparisons. The "endrec" parameter is tweakable,
// but the value 8 (= 4 chains of 8 bits) appears to give best result
// on a 4-LUT FPGA.
module comparator
  #(parameter width = 32, endrec = 8)
   (
  input [width-1:0] a,
  input [width-1:0] b,
  output	    lt,
  output	    eq
	      );

   localparam	    hw = width >> 1;

   generate
      if (width <= endrec) begin
	 assign lt = a < b;
	 assign eq = a == b;
      end else begin
	 wire lt_h;
	 wire eq_h;
	 wire lt_l;
	 wire eq_l;

	 comparator #(.width(hw), .endrec(endrec))
	 h (.a(a[width-1:hw]), .b(b[width-1:hw]), .lt(lt_h), .eq(eq_h));
	 comparator #(.width(hw), .endrec(endrec))
	 l (.a(a[hw-1:0]), .b(b[hw-1:0]), .lt(lt_l), .eq(eq_l));

	 assign eq = eq_h & eq_l;
	 assign lt = eq_h ? lt_l : lt_h;
      end
      endgenerate
endmodule

//
// This merges multiple computational blocks.
// This does not include the bypass logic.
// This doesn't include the multiplier, as the multiplier
// is implemented as a completely independent unit to allow
// for independent timing.
//
// *** Separated the multiplier from the ALU. Even with hardware blocks,
// the multiplier is much slower than any of the other units, so
// it makes sense for it to be given two pipeline stages (output data
// from the M stage.)
//
module alu (
  output reg [31:0] dst,
  output reg	    cmp_out, // Comparator output bypassing output MUX

  input [31:0]	    src1,
  input [31:0]	    src2,

  input		    aluctl_t ctl);

   wire [31:0]		  invsrc2 = src2 ^ {32{ctl.invert}};
   wire [31:0]		  add_out;
   wire			  add_ucarry;
   wire			  add_scarry;

   adder add (.src1(src1), .src2(invsrc2), .sub(ctl.invert),
     .src1shift(core.WITH_Zba ? ctl.shadd : 2'b00),
     .q (add_out), .ucout(add_ucarry), .scout(add_scarry));

   //
   // Comparator (expected to have the adder set up for subtract)
   // Note: cmp_eq does not apply the invert and shift transformations,
   // but doing so (in the adder unit) *might* optimize the generation
   // of add_scarry. Experiment.
   //
   // XXX: it seems combining this with the adder is really slow.
   // Is this better?
   //
   wire   cmp_eq;
   wire	  cmp_ltx;
   wire	  cmp_and = ~|(src1 & src2); // a.k.a. "test eq z"
   wire	  cmp_lgt = ctl.cond[0] ^ cmp_ltx;

   // For signed comparison, bit-flip both MSBs
   wire [31:0] sx1 = { src1[31] ^ ~ctl.cond[1], src1[30:0] };
   wire [31:0] sx2 = { src2[31] ^ ~ctl.cond[1], src2[30:0] };

   comparator comp (.a(sx1), .b(sx2), .lt(cmp_ltx), .eq(cmp_eq));

   always @(*) begin
      logic cmpcond;

      if (ctl.cond[2])
	cmpcond = cmp_ltx;
      else if (core.WITH_cmpand & ctl.cond[1])
	cmpcond = cmp_and;
      else
	cmpcond = cmp_eq;

      cmp_out = cmpcond ^ ctl.cond[0];
   end

   //
   // Minmax (select) unit
   //
   wire [31:0]		  minmax_out;
   mux2 #(32) minmax (.d0(src2), .d1(src1), .q(minmax_out), .sel(cmp_lgt));

   //
   // czero (Zicond) unit
   //
   wire [31:0]		  zicond_out;
   mask #(32) zicond (.d(src1), .q(zicond_out), .enable(ctl.cond[1] ^ |src2));

   //
   // Bitwise logic (AND, OR, XOR...)
   //
   wire [31:0]		  bit_out;
   bitwise bitwise (.src1(src1), .src2(invsrc2), .op(ctl.bitop), .q(bit_out));

   //
   // Fancy shift unit
   //
   wire [31:0]		  shift_out;
   shifter shifter (.shamt(src2[4:0]),
		    .op   (ctl.shiftop),
		    .d    (src1),
		    .q    (shift_out));

   //
   // Zbb operations. This contains two implementations; which is used
   // depends on core.BITCNT_SEPARATE. This can be tweaked to fit
   // the use case.
   //
   // If BITCNT_SEPARATE is false and WITH_extensions is true, the
   // unified implementation also provides cpopz, cto, clo;
   // equivalent to a NOT preceding the instruction.
   //
   logic [5:0]		  bitcnt_out;

   // Separate units implementation
   wire [31:0]		  bcsrc =
			  src1 ^ {32{core.WITH_bitcntinv & ctl.bcop[2]}};
   wire [5:0]		  clz_out;
   wire [5:0]		  ctz_out;
   wire [5:0]		  cpop_out;

   clz  #(32) clz  (.d (bcsrc), .q (clz_out));
   ctz  #(32) ctz  (.d (bcsrc), .q (ctz_out));
   cpop #(32) cpop (.d (bcsrc), .q (cpop_out));

   // Unified unit implementation
   wire [5:0]		  bitcnt_out_unified;
   wire			  bc_cl   = ~ctl.bcop[0];
   wire			  bc_ct   = ctl.bcop[1] ^ ctl.bcop[0];
   wire			  bc_ones = ctl.bcop[2] ^ ctl.bcop[1];

   bitcnt #(32) bitcnt (
     .d		(src1),			// Inversion handled in-unit
     .q		(bitcnt_out_unified),
     .ones	(bc_ones),		// CPOP, C[TL]O
     .ct	(bc_ct),		// CPOP[Z], CT[ZO]
     .cl	(bc_cl)			// CPOP[Z], CL[ZO]
     );

   // bitcnt output
   always @(*)
     if (!core.BITCNT_SEPARATE) begin
	bitcnt_out = bitcnt_out_unified;
     end else begin
	unique case (ctl.bcop)
	  3'b000:  bitcnt_out = clz_out;
	  3'b010:  bitcnt_out = ctz_out;
	  3'b011:  bitcnt_out = cpop_out;
	  default: bitcnt_out = 32'bx;
	endcase
     end

   //
   // orc and reverse operations
   //
   wire [31:0]		  orc_out;
   orc orc (.d(src1), .q(orc_out));
   wire [31:0]		  rev_out;
   rev rev8 (.d(src1), .q(rev_out));

   //
   // Output MUX
   //
   always @(*)
     begin
	dst = 'bx;
	unique case (ctl.unit)
	  ALUSRC_ADD:    dst			   = add_out;
	  ALUSRC_LOGIC:  dst			   = bit_out;
	  ALUSRC_SET:    dst			   = cmp_out;
	  ALUSRC_MINMAX: if (core.WITH_minmax) dst = minmax_out;
	  ALUSRC_SHIFT:  dst			   = shift_out;
	  ALUSRC_BITCNT: if (core.WITH_bitcnt) dst = bitcnt_out;
	  ALUSRC_ORC:    dst			   = orc_out;
	  ALUSRC_REV:    dst			   = rev_out;
	  ALUSRC_ZICOND: if (core.WITH_Zicond) dst = zicond_out;
	  default:       dst = 'bx;
	endcase // unique case (alusrc)
     end
endmodule // alu
