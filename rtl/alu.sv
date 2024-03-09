//
// ALU operations
//
// Implements: I Zicond Zba Zbb Zbs
//
// Note: M/Zmmul is done separately due to timing.
//
typedef enum logic [4:0] {
	ALUSRC_ERR,		// Invalid instruction
	ALUSRC_ADD,
	ALUSRC_LOGIC,
	ALUSRC_SET,		// Set to result of compare
	ALUSRC_MINMAX,		// compare ? src1 : src2
        ALUSRC_BITCNT,
        ALUSRC_ORC,
	ALUSRC_REV,
	ALUSRC_ZICOND,
	// These units need to get MUXed in as late as possible
	ALUSRC_SHIFT = 5'b10000
} alusrc_t;

typedef struct packed {
   alusrc_t    unit;
   logic       invert;
   logic [1:0] shadd;
   logic [1:0] bitop;
   logic	bc_l;		// bitcnt count leading
   logic	bc_t;		// bitcnt count trailing
   logic	bc_s;		// bitcnt count set
   logic [1:0] msign;
   shiftop_t   shiftop;
   cond_t      cond;
} aluctl_t;

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

	unique case (op.itype)
	  INSN_BR: begin
	     // A branch is an SET as far as the ALU is
	     // concerned...
	     ctl.unit   = ALUSRC_SET;
	     ctl.invert = 1'b1;		// Compare: always subtract
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
		  if (core.WITH_Zba && (core.WITH_extensions || !funct7[5])) begin
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
		       if (core.WITH_extensions ||
			 (!op.rs2.r[4] && op.rs2.r[1:0] != 2'b11)) begin
			  ctl.unit = ALUSRC_BITCNT;
			  ctl.bc_l = ~op.rs2.r[0];
			  ctl.bc_t = op.rs2.r[1] ^ op.rs2.r[0];
			  ctl.bc_s = op.rs2.r[4] ^ op.rs2.r[1];
		       end
		    end
		    6'b1_0010?: begin
		       ctl.unit = ALUSRC_SHIFT;
		       ctl.shiftop = { 4'b00_11, op.rs2.r[2:0], 4'b11_1_0 }; // SEXT.B/H
		    end
		    6'b0_?????: begin
		       ctl.unit = ALUSRC_SHIFT;
		       ctl.shiftop = 11'b11_xx_000_xx_x_x; // ROL
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
		  endcase
	       end
	       { 7'b000_0000, ALU_SLT },
		 { 7'b000_0000, ALU_SLTU }: begin
		    ctl.unit   = ALUSRC_SET;
		    ctl.invert = 1'b1;		// Compare: always subtract
		 end
	       { 7'b0?0_0000, ALU_XOR },
		 { 7'b0?0_0000, ALU_OR },
		 { 7'b0?0_0000, ALU_AND }: begin
		    ctl.unit   = ALUSRC_LOGIC;
		    ctl.invert = funct7[5];
		    ctl.bitop  = op.funct3[1:0];
		 end
	       { 7'b0000100, ALU_XOR }: begin
		  unique casez (op.rs2.r)
		    5'b00000: begin
		       ctl.unit = ALUSRC_SHIFT;
		       ctl.shiftop = 11'b00_11_101_xx_0_0; // ZEXT.H
		    end
		  endcase // unique casez (op.rs2.r)
	       end
	       { 7'b000_0101, 3'b1?? }: if (core.WITH_minmax) begin
		  ctl.unit = ALUSRC_MINMAX;
		  ctl.invert = 1'b1;		// Compare: always subtract
	       end
	       { 7'b000_0111, 3'b1?1 }: if (core.WITH_Zicond) begin
		  ctl.unit = ALUSRC_ZICOND;
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
	      output [31:0] q,
	      output       ucout, // Unsigned (true) carry
	      output       scout  // Signed carry (for signed comparison)
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
		output [31:0] q
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

// NB: cpop: ones = 1, cl = 1, ct = 1
//     ctz:  ones = 0, cl = 0, ct = 1
//     clz:  ones = 0, cl = 1, ct = 0
module bitcnt #(
  parameter width = 32
	    ) (
  input [width-1:0]	   d,
  output [$clog2(width):0] q,

  input			   ones,	// Count ones (not zeroes)
  input			   cl,		// Count leading
  input			   ct		// Count trailing
	    );

   localparam		     hw = width >> 1;

   generate
      if (width < 2)
	begin
	   assign q = ~ones ^ d;
	end
      else
	begin
	   wire [hw-1:0]  dl = d[hw-1:0];
	   wire [hw-1:0]  dh = d[width-1:hw];
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   bitcnt #(hw) l (.d(dl), .q(ql), .ones(ones), .cl(cl), .ct(ct));
	   bitcnt #(hw) h (.d(dh), .q(qh), .ones(ones), .cl(cl), .ct(ct));

	   wire [$clog2(hw):0]	xl = (ct | qh[$clog2(hw)]) ? ql : 'b0;
	   wire [$clog2(hw):0]	xh = (cl | ql[$clog2(hw)]) ? qh : 'b0;

	   assign q = xl + xh;
	end
   endgenerate
endmodule // bitcnt

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
module alu
   (
    output reg [31:0] dst,
    output reg	      cmp_out,	// Comparator output bypassing output MUX

    input [31:0]      src1,
    input [31:0]      src2,

    input	      aluctl_t ctl
    );

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
   wire			  cmp_eq  = (src1 == src2);
   wire			  cmp_lts = ~add_scarry;
   wire			  cmp_ltu = ~add_ucarry;
   logic		  cmp_lt;

   always @(*) begin
      cmp_lt  = ctl.cond[0] ^ (ctl.cond[1] ? cmp_ltu : cmp_lts);
      cmp_out = ctl.cond[2] ? cmp_eq ^ ctl.cond[0] : cmp_lt;
   end

   //
   // Minmax (select) unit
   //
   wire [31:0]		  minmax_out;
   mux2 #(32) minmax (.d0(src2), .d1(src1), .q(minmax_out), .sel(cmp_lt));

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
   // Zbb operations
   //
   wire [5:0]		  bitcnt_out;
   bitcnt bitcnt (
     .d		(src1),
     .q		(bitcnt_out),
     .ones	(ctl.bc_s),	// CPOP, C[TL]S
     .ct	(ctl.bc_t),	// CPOP[N], CT[ZS]
     .cl	(ctl.bc_l)	// CPOP[N], CL[ZS]
   );
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
	  ALUSRC_ADD:    dst = add_out;
	  ALUSRC_LOGIC:  dst = bit_out;
	  ALUSRC_SET:    dst = cmp_out;
	  ALUSRC_MINMAX: if (core.WITH_minmax) dst = minmax_out;
	  ALUSRC_SHIFT:  dst = shift_out;
	  ALUSRC_BITCNT: dst = bitcnt_out;
	  ALUSRC_ORC:    dst = orc_out;
	  ALUSRC_REV:    dst = rev_out;
	  ALUSRC_ZICOND: if (core.WITH_Zicond) dst = zicond_out;
	endcase // unique case (alusrc)
     end
endmodule // alu
