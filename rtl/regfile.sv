//
// regfile.sv
//
// Register file: two read ports, one write port, one clock cycle.
//

module regfile
  #(
    parameter contexts  = 1,
    parameter reg_bits  = $clog2(contexts)+5
    )
   (
    input	       rst_n,
    input	       clk,

    input [reg_bits:0] rs1,
    input [reg_bits:0] rs2,
    input [reg_bits:0] rd,
    input [3:0]	       rd_wbe,

    input [31:0]       rd_data,

    output [31:0]      rs1_data,
    output [31:0]      rs2_data
    );

   localparam		nregs = contexts << 5;

   reg [31:0]		r[0:nregs-1];

   // If the zero register can't be wired to 0 in hardware and cannot
   // be initialized, then it is necessary to force it to zero on
   // output.  The core will never actually try to write to register
   // 0; the front end eliminates writes to x0 during decode
   // (otherwise the bypass network would try to forward dummy x0
   // writes.)
   initial
     for (int i = 0; i < nregs; i++)
       r[i] = 32'b0;

   // This assumes that byte enables are basically "free".
   // If not, some additional MUXing for the second strobe of an unaligned
   // load can eliminate the need for them.
   always @(posedge clk)
     begin
	rs1_data <= r[rs1];
	rs2_data <= r[rs2];
	if (rd_wbe[0]) r[rd][7:0]   <= rd_data[7:0];
	if (rd_wbe[1]) r[rd][15:8]  <= rd_data[15:8];
	if (rd_wbe[2]) r[rd][23:16] <= rd_data[23:16];
	if (rd_wbe[3]) r[rd][31:24] <= rd_data[31:24];
     end
endmodule // regfile
