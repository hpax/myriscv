//
// This handles the backend of the pipe; the E, M and W pipeline stages.
//

`include "myriscv.vh"

// Compute the new value for a register that has both a write mask and
// a fixed mask (all bits outside the fixed mask are forced to zero.)
function logic [31:0] rwmz(
  input [31:0] dst,
  input [31:0] src,
  input [31:0] wmask,
  input [31:0] fmask
  );

   rwmz = ((dst & ~wmask) | (src & wmask)) & fmask;
endfunction

module backend #(
  parameter int	NUM_IRQS,
  parameter int	IRQ_BITS,
  parameter bit	ALU_EARLY_DECODE
		)
(
 input		       rst_n,
 input		       clk,
 input		       clken,

 input		       decoded_insn_t d_op,

 // IRQ pending bitmask. Note that there is no IRQ 0 since that vector
 // is reserved for exceptions; e_intack == 0 means no interrupt taken.
 input [NUM_IRQS:1]    d_irqs,
 output [IRQ_BITS-1:0] e_intack,

 input		       e_valid_i,
 input		       e_stall,
 input		       decoded_insn_t e_op,
 output reg	       e_valid_o,
 output reg	       e_kill,
 output reg [31:0]     e_restartpc, // Address for the front end after kill
 output reg	       e_busy,
 input		       e_rs1_m,
 input		       e_rs1_w,
 input		       e_rs2_m,
 input		       e_rs2_w,

 input		       m_valid_i,
 input		       m_stall,
 input		       decoded_insn_t m_op,
 output reg	       m_valid_o,
 output reg	       m_busy,

 // Data output, unregistered and registered
 output reg [31:0]     e_dout,
 output reg [31:0]     m_din,

 // Data bus from ldst unit
 output [31:0]	       dbus_a,
 output		       dbus_valid,
 output		       dbus_wrq,
 output [3:0]	       dbus_wbe,
 output [31:0]	       dbus_wdata,
 input [31:0]	       dbus_rdata,
 input		       dbus_ready
 );

   wire		       e_clken = clken & (~e_stall | e_busy | e_kill);
   wire		       m_clken = clken & (~m_stall | m_busy);
   wire		       w_clken = clken & m_valid_o;

   wire [31:0]	   e_rs1_data;
   wire [31:0]	   e_rs2_data;
   reg [31:0]	   m_dout;
   reg [3:0]	   m_dout_be;

   // E-stage pipeline synchronization signals
   assign e_valid_o = e_clken & e_valid_i & ~e_kill;
   assign e_busy    = 1'b0;

   // Latched output to M stage; also used by the bypass network
   always @(posedge clk)
     if (m_clken)
       m_din <= e_dout;

   // Register file
   regfile #(.contexts(1 << `CONTEXT_BITS)) regs
     (
     .rst_n    ( rst_n ),
     .clk      ( clk ),
     .clken    ( clken ),	// Not w_clken; need to read anyway
     .rs1      ( d_op.rs1 ),
     .rs1_data ( e_rs1_data ),
     .rs2      ( d_op.rs2 ),
     .rs2_data ( e_rs2_data ),
     .rd       ( m_op.rd ),
     .rd_data  ( m_dout ),
     .rd_wren  ( m_valid_o & (m_op.rd_e | m_op.rd_m) ),
     .rd_wbe   ( m_dout_be )
      );

   reg [31:0]	      w_din;
   always @(posedge clk)
     if (w_clken)
	 begin
	    if (m_dout_be[0]) w_din[7:0]   <= m_dout[7:0];
	    if (m_dout_be[1]) w_din[15:8]  <= m_dout[15:8];
	    if (m_dout_be[2]) w_din[23:16] <= m_dout[23:16];
	    if (m_dout_be[3]) w_din[31:24] <= m_dout[31:24];
	 end

   // GPR bypass network/operand selection
   logic [31:0]	e_src1;
   always @(*)
     if (!e_op.rs1_valid)
       e_src1 = e_op.rs1.r;	// rs1 is uimm5 or void
     else if (e_rs1_m)
       e_src1 = m_din;		// Data now in M stage
     else if (e_rs1_w)
       e_src1 = w_din;		// Data now in W stage
     else
       e_src1 = e_rs1_data;	// Data already in register file

   logic [31:0]	e_src2;
   always @(*)
     if (!e_op.rs2_valid)
       e_src2 = e_op.imm;
     else if (e_rs2_m)
       e_src2 = m_din;		// Data now in M stage
     else if (e_rs2_w)
       e_src2 = w_din;		// Data now in W stage
     else
       e_src2 = e_rs2_data;	// Data already in register file

   // AGU adder; this is the only place where a U-immediate is
   // accepted.
   //
   // LD, ST, JALR, LUI use src1 as addend (always 0 for LUI);
   // branch, JAL, AUIPC use pc as addend.
   logic [31:0]	e_addr;
   always @(*)
     begin
	logic [31:0] e_addri;
	logic [31:0] e_addra;

	if (e_op.imm_u)
	  e_addri = { e_op.imm[11:0], e_op.imm[19:12], 12'b0 };
	else
	  e_addri = e_op.imm;

	if (e_op.imm_pc)
	  e_addra = e_op.pc;
	else
	  e_addra = e_src1;

	e_addr = e_addri + e_addra;
     end

   // ALU
   aluctl_t e_aluctl;
   wire [31:0] e_alu_out;
   wire	       e_cmp_out;

   generate
      if (ALU_EARLY_DECODE) begin
	 aluctl_t d_aluctl;
	 alu_decode alu_decode (.op(d_op), .ctl(d_aluctl));
	 always @(negedge rst_n or posedge clk)
	   if (~rst_n)
	     e_aluctl <= 'bx;
	   else if (e_clken)
	     e_aluctl <= d_aluctl;
      end else begin
	 alu_decode alu_decode (.op(e_op), .ctl(e_aluctl));
      end
   endgenerate

   alu alu (.dst(e_alu_out), .cmp_out(e_cmp_out),
     .src1(e_src1), .src2(e_src2), .ctl(e_aluctl));

   // Multiplier
   wire [31:0] m_mul_o;
   wire [31:0] m_mull_o;
   multiplier mult (.rst_n(rst_n), .clk(clk),
     .e_valid(e_clken && e_op.itype == INSN_MUL),
     .e_op(e_op.funct3[1:0]),
     .e_src1(e_src1), .e_src2(e_src2),
     .m_mul_o(m_mul_o), .m_mull_o(m_mull_o));

   //
   // CSR registers
   //
   reg [31:0] mtvec = core.MTVEC_RESET & core.PC_MASK;
   reg [31:0] mepc  = 32'bx & core.PC_MASK;
   localparam [31:0] mcause_mask = 32'h8000_0000 | {IRQ_BITS{1'b1}};
   reg [31:0] mcause;

   reg [63:0] ctr_time	  = 64'b0;
   reg [63:0] ctr_cycle   = 64'b0;
   reg [63:0] ctr_instret = 64'b0;

   wire [63:0] csr_cycle  = core.CTR_CYCLE_WIDTH ? ctr_cycle : ctr_time;

   //
   // CSR read/write logic
   //
   logic [31:0]	e_csr_rval;
   logic [31:0]	e_csr_wval;

   always @(*)
     unique casez (e_op.imm[11:0])
       CSR_MTVEC:  e_csr_rval			      = mtvec;
       CSR_MEPC:   e_csr_rval			      = mepc;
       CSR_MCAUSE: e_csr_rval			      = mcause;
       CSR_TIME:   e_csr_rval			      = ctr_time[31:0];
       CSR_TIMEH:  e_csr_rval			      = ctr_time[63:32];
       CSR_CYCLE, CSR_MCYCLE:   e_csr_rval	      = csr_cycle[31:0];
       CSR_CYCLEH, CSR_MCYCLEH: e_csr_rval	      = csr_cycle[63:32];
       CSR_INSTRET,  CSR_MINSTRET:         e_csr_rval = ctr_instret[31:0];
       CSR_INSTRETH, CSR_MINSTRETH:        e_csr_rval = ctr_instret[63:32];
       default:    e_csr_rval			      = 32'b0;
     endcase

   always @(*)
     unique casez (e_op.funct3)
       3'b?01:  e_csr_wval  = e_src1;
       3'b?10:  e_csr_wval  = e_csr_rval |  e_src1;
       3'b?11:  e_csr_wval  = e_csr_rval & ~e_src1;
       default: e_csr_wval  = 32'bx;
     endcase

   wire		csrw_mtvec  = e_op.csrw && e_op.imm[11:0] == CSR_MTVEC;
   wire		csrw_mepc   = e_op.csrw && e_op.imm[11:0] == CSR_MEPC;
   wire		csrw_mcause = e_op.csrw && e_op.imm[11:0] == CSR_MCAUSE;

   //
   // Counters. All counters are read only, even when using the m-
   // CSR numbers.
   //
   wire [63:0]	ctr_time_mask    = (1'b1 << core.CTR_TIME_WIDTH)    - 1'b1;
   wire [63:0]	ctr_cycle_mask   = (1'b1 << core.CTR_CYCLE_WIDTH)   - 1'b1;
   wire [63:0]	ctr_instret_mask = (1'b1 << core.CTR_INSTRET_WIDTH) - 1'b1;
   always @(posedge clk)
     begin
	ctr_time <= (ctr_time + 1'b1) & ctr_time_mask;

	if (clken)
	  ctr_cycle <= (ctr_cycle + 1'b1) & ctr_cycle_mask;

	// An instruction is considered retired when it gets
	// accepted by the W stage.
	if (w_clken)
	   ctr_instret <= (ctr_instret + 1'b1) & ctr_instret_mask;
     end

   //
   // Interrupt recognition
   //
   reg [IRQ_BITS-1:0] e_irq_vector;
   reg		      e_irq;

   assign e_intack = e_irq_vector;

   // Note that e_irq_vector must be zero if !e_irq
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	e_irq		      <= 1'b0;
	e_irq_vector	      <= 'b0;
     end else if (~clken) begin
	e_irq	     <= |d_irqs;
	e_irq_vector <= 'b0;
	// Priority vector encoder
	for (int i = NUM_IRQS; i > 0; i--)
	  if (d_irqs[i]) e_irq_vector <= i;
     end

   //
   // Successor PC (for JAL/JALR and, in the future, branch predict
   // validation.)
   //
   wire [31:0] e_next_pc  = successor_pc(e_op);

   //
   // Branch, jump, trap and interrupt handling
   //
   logic        trap_irq;
   logic [31:0]	trap_mcause;

   always @(*)
     begin
	logic [31:0] new_pc;

	e_kill	    = 1'b0;
	new_pc	    = e_next_pc;
	trap_irq    = 1'b0;
	trap_mcause = 32'bx;

	if (e_irq) begin
	   trap_irq	 = 1'b1;
	   trap_mcause   = MCAUSE_IRQ | e_irq_vector;
	end else unique case (e_op.itype)
	  INSN_ERR: if (core.TRAP_BADINSN) begin
	     trap_irq    = 1'b1;
	     trap_mcause = MCAUSE_BADINSN;
	  end
	  INSN_ECALL: begin	// ECALL, EBREAK
	     trap_irq	 = 1'b1;
	     trap_mcause = e_op.imm[0] ? MCAUSE_BREAK : MCAUSE_ECALLM;
	  end
	  INSN_ALU: if (core.TRAP_BADALU) begin
	     trap_irq    = e_aluctl.unit == ALUSRC_ERR;
	     trap_mcause = MCAUSE_BADINSN;
	  end
	  INSN_JAL: begin
	     e_kill	 = !e_op.pred_taken;
	     new_pc	 = e_addr;
	  end
	  INSN_BR: begin
	     e_kill	= e_cmp_out != e_op.pred_taken;
	     if (e_cmp_out)
	       new_pc   = e_addr;
	  end
	  default: begin
	     // No control transfer
	  end
	endcase

	if (core.TRAP_BADPC && (new_pc & ~core.PC_MASK) && !trap_irq) begin
	   trap_irq    = 1'b1;	// PC out of bounds
	   trap_mcause = MCAUSE_BADPC;
	end

	if (trap_irq) begin
	   e_kill = 1'b1;	// The unexpected is never predicted...
	   new_pc = mtvec + (e_irq_vector << 2);
	end

	e_restartpc = new_pc & core.PC_MASK;
     end

   always @(posedge clk)
     if (e_clken) begin
	if (csrw_mtvec)
	  mtvec <= rwmz(mtvec,  e_csr_wval, core.MTVEC_WMASK, core.PC_MASK);

	// XXX: writing mepc seems to be a frequency limiter; it could
	// probably be written in the M stage (post-kill) instead.
	if (trap_irq)
	  mepc  <= e_op.pc & core.PC_MASK;
	else if (csrw_mepc)
	  mepc  <= rwmz(mepc,   e_csr_wval, core.PC_MASK,     core.PC_MASK);

	if (trap_irq)
	  begin
	     if (e_irq)
	       mcause	  <= MCAUSE_IRQ | e_irq_vector;
	     else
	       mcause	  <= trap_mcause;
	  end
	else if (csrw_mcause);
	  mcause <= rwmz(mcause, e_csr_wval, mcause_mask, mcause_mask);
     end

   //
   // E stage output data MUX
   //
   always @(*)
     unique case (e_op.itype)
       INSN_ALU:  e_dout = e_alu_out;
       INSN_MULL: e_dout = m_mull_o;
       INSN_JAL:  e_dout = e_next_pc;
       INSN_AGU:  e_dout = e_addr;
       INSN_CSR:  e_dout = e_csr_rval;
       default:   e_dout = 32'bx; // No output, or delivered from M stage
     endcase

   //
   // Load/store unit
   //
   wire ldst_valid = insn_ldst(e_op.itype);

   wire [31:0] ldst_dout;
   wire [3:0]  ldst_dout_wbe;
   wire	       ldst_dout_valid;
   wire	       ldst_busy;

   ldst ldst (
     .rst_n		(rst_n),
     .clk		(clk),
     .clken		(clken),
     .valid		(ldst_valid),
     .memop_st		(e_op.itype[0]),
     .memop_ldu		(e_op.funct3[2]),
     .size		(e_op.funct3[1:0]),
     .addr		(e_addr),
     .src2		(e_src2),
     .dout		(ldst_dout),
     .dout_wbe		(ldst_dout_wbe),
     .dout_valid	(ldst_dout_valid),
     .busy		(ldst_busy),
     .dbus_a		(dbus_a),
     .dbus_valid	(dbus_valid),
     .dbus_wrq		(dbus_wrq),
     .dbus_wbe		(dbus_wbe),
     .dbus_wdata	(dbus_wdata),
     .dbus_rdata	(dbus_rdata),
     .dbus_ready	(dbus_ready)
     );

   assign m_busy = ldst_busy;

   //
   // M stage output MUX
   //
   always @(*)
     unique case (m_op.itype)
       INSN_LD: begin
	  m_dout    = ldst_dout;
	  m_dout_be = ldst_dout_wbe;
	  m_valid_o = ldst_dout_valid;
       end
       INSN_MUL: begin
	  m_dout    = m_mul_o;
	  m_dout_be = 4'b1111;
	  m_valid_o = m_valid_i;
       end
       default: begin
	  m_dout    = m_din;
	  m_dout_be = 4'b1111;
	  m_valid_o = m_valid_i;
       end
     endcase
endmodule // execute
