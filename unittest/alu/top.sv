//
// Unit test for ALU and multiplier units
//

`include "myriscv.vh"

module alutest (
  input		rst_n,
  input		clk,
  input		decoded_insn_t e_op,

  input [31:0]	e_src1,
  input [31:0]	e_src2,

  output logic [31:0]	m_dst,
  output logic		m_cmp_out,
  output logic		m_valid
  );

   aluctl_t                         ctl;

   wire [31:0]			    e_alu_out;
   wire 			    e_cmp_out;
   wire [31:0]			    m_mull_out;
   wire [31:0]			    m_mulh_out;

   reg [31:0]			    m_alu_out;

   wire				    e_is_mul = e_op.itype == INSN_MUL;
   reg 				    m_is_mul;
   reg				    m_is_mulh;
   wire				    e_do_mul = e_is_mul & ~m_is_mul;
   
   always @(posedge clk or negedge rst_n)
     if (~rst_n) begin
	m_alu_out <= 32'bx;
	m_cmp_out <= 32'bx;
	m_valid   <= 1'b0;
	m_is_mul  <= 1'b0;
	m_is_mulh <= 1'bx;
     end else begin
	m_alu_out <= e_alu_out;
	m_cmp_out <= e_cmp_out;
	m_is_mul  <= e_is_mul;
	m_is_mulh <= |e_op.funct3[1:0];
	m_valid   <= ~e_do_mul;
     end

   always @(*)
     if (!m_is_mul)
       m_dst = m_alu_out;
     else if (m_is_mulh)
       m_dst = m_mulh_out;
     else
       m_dst = m_mull_out;
   
   alu_decode dc (
     .op (e_op),
     .ctl(ctl)
     );

   alu alu (
     .dst	(e_alu_out),
     .cmp_out	(e_cmp_out),
     .src1      (e_src1),
     .src2      (e_src2),
     .ctl	(ctl)
     );
     
   multiplier mult (
     .rst_n 	(rst_n),
     .clk   	(clk),
     .e_valid	(e_do_mul),
     .e_src1	(e_src1),
     .e_src2	(e_src2),
     .e_op	(e_op.funct3[1:0]),
     .m_mulh_o	(m_mulh_out),
     .m_mull_o	(m_mull_out)
     );
endmodule // alutest
