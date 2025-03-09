//
// This handles the backend of the pipe; the E, M and W pipeline stages.
//

`include "myriscv.vh"

// Compute the new value for a register under mask
function logic [31:0] wmask(
  input [31:0] src,
  input [31:0] old,
  input [31:0] mask
  );

   wmask = (src & mask) | (old & ~mask);
endfunction

module backend #(`CONFIG)
(
 input			   rst_n,
 input			   clk,
 input			   clken,

 input			   decoded_insn_t d_op,

 input			   f_valid_o,
 input			   regnum_t f_rs1,
 input			   regnum_t f_rs2,

 // IRQ pending bitmask. Note that there is no IRQ 0 since that vector
 // is reserved for exceptions; e_intack == 0 means no interrupt taken.
 input [NUM_IRQS:1]	   d_irqs,
 output reg [NUM_IRQS:1]   d_irqs_clear, // Clear edge-triggered interrupts
 output reg [IRQ_BITS-1:0] e_intack,

 input			   e_valid_i,
 input			   e_stall,
 input			   decoded_insn_t e_op,
 output reg		   e_valid_o,
 output reg		   m_kill,
 output reg [31:0]	   m_restartpc, // Address for the front end after kill
 output			   mcontext_t m_restart_mcontext,
 output reg		   e_busy,
 input			   d_rs1_e,
 input			   d_rs1_m,
 input			   d_rs1_w,
 input			   d_rs2_e,
 input			   d_rs2_m,
 input			   d_rs2_w,

 input			   m_valid_i,
 input			   m_stall,
 input			   decoded_insn_t m_op,
 output reg		   m_valid_o,
 output reg		   m_busy,

 // Counters
 input [63:0]		   ctr_time,
 input [63:0]		   ctr_cycle,
 input [63:0]		   ctr_instret,

 // Random data input
 input rng_bus_t	   rng,
 output			   rng_full,

 // Data output, unregistered and registered
 output reg [31:0]	   e_dout,
 output reg [31:0]	   m_din,

 // Data bus from ldst unit
 output [31:0]		   dbus_a,
 output			   dbus_valid,
 output cbo_t		   dbus_cbo,
 output			   dbus_wrq,
 output [3:0]		   dbus_wbe,
 output [31:0]		   dbus_wdata,
 input [31:0]		   dbus_rdata,
 input			   dbus_ready
 );
   wire [31:0] MISA = {
	       WITH_Zalrsc & WITH_Zaamo,		// A
	       WITH_Zba & WITH_Zbb & WITH_Zbs,	// B
	       WITH_RVC,				// C
	       1'b0,				// D
	       1'b0,				// E
	       1'b0,				// F
	       1'b0,				// G
	       1'b0,				// H
	       1'b1,				// I
	       1'b0,				// J
	       1'b0,				// K
	       1'b0,				// L
	       WITH_Zmmul & WITH_div,		// M
	       1'b0,				// N
	       1'b0,				// O
	       1'b0,				// P
	       1'b0,				// Q
	       1'b0,				// R
	       1'b0,				// S
	       1'b0,				// T
	       1'b0,				// U
	       1'b0,				// V
	       1'b0,				// W
	       1'b0,				// X
	       1'b0,				// Y
	       1'b0,				// Z
	       4'b0,				// Padding
	       2'b01				// RISCV-32
   };

   wire [31:0] csrval_misa = WITH_misa ? MISA : 32'b0;

   logic	   e_kill;

   wire		   e_clken = clken & (~e_stall | e_busy | e_kill);
   wire		   m_clken = clken & (~m_stall | m_busy | m_kill);
   wire		   w_clken = clken & m_valid_o;

   wire [31:0]	   d_rs1_data;
   wire [31:0]	   d_rs2_data;
   reg [31:0]	   m_dout;
   reg [3:0]	   m_dout_be;

   // E-stage pipeline synchronization signals
   logic	   e_trap;
   logic	   e_jump;

   assign e_busy    = 1'b0;

   // m_kill will not be reflected in e_valid_i because it ends
   // up on the wrong side of a register; this could be fixed,
   // though...
   wire   e_accept  = e_valid_i & ~e_busy & ~m_kill;

   // This does not consider m_trap due to a speed path.
   assign e_valid_o = e_accept;

   // LR/SC state machine outputs
   logic lrsc_resv;		// Reservation set held (SC returns 0)
   logic lrsc_hold;		// Inhibit interrupts (atomic sequence)

   // M-stage pipeline synchronization signals
   reg	  m_trap;

   wire	  m_accept = m_valid_i & ~m_busy & ~m_trap;

   // Latched output to M stage; also used by the bypass network
   always @(posedge clk)
     if (e_clken)
       m_din <= e_dout;

   // Register file
   regfile #(.contexts(1 << CONTEXT_BITS)) regs
     (
     .rst_n    ( rst_n ),
     .clk      ( clk ),
     .clken    ( clken ),	// Not any specific stage!
     .rs_valid ( f_valid_o ),
     .rs1      ( f_rs1 ),
     .rs1_data ( d_rs1_data ),
     .rs2      ( f_rs2 ),
     .rs2_data ( d_rs2_data ),
     .rd       ( m_op.rd ),
     .rd_data  ( m_dout ),
     .rd_wren  ( m_valid_o & m_op.rd_m ),
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
   wire [31:0] w_dout = w_din;

   // GPR bypass network/operand selection
   wire		      d_src_hold = (e_valid_i & e_stall) | e_busy;

   logic [31:0] e_src1;
   logic [31:0] e_src2;

   generate
      if (EARLY_BYPASS_MUX) begin
	always @(negedge rst_n or posedge clk)
	  if (~rst_n) begin
	     e_src1 <= 32'bx;
	     e_src2 <= 32'bx;
	  end else begin
	     if (d_src_hold)
	       e_src1 <= e_src1;	// Do not update
	     if (!d_op.rs1_valid)
	       e_src1 <= d_op.rs1.r;	// rs1 is uimm5 or void
	     else if (d_rs1_e)
	       e_src1 <= e_dout;	// Data comes from the E stage
	     else if (d_rs1_m)
	       e_src1 <= m_dout;	// Data comes from the M stage
	     else if (d_rs1_w)
	       e_src1 <= w_dout;	// Data comes from the W stage
	     else
	       e_src1 <= d_rs1_data;	// Data comes from the register file

	     if (d_src_hold)
	       e_src2 <= e_src2;	// Do not update
	     if (!d_op.rs2_valid)
	       e_src2 <= d_op.imm;	// rs2 is uimm5 or void
	     else if (d_rs2_e)
	       e_src2 <= e_dout;	// Data comes from the E stage
	     else if (d_rs2_m)
	       e_src2 <= m_dout;	// Data comes from the M stage
	     else if (d_rs2_w)
	       e_src2 <= w_dout;	// Data comes from the W stage
	     else
	       e_src2 <= d_rs2_data;	// Data comes from the register file
	  end
      end else begin
	 // Late MUX
	 reg e_rs1_m;
	 reg e_rs1_w;
	 reg e_rs2_m;
	 reg e_rs2_w;
	 reg [31:0] e_src1_q;
	 reg [31:0] e_src2_q;

	always @(negedge rst_n or posedge clk)
	  if (~rst_n) begin
	     e_src1_q	<= 32'bx;
	     e_src2_q	<= 32'bx;
	     e_rs1_m	<= 1'bx;
	     e_rs1_w	<= 1'bx;
	     e_rs2_m	<= 1'bx;
	     e_rs2_w	<= 1'bx;
	  end else if (clken) begin
	     if (d_src_hold)
	       e_src1_q <= e_src1;
	     else if (~d_op.rs1_valid)
	       e_src1_q <= d_op.rs1.r;	// rs1 is uimm5 or void
	     else if (d_rs1_w)
	       e_src1_q <= w_dout;
	     else
	       e_src1_q <= d_rs1_data;

	     if (d_src_hold)
	       e_src2_q <= e_src2;
	     else if (~d_op.rs2_valid)
	       e_src2_q <= d_op.imm;
	     else if (d_rs2_w)
	       e_src2_q <= w_dout;
	     else
	       e_src2_q <= d_rs2_data;

	     // XXX: this is wrong if the M stage can advance
	     // while the E stage is busy; in that case we need
	     // to explicitly re-do the comparison for d_rs*_m
	     // using e_op when d_src_hold is active. However,
	     // as of right now, the E stage is never busy (e_busy = 0)
	     // so this (hack) should be correct.
	     if (~d_src_hold) begin
		e_rs1_m <= d_rs1_e;
		e_rs1_w <= d_rs1_m;
		e_rs2_m <= d_rs2_e;
		e_rs2_w <= d_rs2_m;
	     end
	  end

	 always @(*) begin
	    if (e_rs1_m)
	      e_src1 = m_din;
	    else if (e_rs1_w)
	      e_src1 = w_din;
	    else
	      e_src1 = e_src1_q;

	    if (e_rs2_m)
	       e_src2 = m_din;
	    else if (e_rs2_w)
	      e_src2 = w_din;
	    else
	      e_src2 = e_src2_q;
	 end
      end
   endgenerate

   //
   // AGU adder; separate adder for performance reasons.
   //
   logic [31:0]	e_addr;
   always @(*)
     e_addr = $signed(e_src1) + $signed(e_op.imm);

   // ALU
   aluctl_t e_aluctl;
   wire [31:0] e_alu_out;
   wire	       e_cmp_out;

   generate
      if (ALU_EARLY_DECODE) begin
	 aluctl_t d_aluctl;
	 alu_decode #(`CFG) alu_decode (.op(d_op), .ctl(d_aluctl));
	 always @(negedge rst_n or posedge clk)
	   if (~rst_n)
	     e_aluctl <= 'bx;
	   else if (e_clken)
	     e_aluctl <= d_aluctl;
      end else begin
	 alu_decode #(`CFG) alu_decode (.op(e_op), .ctl(e_aluctl));
      end
   endgenerate

   alu #(`CFG) alu (.dst(e_alu_out), .cmp_out(e_cmp_out),
     .src1(e_src1), .src2(e_src2), .ctl(e_aluctl));

   // Multiplier
   wire [31:0] m_mulh_o;
   wire [31:0] m_mull_o;
   multiplier mult (.rst_n(rst_n), .clk(clk),
     .e_valid(clken & e_accept & (e_op.itype == INSN_MUL) & ~e_op.rd_e),
     .e_op(e_op.funct3[1:0]),
     .e_src1(e_src1), .e_src2(e_src2),
     .m_mulh_o(m_mulh_o), .m_mull_o(m_mull_o));

   // Random number generator
   logic [31:0] e_rng_out;
   logic	e_rng_rstb;
   rng_zkr #(`CFG)
   rng_zkr (.rst_n(rst_n), .clk(clk), .clken(clken),
     .rng(rng), .rng_full(rng_full),
     .rdata(e_rng_out), .rstb(e_rng_rstb));

   //
   // CSR registers
   //
   reg [31:0] mtvec;
   reg [31:0] mepc;
   localparam [31:0] mcause_mask = MCAUSE_FIXED_MASK | {IRQ_BITS{1'b1}};
   reg [31:0] mcause;
   reg [NUM_IRQS:1] mie;
   reg [`REG_CONTEXTS-1:0] cie; // Context interrupt enable

   //
   // CSR read/write logic
   //
   logic [31:0]	e_csr_rval;
   logic [31:0]	e_csr_wval;
   wire [11:0]	ncsr = e_op.imm[11:0];

   // For a CSR with read side effects, the read side effect
   // should be conditioned on e_accept & e_op.csrr.
   always @(*) begin
      e_rng_rstb = 1'b0;

      unique case (ncsr)
	CSR_MTVEC:
	  e_csr_rval  = mtvec;
	CSR_MEPC:
	  e_csr_rval  = mepc;
	CSR_MCAUSE:
	  e_csr_rval  = mcause;
	CSR_TIME:
	  e_csr_rval  = ctr_time[31:0];
	CSR_TIMEH:
	  e_csr_rval  = ctr_time[63:32];
	CSR_CYCLE, CSR_MCYCLE:
	  e_csr_rval  = ctr_cycle[31:0];
	CSR_CYCLEH, CSR_MCYCLEH:
	  e_csr_rval  = ctr_cycle[63:32];
	CSR_INSTRET,  CSR_MINSTRET:
	  e_csr_rval  = ctr_instret[31:0];
	CSR_INSTRETH, CSR_MINSTRETH:
	  e_csr_rval  = ctr_instret[63:32];
	CSR_MISA:
	  e_csr_rval  = csrval_misa;
	CSR_MVENDORID:
	  e_csr_rval  = csrval_vendorid;
	CSR_MARCHID:
	  e_csr_rval  = csrval_archid;
	CSR_MIMPID:
	  e_csr_rval  = csrval_impid;
	CSR_MIP:
	  e_csr_rval  = { d_irqs, 1'b0 };
	CSR_MIE:
	  e_csr_rval  = { mie, 1'b0 };
	CSR_MSTATUS:
	  e_csr_rval  = { 28'b0,
	  cie[e_op.mcontext.m], 1'b0,
	  cie[e_op.mcontext.u], 1'b0 };
	CSR_USER_CONTEXT:
	  e_csr_rval  = e_op.mcontext.u;
	CSR_CIE:
	  e_csr_rval = cie;
	CSR_SEED: begin
	   e_csr_rval = e_rng_out;
	   e_rng_rstb = e_accept & (e_op.csrr | e_op.csrw);
	end
	default:
	  e_csr_rval  = 32'b0;
      endcase
   end

   always @(*)
     unique casez (e_op.funct3)
       3'b?01:  e_csr_wval  = e_src1;
       3'b?10:  e_csr_wval  = e_csr_rval |  e_src1;
       3'b?11:  e_csr_wval  = e_csr_rval & ~e_src1;
       default: e_csr_wval  = 32'bx;
     endcase

   wire		csrw_mtvec	  = e_op.csrw && ncsr == CSR_MTVEC;
   wire		csrw_mepc	  = e_op.csrw && ncsr == CSR_MEPC;
   wire		csrw_mcause	  = e_op.csrw && ncsr == CSR_MCAUSE;
   wire		csrw_mip	  = e_op.csrw && ncsr == CSR_MIP;
   wire		csrw_mie	  = e_op.csrw && ncsr == CSR_MIE;
   wire		csrw_mstatus	  = e_op.csrw && ncsr == CSR_MSTATUS;
   wire		csrw_user_context = e_op.csrw && ncsr == CSR_USER_CONTEXT;
   wire		csrw_cie	  = e_op.csrw && ncsr == CSR_CIE;

   //
   // Interrupt recognition
   //
   reg [IRQ_BITS-1:0] e_irq_vector;
   reg		      e_irq;

   // Note that e_irq_vector must be zero if !e_irq
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	e_irq		      <= 1'b0;
	e_irq_vector	      <= 'b0;
     end else if (~clken) begin
	logic [NUM_IRQS:1] real_irq;
	real_irq      = d_irqs & mie;

	e_irq        <= 1'b0;
	e_irq_vector <= 'b0;

	// lrsc_hold inhibits interrupts for the forward progress guarantee
	if (cie[e_op.mcontext.m] & ~lrsc_hold) begin
	   e_irq     <= |real_irq;
	   // Priority vector encoder
	   for (int i = NUM_IRQS; i > 0; i--)
	     if (real_irq[i]) e_irq_vector <= i;
	end
     end

   //
   // Successor PC (for JAL/JALR and, in the future, branch predict
   // validation.)
   //

   //
   // Branch, jump, trap and interrupt handling.
   //
   // Traps have the highest priority, followed by interrupts.
   //
   // e_succ_pc is always the subsequent instruction.
   // It is used to set the target register of JAL(R).
   //
   // e_jump_pc reflects the taken address of jumps.
   //
   // e_next_pc reflects jumps, but not traps or interrupts;
   // it is used to set mepc after an interrupt.
   //
   // e_restartpc should always reflect the latest instruction
   // executed, in case *another* pipeline stage pulls kill.
   //
   // For dead cycles, all are equivalent to the current PC.
   // e_succ_pc and e_next_pc are *not* masked, in order to detect
   // the BADPC trap.
   //
   logic [31:0] e_restartpc;
   mcontext_t   e_restart_mcontext;
   logic [31:0]	e_succ_pc;
   logic [31:0]	e_next_pc;
   logic [31:0]	e_jump_pc;

   logic	e_fencei;

   // Values to write to these register IF they are to be written...
   logic [31:0]	e_mepc;
   logic [31:0]	e_mcause;

   always @(*)
     begin
	e_trap      = 1'b0;
	e_jump      = 1'b0;	// Mispredicted jump or branch
	e_fencei    = 1'b0;
	e_succ_pc   = successor_pc(e_op, e_accept);
	e_jump_pc   = 32'bx;
	e_next_pc   = e_succ_pc;
	e_restartpc = e_next_pc & PC_MASK;
	e_restart_mcontext = e_op.mcontext;
	e_mepc      = 32'bx;
	e_mcause    = 32'bx;

	if (e_accept) begin
	   unique case (e_op.itype)
	     INSN_ERR: if (TRAP_BADINSN) begin
		e_trap      = 1'b1;
		e_mcause = MCAUSE_BADINSN;
	     end
	     INSN_ECALL: begin
		// ECALL, EBREAK
		e_trap   = 1'b1;
		e_mcause = e_op.imm[0] ? MCAUSE_BREAK : MCAUSE_ECALLM;
	     end
	     INSN_ALU: if (TRAP_BADALU) begin
		e_trap	 = e_aluctl.unit == ALUSRC_ERR;
		e_mcause = MCAUSE_BADINSN;
	     end
	     INSN_XALU:
	     if (TRAP_BADALU) begin
		e_trap			= e_aluctl.unit == ALUSRC_ERR;
		e_mcause		= MCAUSE_BADINSN;
	     end else if (e_op.funct3 == 3'b011) begin
		// .sm		-> switch to machine mode
		e_jump			= !e_op.pred_taken;
		e_jump_pc		= e_succ_pc;
		e_restart_mcontext.m	= CTX_MACHINE;
	     end
	     INSN_JAL: begin	// JAL, JALR
		e_jump	  = !e_op.pred_taken;
		e_jump_pc = e_addr;
	     end
	     INSN_BR: begin
		e_jump	  = e_cmp_out != e_op.pred_taken;
		e_jump_pc = e_op.imm;
	     end
	     INSN_MRET: begin
		e_jump               = !e_op.pred_taken;
		e_jump_pc            = mepc;
		e_restart_mcontext.m = e_restart_mcontext.u;
	     end
	     INSN_FENCEI: begin
		e_fencei	     = 1'b1;
	     end
	     default: begin
		if (csrw_user_context) begin
		   // Force a mispredict kill when writing the user context;
		   // the actual CSR write is done by the restart.
		   e_jump    = !e_op.pred_taken;
		   e_jump_pc = e_succ_pc;
		   e_restart_mcontext.u = (rcontext_t)'(e_csr_wval);
		   e_restart_mcontext.m = CTX_MACHINE;
		end
		// No control transfer
	     end
	   endcase

	   // If e_jump is set, a branch was mispredicted...
	   if (e_jump & !e_op.pred_taken)
	     e_next_pc = e_jump_pc;

	   // For an invalid PC, unless we are taking another trap...
	   if (TRAP_BADPC) begin
	      if (!e_trap && (e_next_pc & ~PC_MASK)) begin
		 e_trap = 1'b1;
		 e_mcause = MCAUSE_BADPC;
	      end
	   end

	   if (e_trap) begin
	      e_restartpc = mtvec & PC_MASK;
	      e_restart_mcontext.m = CTX_MACHINE;
	   end else begin
	     e_restartpc = e_next_pc & PC_MASK;
	   end
	end // if (e_accept)

	if (e_trap) begin
	  e_mepc       = e_op.pc & PC_MASK;
	end else if (~e_busy & e_irq) begin
	   e_restartpc = (mtvec + (e_irq_vector << 2)) & PC_MASK;
	   e_mepc      = e_next_pc & PC_MASK;
	   e_mcause    = MCAUSE_IRQ | e_irq_vector;
	end

	e_kill = e_trap | (e_irq & ~e_busy) | e_jump | e_fencei;
     end

   //
   // Register for pipeline kill "think cycle"
   //
   // These are notionally in the M stage, but DO NOT depend on
   // m_valid_i or m_busy; the pipeline will be killed at that point,
   // and these operations are touching E stage stage not M stage.
   //
   reg	       m_xcpt;		// trap or interrupt
   reg [31:0]  m_mepc;		// epc to be written if m_xcpt
   reg [31:0]  m_mcause;	// mcause to be written in m_xcpt
   reg	       m_fencei;	// Don't unkill until the real M stage is done

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	m_kill		   <= 1'b0;
	m_fencei	   <= 1'b0;
	m_trap		   <= 1'b0;
	m_xcpt		   <= 1'b0;
	m_restartpc	   <= RESET_PC & PC_MASK;
	m_restart_mcontext <= mcontext_reset();
	m_mepc		   <= 32'bx;
	m_mcause	   <= 32'bx;
     end else if (clken & ~(m_fencei & (m_busy | m_valid_o))) begin
	// For FENCE.I, keep asserting kill until the pipeline
	// is fully drained (the result of the last active instruction
	// has been accepted into the W stage.)
	m_kill		   <= e_kill;
	m_fencei	   <= e_fencei;
	m_trap		   <= e_trap;
	m_xcpt		   <= e_trap | (e_irq & ~e_busy);
	m_restartpc	   <= e_restartpc & PC_MASK;
	m_restart_mcontext <= e_restart_mcontext;
	m_mepc		   <= e_mepc & PC_MASK;
	m_mcause	   <= e_mcause;
     end

   // Handle intack and d_irq_clear
   always @(*) begin
      e_intack      = 'b0;
      d_irqs_clear  = 'b0;
      if (~e_trap & e_irq & ~e_busy) begin
	 e_intack     = e_irq_vector;
	 d_irqs_clear = 1'b1 << e_irq_vector;
      end else if (csrw_mip) begin
	 d_irqs_clear = ~e_csr_wval[NUM_IRQS:1]; // Write 0 to clear
      end
   end

   //
   // Handle mepc, mcause, mtvec, mie, cie
   //
   wire [31:0] mtvec_reset = MTVEC_RESET & PC_MASK;
   wire [31:0] mtvec_wmask = MTVEC_WMASK & PC_MASK;

   //
   // Flags for delayed updates of mepc, mcause, etc.
   //

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	mtvec        <= mtvec_reset;
	mcause       <= 32'b0;
	mepc         <= 32'b0;
	mie          <= 'b0;
	cie	     <= 'b0;
     end else if (clken) begin
	if (csrw_mtvec)
	  mtvec <= wmask(e_csr_wval, mtvec_reset, mtvec_wmask);

	if (m_xcpt)
	  mepc  <= m_mepc;
	else if (csrw_mepc)
	  mepc  <= e_csr_wval & PC_MASK;

	if (m_xcpt)
	  mcause <= m_mcause;
	else if (csrw_mcause)
	  mcause <= e_csr_wval & mcause_mask;

	if (csrw_mie)
	  mie <= e_csr_wval[NUM_IRQS:1];

	if (csrw_cie)
	  cie <= e_csr_wval;
	else if (csrw_mstatus) begin
	   cie[e_op.mcontext.u] <= e_csr_wval[1]; // mstatus.sie = user ie
	   cie[e_op.mcontext.m] <= e_csr_wval[3]; // mstatus.mie = current ie
	end
     end

   //
   // E stage output data MUX
   //
   always @(*) begin
      // No output, or delivered from M stage
      e_dout = 32'bx;
      unique case (e_op.itype)
	INSN_ALU, INSN_XALU:
	  e_dout = e_alu_out;
	INSN_MUL:
	  if (WITH_Zmmul & FORWARD_MUL)
	     e_dout = e_op.funct3[1:0] ? m_mulh_o : m_mull_o;
	INSN_JAL:
	  e_dout = e_succ_pc;
	INSN_CSR:
	  e_dout = e_csr_rval;
	INSN_ST:
	  if (WITH_Zalrsc)
	    e_dout = { 31'b0, ~lrsc_resv };
	default:
	  e_dout = 32'bx; // Suppress warning
      endcase
   end

   //
   // Load/store unit
   //

   // XXX: currently load/store instructions cannot trap; using e_trap
   // here is a speed path. However, if invalid address exceptions
   // are added, this needs to be considered here (or in the ldst unit),
   // or a memory transaction would be initiated.
   wire [31:0] ldst_dout;
   wire [3:0]  ldst_dout_wbe;
   wire	       ldst_dout_valid;
   wire	       ldst_busy;

   logic       ldst_valid;
   cbo_t       ldst_cbo;

   always @(*) begin
      ldst_valid = e_accept & insn_mem(e_op.itype);
      ldst_cbo   = { 1'b0, CBO_X };

      if (ldst_valid && e_op.itype == INSN_CBO) begin
	 unique casez (e_op.rs2.r)
	   5'b00000: ldst_cbo = { 1'b1, CBO_INVAL };
	   5'b00001: ldst_cbo = { 1'b1, CBO_CLEAN };
	   5'b00010: ldst_cbo = { 1'b1, CBO_FLUSH };
	   5'b00100: ldst_cbo = { 1'b1, CBO_ZERO  };
	   default:  ldst_cbo = { 1'b0, CBO_X };
	 endcase
	 ldst_valid = ldst_cbo.valid;
      end
   end

   ldst ldst (
     .rst_n		(rst_n),
     .clk		(clk),
     .clken		(clken),
     .valid		(ldst_valid),
     .memop_cbo		(ldst_cbo),
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
     .dbus_cbo		(dbus_cbo),
     .dbus_wrq		(dbus_wrq),
     .dbus_wbe		(dbus_wbe),
     .dbus_wdata	(dbus_wdata),
     .dbus_rdata	(dbus_rdata),
     .dbus_ready	(dbus_ready)
     );

   assign m_busy = ldst_busy;

   //
   // LR/SC state machine
   //
   logic       lrsc_hold_q;
   logic       lrsc_clear_hold;

   wire is_lr = WITH_Zalrsc & e_accept & e_op.lrsc & ~e_op.itype[0];
   wire	is_sc = WITH_Zalrsc & e_accept & e_op.lrsc &  e_op.itype[0];

   // The combinatorial part here prevents an interrupt right after LR,
   // which would violate the Ziccrse atomicity guarantee.
   assign lrsc_hold = WITH_Zalrsc & WITH_Ziccrse & (lrsc_hold_q | is_lr);

   generate
      if (WITH_Zalrsc && WITH_Ziccrse && Ziccrse_bits) begin
	 reg [Ziccrse_bits-1:0] lrsc_hold_ctr;

	 always @(negedge rst_n or posedge clk)
	   if (~rst_n)
	      lrsc_hold_ctr <= 'b0;
	   else if (clken) begin
	      if (is_lr)
		lrsc_hold_ctr <= 'b0;
	      else
		lrsc_hold_ctr <= lrsc_hold_ctr + (m_valid_o & ~m_stall);
	   end

	 assign lrsc_clear_hold = &lrsc_hold_ctr;
      end else begin
	 assign lrsc_clear_hold = 1'b0;
      end
   endgenerate

   generate
      if (WITH_Zalrsc) begin
	 always @(negedge rst_n or posedge clk)
	   if (~rst_n) begin
	      lrsc_resv     <= 1'b0;
	      lrsc_hold_q   <= 1'b0;
	   end else if (clken) begin
	      lrsc_hold_q <= WITH_Ziccrse & lrsc_hold_q & ~lrsc_clear_hold;
	      if (is_sc | m_xcpt) begin
		 lrsc_resv   <= 1'b0;
		 lrsc_hold_q <= 1'b0;
	      end else if (is_lr) begin
		 lrsc_resv   <= 1'b1;
		 lrsc_hold_q <= WITH_Ziccrse;
	      end
	   end
      end else begin
	 assign lrsc_resv   = 1'b0;
	 assign lrsc_hold_q = 1'b0;
      end
   endgenerate

   //
   // M stage output MUX
   //
   always @(*) begin
      m_dout	= m_din;
      m_dout_be = 4'b1111;
      m_valid_o = m_accept;

      unique case (m_op.itype)
       INSN_LD: begin
	  m_dout    = ldst_dout;
	  m_dout_be = ldst_dout_wbe;
	  m_valid_o = ldst_dout_valid;
       end
       INSN_MUL: begin
	  if (WITH_Zmmul)
	    m_dout  = m_op.funct3[1:0] ? m_mulh_o : m_mull_o;
       end
       default: begin
	  // See above
       end
      endcase
   end
endmodule // execute
