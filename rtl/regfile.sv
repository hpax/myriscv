//
// regfile.sv
//
// Register file: two read ports, one write port, one clock cycle.
//

module regfile
  #(
    parameter	  contexts = 1,
    parameter	  reg_bits = $clog2(contexts)+5,
    parameter bit zero_init = 1'b1
    )
   (
    input	       rst_n,
    input	       clk,
    input	       clken,

    input [reg_bits:0] rs1,
    input [reg_bits:0] rs2,
    input [reg_bits:0] rd,
    input	       rd_wren,
    input [3:0]	       rd_wbe,

    input [31:0]       rd_data,

    output [31:0]      rs1_data,
    output [31:0]      rs2_data
    );

   // This is not required to be a power of 2
   localparam		nregs = contexts << 5;

   reg [31:0]		r[0:nregs-1];

   // Noete: the core will never try to read or write to GPR register 0.
   // (otherwise the bypass network would try to forward dummy x0
   // writes.)
   initial
     for (int i = 0; i < nregs; i++)
       r[i] = zero_init ? 'b0 : 'bx;

   wire	rs1_null = !zero_init && ~|rs1[4:0];
   wire rs2_null = !zero_init && ~|rs2[4:0];

   // This assumes that byte enables are basically "free".
   // If not, some additional MUXing for the second strobe of an unaligned
   // load can eliminate the need for them.
   always @(posedge clk)
     if (clken) begin
	rs1_data <= rs1_null ? 'b0 : r[rs1];
	rs2_data <= rs2_null ? 'b0 : r[rs2];
	if (rd_wren) begin
	  if (rd_wbe[0]) r[rd][7:0]   <= rd_data[7:0];
	  if (rd_wbe[1]) r[rd][15:8]  <= rd_data[15:8];
	  if (rd_wbe[2]) r[rd][23:16] <= rd_data[23:16];
	  if (rd_wbe[3]) r[rd][31:24] <= rd_data[31:24];
	end
     end
endmodule // regfile
