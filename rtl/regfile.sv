//
// regfile.sv
//
// Register file: two read ports, one write port, one clock cycle.
//

`include "myriscv.vh"

`ifndef ALTERA_RESERVED_QIS	// XXX: try to figure out how to use generic

// Generic implementation
module regfile #(`CONFIG)
   (
    input		 rst_n,
    input		 clk,
    input		 clken,

    input		 rs_valid,
    input regnum_t	 rs1,
    input regnum_t	 rs2,
    input regnum_t	 rd,
    input		 rd_wren,
    input [3:0]		 rd_wbe,

    input [31:0]	 rd_data,

    output [31:0]	 rs1_data,
    output [31:0]	 rs2_data
    );

   // Note: CONTEXTS is not required to be a power of 2!
   localparam int       bregs	  = $clog2(CONTEXTS) + 5;
   localparam int	nregs	  = CONTEXTS << 5;

   reg [3:0][7:0]	r[0:nregs-1];

   // Register index into the memory array. This allows for
   // e.g. hardware implementations that want to keep the non-existent
   // x0 registers together.
   logic [bregs-1:0]	ix1;	// rs1 index
   logic [bregs-1:0]	ix2;	// rs2 index
   logic [bregs-1:0]	ixd;	// rd index

   assign ix1 = REGFILE_CONTEXT_LSB ? { rs1.r, rs1.c } : { rs1.c, rs1.r };
   assign ix2 = REGFILE_CONTEXT_LSB ? { rs2.r, rs2.c } : { rs2.c, rs2.r };
   assign ixd = REGFILE_CONTEXT_LSB ? { rd.r,  rd.c  } : { rd.c,  rd.r  };

   // Note: the core will never try to write to GPR register 0.
   // (otherwise the bypass network would try to forward dummy x0
   // writes.)
   initial
     for (int i = 0; i < nregs; i++)
       r[i] <= REGFILE_ZERO_INIT ? 32'b0 : 32'bx;

   reg rs1_zero;
   reg rs2_zero;
   always @(posedge clk) begin
      if (rs_valid) begin
	 rs1_zero  <= ~|rs1.r;
	 rs2_zero  <= ~|rs2.r;
      end
   end

   reg [31:0] rs1_dq;
   reg [31:0] rs2_dq;

   // Combinatorial clearing on input if REGFILE_ZERO_INIT is not available
   // Not needed as rs1_valid is squished in the decode stage
   wire	      rs1_null = 1'b0; // !REGFILE_ZERO_INIT && rs1_zero;
   wire	      rs2_null = !REGFILE_ZERO_INIT && rs2_zero;

   assign rs1_data = rs1_null ? 'b0 : rs1_dq;
   assign rs2_data = rs2_null ? 'b0 : rs2_dq;

   // This assumes that byte enables are basically "free".
   // If not, some additional MUXing for the second strobe of an unaligned
   // load can eliminate the need for them.
   //
   // Putting a clken on the read seems to generate a dual-clock
   // memory. Does this need to be fixed?
   always @(posedge clk) begin
      if (rs_valid) begin
	 rs1_dq <= r[ix1];
	 rs2_dq <= r[ix2];
      end
      if (clken & rd_wren) begin
	 logic [31:0] wr_mask = {{8{rd_wbe[3]}}, {8{rd_wbe[2]}},
				 {8{rd_wbe[1]}}, {8{rd_wbe[0]}}};
	 if (rd.r == 5'd0 && |rd_wbe)
	   $display("ERROR: writing to register %d:0 at t=%0t",
		    rd.c, $time);
	 if ($isunknown(rd_data & wr_mask))
	   $display("ERROR: writing x or z to register %d:%d at t=%0t",
		    rd.c, rc.r, $time);
	 if (rd_wbe[0]) r[ixd][0] <= rd_data[7:0];
	 if (rd_wbe[1]) r[ixd][1] <= rd_data[15:8];
	 if (rd_wbe[2]) r[ixd][2] <= rd_data[23:16];
	 if (rd_wbe[3]) r[ixd][3] <= rd_data[31:24];
      end
   end
endmodule // regfile

`else // !`ifndef ALTERA_RESERVED_QIS

// Altera-specific register file implementation
module regfile #(`CONFIG)
   (
    input		 rst_n,
    input		 clk,
    input		 clken,

    input		 rs_valid,
    input regnum_t	 rs1,
    input regnum_t	 rs2,
    input regnum_t	 rd,
    input		 rd_wren,
    input [3:0]		 rd_wbe,

    input [31:0]	 rd_data,

    output [31:0]	 rs1_data,
    output [31:0]	 rs2_data
    );

   // No 3-port memories, so use two copies
   alt_regfile r1 (
		   .aclr		(~rst_n),
		   .clock		(clk),
		   .enable		(clken),

		   .wren		(rd_wren),
		   .byteena_a		(rd_wbe),
		   .wraddress		(rd),

		   .rd_addressstall	(~rs_valid),
		   .rdaddress		(rs1),
		   .q			(rs1_data)
		   );
   alt_regfile r2 (
		   .aclr		(~rst_n),
		   .clock		(clk),
		   .enable		(clken),

		   .wren		(rd_wren),
		   .byteena_a		(rd_wbe),
		   .wraddress		(rd),

		   .rd_addressstall	(~rs_valid),
		   .rdaddress		(rs2),
		   .q			(rs2_data)
		   );
endmodule // regfile

`endif
