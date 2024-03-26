//
// Load/store unit (data bus driver). Input is taken at the beginning
// of the E stage; load output is taken at the end of the M stage.
//
// This generates the data bus address, byte enables, permuted store
// data, and sets up the multiplexers for the load data.
//
// This unit supports misaligned accesses by breaking them into two if they
// cross a word boundary.
//
module ldst (
		input		  rst_n,
		input		  clk,
		input		  clken,
		input		  valid, // It is a memop

		input		  memop_cbo,  // It is a cache management op
		input [4:0]	  memop_cbo_op,    // 5-bit CBO opcode
		input		  memop_st, // It is a store
		input		  memop_ldu, // Load is unsigned
		input [1:0]	  size, // Data size == 2^x bytes

		input [31:0]	  addr, // address
		input [31:0]	  src2, // store data

		output reg [31:0] dout, // Load data output
		output reg [3:0]  dout_wbe,
		output reg	  dout_valid,

		// Set if the pipeline should be held due to misaligned
		// input or waiting for data.
		output		  busy,

		output [31:0]	  dbus_a,
		output		  dbus_valid,
		output		  dbus_cbo,	// Cache block operation
		output		  dbus_wrq,
		output reg [3:0]  dbus_wbe,
		output reg [31:0] dbus_wdata,	// Or CBO operation
		input [31:0]	  dbus_rdata,
		input		  dbus_ready
		);

   // Handling the upper word of a misaligned operation?
   reg			      upper_word;

   // Hold output address while busy; also increments for the second word.
   reg [31:0]		      latched_a;

   // Should we use latched data?
   wire			      use_latched = busy;

   // Each of the load byte MUXes can take data from any byte,
   // or set it to 0 or the MSB of another byte.
   reg [3:0]		      ld_ext;
   reg			      ld_uns;
   reg [3:0][1:0]	      ld_src;

   reg			      dbus_valid_q;
   reg			      memop_st_q;
   reg			      memop_cbo_q;

   assign dbus_a	= use_latched ? latched_a + {upper_word, 2'b00} : addr;
   assign dbus_valid	= rst_n & (valid | busy);
   assign dbus_wrq = dbus_valid & (use_latched ? memop_st_q : memop_st);
   assign dbus_cbo = dbus_valid & (use_latched ? memop_cbo_q : memop_cbo);

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	dbus_valid_q <= 1'b0;
	memop_st_q   <= 1'b0;
	memop_cbo_q  <= 1'b0;
     end else if (clken) begin
	dbus_valid_q <= dbus_valid;
	if (~busy) begin
	   memop_st_q  <= memop_st;
	   memop_cbo_q <= memop_cbo;
	end
     end

   logic		      misaligned_comb;
   reg			      misaligned_q;
   always @(*)
     if (memop_cbo)
       misaligned_comb = 1'b0;	// Never split a CBO
     else
       unique case (size)
	 2'b00: misaligned_comb = 1'b0;				// Byte
	 2'b01: misaligned_comb = (dbus_a[1:0] == 2'b11);	// Halfword
	 2'b10: misaligned_comb = (dbus_a[1:0] != 2'b00);	// Word
	 default: misaligned_comb = 1'bx;			// Invalid
       endcase

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       misaligned_q <= 1'bx;
     else if (clken & ~busy)
       misaligned_q <= misaligned_comb;

   reg	upper_word_q;

   // Note: busy contains dbus_valid_q, because it is asserted by the M
   // stage, but valid is asserted in the E stage.
   assign dout_valid = dbus_valid_q & dbus_ready;
   assign busy	     = dbus_valid_q & (~dbus_ready |
		       (misaligned_q & ~upper_word_q));
   assign upper_word = dout_valid ? misaligned_q & ~upper_word_q : upper_word_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       upper_word_q <= 1'b0;
     else if (clken)
       upper_word_q <= dbus_valid_q & upper_word;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	latched_a    <= 'bx;
     end else if (clken) begin
	if (~busy)
	  latched_a <= addr;
     end

   // Bytemask for the bus, upper and lower word
   // The upper word enables can be x when aligned
   logic [1:0][3:0] bytemask;
   always @(*)
     unique case ({size, addr[1:0]})
       4'b00_00: bytemask = 8'bxxxx_0001;
       4'b00_01: bytemask = 8'bxxxx_0010;
       4'b00_10: bytemask = 8'bxxxx_0100;
       4'b00_11: bytemask = 8'bxxxx_1000;

       4'b01_00: bytemask = 8'bxxxx_0011;
       4'b01_01: bytemask = 8'bxxxx_0110;
       4'b01_10: bytemask = 8'bxxxx_1100;
       4'b01_11: bytemask = 8'b0001_1000;

       4'b10_00: bytemask = 8'bxxxx_1111;
       4'b10_01: bytemask = 8'b0001_1110;
       4'b10_10: bytemask = 8'b0011_1100;
       4'b10_11: bytemask = 8'b0111_1000;

       default:  bytemask = 8'bxxxx_xxxx; // Invalid
     endcase

   // Bytemask for the register file. The bytemask here must include
   // any bytes that are derived by zero/sign extension. It is safe to
   // write all the bytes on the low-word operation, but the high word
   // operation must limit its byte enables.
   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       dout_wbe <= 4'bxxxx;
     else if (clken) begin
	if (~upper_word)
	  dout_wbe <= 4'b1111;
	else
	  unique case (latched_a[1:0]) // Can always use the latched here
	    2'b01:   dout_wbe <= 4'b1000;
	    2'b10:   dout_wbe <= 4'b1100;
	    2'b11:   dout_wbe <= 4'b1110;
	    default: dout_wbe <= 4'bxxxx;
	  endcase
     end

   // dbus output MUXes
   // XXX: does multiplexing CBO operations onto the wdata bus actually
   // make any sense?
   logic [31:0] wdata_comb;
   always @(*)
     if (memop_cbo)
       wdata_comb = { 27'bx, memop_cbo_op };
     else
       unique case (addr[1:0])
	 2'b00:   wdata_comb = src2;
	 2'b01:   wdata_comb = { src2[23:0], src2[31:24] };
	 2'b10:   wdata_comb = { src2[15:0], src2[31:16] };
	 2'b11:   wdata_comb = { src2[7:0],  src2[31:8]  };
	 default: wdata_comb = 32'bx;
       endcase // unique casez (addr[1:0])

   reg [31:0]	  latched_wdata;
   reg [1:0][3:0] latched_wbe;
   always @(posedge clk or negedge rst_n)
     if (~rst_n) begin
	latched_wbe   <= 8'bx;
	latched_wdata <= 32'bx;
     end else if (clken) begin
	if (~busy) begin
	   latched_wbe	 <= bytemask;
	   latched_wdata <= wdata_comb;
	end
     end

   always @(*)
     if (use_latched) begin
	dbus_wbe   = latched_wbe[upper_word];
	dbus_wdata = latched_wdata;
     end else begin
	dbus_wbe   = bytemask[0];
	dbus_wdata = wdata_comb;
     end

   // Load input MUX setup
   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  ld_ext       <= 4'bx;
	  ld_uns       <= 1'bx;
	  ld_src       <= 8'bx;
       end
     else if (clken & ~busy)
       begin
	  // Set up load MUXes
	  ld_uns <= memop_ldu;

	  unique case (size)
	    2'b00:   ld_ext <= 4'b1110;
	    2'b01:   ld_ext <= 4'b1100;
	    2'b10:   ld_ext <= 4'b0000;
	    default: ld_ext <= 4'bx; // Invalid
	  endcase // unique casez (size)

	  unique casez ({size, addr[1:0]})
	    4'b00_??: ld_src <= {4{addr[1:0]}};
	    4'b01_00: ld_src <= 8'b01_01_01_00;
	    4'b01_01: ld_src <= 8'b10_10_10_01;
	    4'b01_10: ld_src <= 8'b11_11_11_10;
	    4'b01_11: ld_src <= 8'b00_00_00_11;
	    4'b10_00: ld_src <= 8'b11_10_01_00;
	    4'b10_01: ld_src <= 8'b10_01_00_11;
	    4'b10_10: ld_src <= 8'b01_00_11_10;
	    4'b10_11: ld_src <= 8'b00_11_10_01;
	    default:  ld_src <= 8'bx; // Invalid
	  endcase // unique casez ({size, addr[1:0]})
       end // else: !if(~rst_n)

   // Load data output MUXes
   always @(*)
     begin
	logic [7:0] din[0:3];	// Input bytes
	logic [7:0] dperm[0:3];	// Permuted bytes

	din[0] = dbus_rdata[7:0];
	din[1] = dbus_rdata[15:8];
	din[2] = dbus_rdata[23:16];
	din[3] = dbus_rdata[31:24];

	dperm[0] = din[ld_src[0]];
	dperm[1] = din[ld_src[1]];
	dperm[2] = din[ld_src[2]];
	dperm[3] = din[ld_src[3]];

	dout[7:0]   = ld_ext[0] ? {8{dperm[0][7] & ~ld_uns}} : dperm[0];
	dout[15:8]  = ld_ext[1] ? {8{dperm[1][7] & ~ld_uns}} : dperm[1];
	dout[23:16] = ld_ext[2] ? {8{dperm[2][7] & ~ld_uns}} : dperm[2];
	dout[31:24] = ld_ext[3] ? {8{dperm[3][7] & ~ld_uns}} : dperm[3];
     end // always @ (*)
endmodule // addrgen
