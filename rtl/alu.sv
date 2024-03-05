//
// ALU operations
//
// Implements: I Zicond Zba Zbb Zbs
//
// Note: M/Zmmul is done separately due to timing.
//
typedef enum logic [4:0] {
	ALUSRC_ADD   = 5'b00001,
	ALUSRC_LOGIC,
	ALUSRC_SET,		// Set to result of compare
	ALUSRC_MINMAX,		// compare ? src1 : src2
        ALUSRC_CLZ,
        ALUSRC_CTZ,
	ALUSRC_CPOP,
        ALUSRC_ORC,
	ALUSRC_REV,
	ALUSRC_ZICOND,
	// These units need to get MUXed in as late as possible
	ALUSRC_SHIFT = 5'b10000
} alusrc_t;

typedef struct packed {
   alusrc_t    unit;
   logic       is_mult;
   logic       invert;
   logic [1:0] shadd;
   logic [1:0] bitop;
   logic [1:0] msign;
   shiftop_t   shiftop;
   logic [2:0] cond;
} aluctl_t;

module alu_decode (
		  input signed [11:0] rs2,
		  input	       is2_valid,
		  input [2:0]  funct3,
		  input [6:0]  funct7, // Already zero if imm12

		  output aluctl_t ctl
		  );

   always @(*)
     begin
	ctl = 'bx;
	ctl.shadd   = 2'b00;		// No preshift
	ctl.cond    = funct3;
	ctl.is_mult = 1'b0;
	unique casez ({funct7, funct3})
	  { 7'b0?0_0000, ALU_ADD }: begin
	     ctl.unit = ALUSRC_ADD;
	     ctl.invert = funct7[5];
	  end
	  { 7'b000_0001, 3'b0?? }: begin
	     ctl.is_mult = 1'b1;
	  end
	  { 7'b0?1_0000, 3'b??0 }: begin // shXadd, shXsub
	     ctl.unit = ALUSRC_ADD;
	     ctl.shadd = funct3[2:1];
	     ctl.invert = funct7[5];
	  end
`ifdef WITH_DIVIDE
	  { 7'b000_0001, 3'1?? }: begin
	     ctl.unit = funct3[1] ? ALUSRC_REM : ALUSRC_DIV;
	     ctl.msign = funct3[0] ? 2'b11 : 2'b00;
	  end
`endif
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
	     unique casez ({is2_valid, rs2[4:0]})
	       6'b1_00000: begin
		  ctl.unit = ALUSRC_CLZ;
	       end
	       6'b1_00001: begin
		  ctl.unit = ALUSRC_CTZ;
	       end
	       6'b1_00010: begin
		  ctl.unit = ALUSRC_CPOP;
	       end
	       6'b1_0010?: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = { 4'b00_11, rs2[2:0], 4'b11_1_0 }; // SEXT.B/H
	       end
	       6'b0_?????: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b11_xx_000_xx_x_x; // ROL
	       end
	     endcase // unique casez ({is2_valid, rs2[4:0]})
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
	     unique casez ({is2_valid, rs2[4:0]})
	       5'b1_00111: begin // ORC.B
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
	     unique casez ({is2_valid, rs2[4:0]})
	       6'b1_11000: begin // REV8
		  // In the future, rs2 might be a control mask for a more
		  // advanced bitswap instruction
		  ctl.unit = ALUSRC_REV;
	       end
	     endcase // unique casez ({is2_valid, rs2[4:0]})
	  end
	  { 7'b000_0000, ALU_SLT },
	  { 7'b000_0000, ALU_SLTU }: begin
	     ctl.unit   = ALUSRC_SET;
	     ctl.invert = 1'b1;		// Compare: always subtract
	  end
	  { 7'b0?0_0000, ALU_XOR },
	  { 7'b0?0_0000, ALU_OR },
	  { 7'b0?0_0000, ALU_AND }: begin
	     ctl.unit = ALUSRC_LOGIC;
	     ctl.invert = funct7[5];
	     ctl.bitop = funct3[1:0];
	  end
	  { 7'b0000100, ALU_XOR }: begin
	     unique casez (rs2[4:0])
	       5'b00000: begin
		  ctl.unit = ALUSRC_SHIFT;
		  ctl.shiftop = 11'b00_11_101_xx_0_0; // ZEXT.H
	       end
	     endcase // unique casez (rs2[4:0])
	  end
	  { 7'b000_0101, 3'b1?? }: begin
	     ctl.unit = ALUSRC_MINMAX;
	     ctl.invert = 1'b1;		// Compare: always subtract
	  end
	  { 7'b000_0111, 3'b1?1 }: begin
	     ctl.unit = ALUSRC_ZICOND;
	  end
	endcase // unique casez ({funct7, funct3})
     end // always @ (*)
endmodule // alu_decode

//
// Add/subtract with pre-shift support
// d2 must be already 1's-complemented for subtract
//
module adder (
	      input [31:0] d1,
	      input [31:0] d2,
	      input [1:0]  d1shift,
	      input        sub,
	      output [31:0] q,
	      output       ucout, // Unsigned (true) carry
	      output       scout  // Signed carry (for signed comparison)
	      );
   always @(*)
     begin
	logic [31:0]      src1;
	logic [31:0]	  src2;
	logic		  cmsb;	// Carry into the MSB

	src1 = d1 << d1shift;
	src2 = d2;

	{ ucout, q } = src1 + src2 + sub;

	// XXX: make the generation of scout saner; this is
	// just intended to be a temporary hack
	scout = sub ? $signed(src1) >= $signed(~src2) : 1'bx;
     end
endmodule // adder

//
// Bitwise logic
//
module bitwise (
		input [31:0]  d1,
		input [31:0]  d2,
		input [1:0]   op,
		output [31:0] q
		);
   always @(*)
     begin
	logic [31:0] src2;

	unique case (op)
	  2'b01: q = d1 ^ d2;
	  2'b10: q = d1 | d2;
	  2'b11: q = d1 & d2;
	  default: q = 'bx;
	endcase // unique case (xop[1:0])
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
// Zbb operations
//
module ctz
  #(
    parameter width = 32
    )
   (
    input [width-1:0]	     d,
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
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   ctz #(hw) l (.d(d[hw-1:0]), .q(ql));
	   ctz #(hw) h (.d(d[width-1:hw]), .q(qh));

	   assign q = ql[$clog2(hw)]
		      ? qh + (1'b1 << $clog2(hw))
		      : ql;
	end
   endgenerate
endmodule // ctz

module clz
  #(
    parameter width = 32
    )
   (
    input [width-1:0]	     d,
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
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   ctz #(hw) l (.d(d[hw-1:0]), .q(ql));
	   ctz #(hw) h (.d(d[width-1:hw]), .q(qh));

	   assign q = qh[$clog2(hw)]
		      ? ql + (1'b1 << $clog2(hw))
		      : qh;
	end
   endgenerate
endmodule // clz

module cpop
  #(
    parameter width = 32
    )
   (
    input [width-1:0]	     d,
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
	   wire [$clog2(hw):0]  ql;
	   wire [$clog2(hw):0]  qh;

	   cpop #(hw) l (.d(d[hw-1:0]), .q(ql));
	   cpop #(hw) h (.d(d[width-1:hw]), .q(qh));

	   assign q = ql + qh;
	end // else: !if(width == 1)
      endgenerate
endmodule

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
  #(
    parameter bit WITH_Zba    = 1'b1, // Adds ~88 LE
    parameter bit WITH_minmax = 1'b1  // Adds ~59 LE
    )
   (
    output reg [31:0] dst,

    input [31:0]      src1,
    input [31:0]      src2,

    input	      aluctl_t ctl
    );

   wire [31:0]		  invsrc2 = src2 ^ {32{ctl.invert}};
   wire [31:0]		  add_out;
   wire			  add_ucarry;
   wire			  add_scarry;

   adder add (.d1(src1), .d2(invsrc2), .sub(ctl.invert),
	      .d1shift(ctl.shadd),
	      .q (add_out),
	      .ucout(add_ucarry), .scout(add_scarry));
   //
   // Comparator (expected to have the adder set up for subtract)
   // Note: cmp_eq does not apply the invert and shift transformations;
   // that can be done optionally.
   //
   wire			  cmp_eq  = (src1 == src2);
   wire			  cmp_lts = ~add_scarry;
   wire			  cmp_ltu = ~add_ucarry;
   logic		  cmp_lt;
   logic		  cmp_out;

   always @(*) begin
      cmp_lt  = ctl.cond[0] ^ (ctl.cond[1] ? cmp_ltu : cmp_lts);
      cmp_out = ctl.cond[2] ? cmp_eq ^ ctl.cond[0] : cmp_lt;
   end

   //
   // Minmax (select) unit
   //
   wire [31:0]		  minmax_out;
   mux2 #(32) minmax (.d0(src2), .d1(src1), .sel(cmp_lt), .q(minmax_out));

   //
   // czero (Zicond) unit
   //
   wire [31:0]		  zicond_out;
   assign zicond_out = src1 & {32{ctl.cond[1] ^ |src2}};

   //
   // Bitwise logic
   //
   wire [31:0]		  bit_out;
   bitwise bitwise (.d1(src1), .d2(invsrc2), .op(ctl.bitop), .q(bit_out));

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
   wire [5:0]		  clz_out;
   clz clz (.d(src1), .q(clz_out));
   wire [5:0]		  ctz_out;
   ctz ctz (.d(src1), .q(ctz_out));
   wire [5:0]		  cpop_out;
   cpop cpop (.d(src1), .q(cpop_out));
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
	  ALUSRC_SET:    dst = { 31'b0, cmp_out };
	  ALUSRC_MINMAX: if (WITH_minmax) dst = minmax_out;
	  ALUSRC_SHIFT:  dst = shift_out;
	  ALUSRC_CLZ:    dst = clz_out;
	  ALUSRC_CTZ:    dst = ctz_out;
	  ALUSRC_CPOP:   dst = cpop_out;
	  ALUSRC_ORC:    dst = orc_out;
	  ALUSRC_REV:    dst = rev_out;
	  ALUSRC_ZICOND: dst = zicond_out;
	endcase // unique case (alusrc)
     end
endmodule // alu
