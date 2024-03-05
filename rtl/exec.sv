//
// This handles the backend of the pipe
//

module execute
  #(
    parameter contexts = 1,
    parameter ctx_bits = $clog2(contexts),
    parameter reg_bits = ctx_bits+5
    )
(
 input		      rst_n,
 input		      clk,
 input		      clken,

 output reg	      e_valid_out,
 output		      e_kill,
 output [31:0]	      e_dout,
 output [31:0]	      e_s1,	// rs1 or immediate data
 output [31:0]	      e_s2,	// rs2 or immediate data (e.g. store data)
rs
 output reg [31:0]    m_din,

 input		      e_stall,
 input		      e_rs1_m,
 input		      e_rs1_w,
 input		      e_rs2_m,
 input		      e_rs2_w,

 input [4:0]	      d_rs1, // rs1 or (short) immediate
 input		      d_rs1_valid, // rs1 is a register
 input [ctx_bits-1:0] d_rs1_ctx, // rs1 register context
 input [31:0]	      d_rs2, // rs2 or immediate
 input		      d_rs2_valid, // rs2 is a register
 input [ctx_bits-1:0] d_rs2_ctx, // rs2 register context
 input [31:0]	      d_offs,
 input		      d_pred_taken,

 input		      m_valid_out,
 input [31:0]	      m_dout,
 input [3:0]	      m_dout_be
 );

   wire		      e_clken = clken & ~e_stall;

   wire [31:0]	      rs1_data;
   wire [31:0]	      rs2_data;

   regfile #(.contexts(contexts)) regs
     (
      .rst_n ( rst_n ),
      .clk ( clk ),
      .rs1 ( d_rs1 ),
      .rs1_data ( rs1_data ),
      .rs2 ( d_rs2 ),
      .rs2_data ( rs2_data ),
      .rd  ( m_out ),
      .rd_wbe ( m_valid_out ? m_out_be : 4'b0 )
      );

   // This W-stage, don't use e_clken
   reg [31:0]	      w_din;
   always @(posedge clk)
     if (m_valid_out)
       begin
	  if (m_out_be[0]) w_din[7:0]   <= m_dout[7:0];
	  if (m_out_be[1]) w_din[15:8]  <= m_dout[15:8];
	  if (m_out_be[2]) w_din[23:16] <= m_dout[23:16];
	  if (m_out_be[3]) w_din[31:24] <= m_dout[31:24];
       end

   reg [31:0] m_din;
   always @(posedge clk)
     if (e_clken)
       begin
	  e_valid_out <= e_valid_in;
	  if (e_valid_in)
	    m_din <= e_dout;
       end

   // GPR bypass network/operand selection
   always @(posedge clk)
     if (!e_rs1_valid)
       e_s1 = rs1;		// rs1 is uimm5 or void
     else if (e_rs1_m)
       e_s1 = m_din;		// Data now in M stage
     else if (e_rs1_w)
       e_s1 = w_din;		// Data now in W stage
     else
       e_s1 = rs1_data;		// Data already in register file

   always @(*)
     if (!e_rs2_valid)
       e_s2 = rs2;		// rs2 is immediate or void
     else if (e_rs2_m)
       e_s2 = m_din;		// Data now in M stage
     else if (e_rs2_w)
       e_s2 = w_din;		// Data now in W stage
     else
       e_s2 = rs2_data;		// Data already in register file
endmodule // execute
