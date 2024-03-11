//
// Load/store unit (data bus driver). Input is taken at the beginning
// of the E stage; load output is taken at the end of the M stage.
//
// This generates the data bus address, byte enables, permuted store
// data, and sets up the multiplexers for the load data.
//
// memop is encoded as:
// 00 - not memop
// 01 - store
// 10 - unsigned load
// 11 - signed load
//
// This unit supports misaligned accesses by breaking them into two if they
// cross a word boundary.
//
module ldst (
		input	      rst_n,
		input	      clk,
		input	      clken,
		input	      valid,

		input [1:0]   memop,	// See above
		input [1:0]   size,	// Data size == 2^x bytes

		input [31:0]  addr,	// address
		input [31:0]  src2,	// store data

		output reg [31:0] dout,	// Load data output
		output reg [3:0]  dout_wbe, // Load data output enables

		// Set if the pipeline should be held due to misaligned
		// input or waiting for data
		output	      busy,

		output [31:0] dbus_a,
		output	      dbus_valid,
		output	      dbus_wrq,
		output reg [3:0]  dbus_wbe,
		output reg [31:0] dbus_wdata,
		input [31:0]  dbus_rdata,
		input	      dbus_ready
		);

   // Handling the upper word of a misaligned operation?
   reg			      upper_word;

   // Each of the load byte MUXes can take data from any byte,
   // or set it to 0 or the MSB of another byte.
   reg [3:0]		      ld_ext;
   reg			      ld_uns;
   reg [3:0][1:0]	      ld_src;

   assign dbus_a[31:2] = addr[31:2] + upper_word;
   assign dbus_a[1:0]  = 2'b00;
   assign dbus_valid   = valid & |memop;
   assign dbus_wrq     = valid & memop == 2'b01;

   logic		      misaligned;
   always @(*)
     begin
	priority casez ({dbus_valid, size, dbus_a[1:0]})
	  5'b1_00_??: misaligned = 1'b0;
	  5'b1_01_0?: misaligned = 1'b0;
	  5'b1_01_11: misaligned = 1'b1;
	  5'b1_10_00: misaligned = 1'b0;
	  5'b1_10_??: misaligned = 1'b1;
	  5'b1_11_??: misaligned = 1'bx; // Invalid
	  5'b0_??_??: misaligned = 1'b0; // Not a memop
	endcase // priority casez ({dbus_valid, size, lower_byte})
     end

   assign busy = !dbus_ready | (misaligned & ~upper_word);

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
       upper_word <= 1'b0;
     end else if (clken) begin
	upper_word <= dbus_valid & dbus_ready & misaligned & ~upper_word;
     end

   logic [3:0] bytemask;
   always @(*)
     unique casez ({size, addr[1:0], upper_word})
       5'b00_00_0: bytemask <= 4'b0001;
       5'b00_01_0: bytemask <= 4'b0010;
       5'b00_10_0: bytemask <= 4'b0100;
       5'b00_11_0: bytemask <= 4'b1000;

       5'b01_00_0: bytemask <= 4'b0011;
       5'b01_01_0: bytemask <= 4'b0110;
       5'b01_10_0: bytemask <= 4'b1100;
       5'b01_11_0: bytemask <= 4'b1000;
       5'b01_11_1: bytemask <= 4'b0001;

       5'b10_00_0: bytemask <= 4'b1111;
       5'b10_01_0: bytemask <= 4'b1110;
       5'b10_01_1: bytemask <= 4'b0001;
       5'b10_10_0: bytemask <= 4'b1100;
       5'b10_10_1: bytemask <= 4'b0011;
       5'b10_11_0: bytemask <= 4'b1000;
       5'b10_11_1: bytemask <= 4'b0111;

       default:    bytemask <= 4'bxxxx; // Invalid
     endcase // unique casez ({size, addr[1:0], upper_word})

   // XXX: this is wrong for a misaligned load
   assign dout_wbe = 4'b1111;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  dbus_wdata   <= 32'bx;
	  dbus_wbe     <= 4'b0;
	  ld_ext       <= 4'bx;
	  ld_uns       <= 1'bx;
	  ld_src       <= 8'bx;
       end
     else
       begin
	  dbus_wbe     <= 4'b0;
	  dbus_wdata   <= 32'bx;

	  if (dbus_wrq)
	    begin
	       dbus_wbe <= bytemask;
	       unique casez (addr[1:0])
		 2'b00: dbus_wdata <= src2;
		 2'b01: dbus_wdata <= { src2[23:0], src2[7:0]  };
		 2'b10: dbus_wdata <= { src2[15:0], src2[15:8] };
		 2'b11: dbus_wdata <= { src2[7:0],  src2[31:8] };
	       endcase // unique casez (addr[1:0])
	    end // if (dbus_wrq)

	  // Set up load MUXes
	  ld_uns <= ~memop[1];

	  unique casez (size)
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

   // Output MUXes
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
