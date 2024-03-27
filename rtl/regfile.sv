//
// regfile.sv
//
// Register file: two read ports, one write port, one clock cycle.
//

`include "myriscv.vh"

`ifndef ALTERA_RESERVED_QIS

// Generic implementation
module regfile
  #(
    parameter	  contexts = 1,
    parameter	  reg_bits = $clog2(contexts)+5,
    parameter bit zero_init = 1'b1
    )
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

   // This is not required to be a power of 2
   localparam int       nregs = contexts << 5;
   reg [3:0][7:0]	r[0:nregs-1];

   // Noete: the core will never try to write to GPR register 0.
   // (otherwise the bypass network would try to forward dummy x0
   // writes.)
   initial
     for (int i = 0; i < nregs; i++)
       r[i] <= zero_init ? 32'b0 : 32'bx;

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

   // Combinatorial clearing on input if zero_init is not available
   wire	      rs1_null = !zero_init & rs1_zero;
   wire	      rs2_null = !zero_init & rs2_zero;

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
	 rs1_dq <= r[rs1];
	 rs2_dq <= r[rs2];
      end
      if (clken & rd_wren) begin
	 if (rd.r == 5'd0 && |rd_wbe)
	   $display("ERROR: writing to register 0 at t=%0t", $time);
	 if (rd_wbe[0]) r[rd][0] <= rd_data[7:0];
	 if (rd_wbe[1]) r[rd][1] <= rd_data[15:8];
	 if (rd_wbe[2]) r[rd][2] <= rd_data[23:16];
	 if (rd_wbe[3]) r[rd][3] <= rd_data[31:24];
      end
   end
endmodule // regfile

`else // !`ifndef ALTERA_RESERVED_QIS

// Altera-specific register file implementation
module regfile
  #(
    parameter	  contexts = 1,
    parameter	  reg_bits = $clog2(contexts)+5,
    parameter bit zero_init = 1'b1
    )
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
