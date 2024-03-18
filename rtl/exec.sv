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
 output reg [NUM_IRQS:1]   d_irqs_clear, // Clear edge-triggered interrupts
 output reg [IRQ_BITS-1:0] e_intack,

 input		       e_valid_i,
 input		       e_stall,
 input		       decoded_insn_t e_op,
 output reg	       e_valid_o,
 output reg	       e_kill,
 output reg [31:0]     e_restartpc, // Address for the front end after kill
 output mcontext_t     e_restart_mcontext,
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

 // Counters
 input [63:0]	       ctr_time,
 input [63:0]	       ctr_cycle,
 input [63:0]	       ctr_instret,

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
   logic	   e_trap;
   logic	   e_jump;

   wire   e_accept  = e_valid_i & ~e_busy;
   assign e_valid_o = e_accept & ~e_trap & ~e_jump;
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
   reg [31:0] mtvec;
   reg [31:0] mepc;
   localparam [31:0] mcause_mask = MCAUSE_FIXED_MASK | {IRQ_BITS{1'b1}};
   reg [31:0] mcause;
   reg [NUM_IRQS:1] mie;
   reg [`USER_CONTEXTS+`SYS_CONTEXTS-1:0] cie; // Context interrupt enable

   //
   // CSR read/write logic
   //
   logic [31:0]	e_csr_rval;
   logic [31:0]	e_csr_wval;
   wire [11:0]	ncsr = e_op.imm[11:0];

   // For a CSR with read side effects, the read side effect
   // should be conditioned on e_op.csrr.
   always @(*)
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
	 e_csr_rval  = core.csrval_misa;
       CSR_MVENDORID:
	 e_csr_rval  = core.csrval_vendorid;
       CSR_MARCHID:
	 e_csr_rval  = core.csrval_archid;
       CSR_MIMPID:
	 e_csr_rval  = core.csrval_impid;
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
	 e_csr_rval  = cie;
       default:
	 e_csr_rval  = 32'b0;
     endcase

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

	if (cie[e_op.mcontext.m]) begin
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
   logic [31:0]	trap_mcause;
   logic [31:0]	e_succ_pc;
   logic [31:0]	e_next_pc;
   logic [31:0]	e_jump_pc;

   always @(*)
     begin
	e_trap      = 1'b0;
	e_jump      = 1'b0;	// Mispredicted jump or branch
	trap_mcause = 32'bx;
	e_succ_pc   = successor_pc(e_op, e_accept);
	e_jump_pc   = 32'bx;
	e_next_pc   = e_succ_pc;
	e_restartpc = e_next_pc & core.PC_MASK;
	e_restart_mcontext = e_op.mcontext;

	if (e_accept) begin
	   unique case (e_op.itype)
	     INSN_ERR: if (core.TRAP_BADINSN) begin
		e_trap      = 1'b1;
		trap_mcause = MCAUSE_BADINSN;
	     end
	     INSN_ECALL: begin	// ECALL, EBREAK
		e_trap	 = 1'b1;
		trap_mcause = e_op.imm[0] ? MCAUSE_BREAK : MCAUSE_ECALLM;
	     end
	     INSN_ALU: if (core.TRAP_BADALU) begin
		e_trap	 = e_aluctl.unit == ALUSRC_ERR;
		trap_mcause = MCAUSE_BADINSN;
	     end
	     INSN_JAL: begin	// JAL, JALR
		e_jump	  = !e_op.pred_taken;
		e_jump_pc = e_addr;
	     end
	     INSN_BR: begin
		e_jump	  = e_cmp_out != e_op.pred_taken;
		e_jump_pc = e_op.imm; // rs1 is not part of the jump addr!
	     end
	     INSN_MRET: begin
		e_jump               = !e_op.pred_taken;
		e_jump_pc            = mepc;
		e_restart_mcontext.m = e_restart_mcontext.u;
	     end
	     default: begin
		if (csrw_user_context) begin
		   rcontext_t new_ctx;
		   new_ctx = rcontext_t ' (e_csr_wval);
		   // Force a mispredict kill when writing the user context;
		   // the actual CSR write is done by the restart.
		   // Writing user_context always goes to machine mode;
		   // writing zero goes to machine mode without actually
		   // modifying the user_context.
		   e_jump    = 1'b1;
		   e_jump_pc = e_succ_pc;
		   if (new_ctx)
		     e_restart_mcontext.u = new_ctx;
		   e_restart_mcontext.m = CTX_MACHINE;
		end
		// No control transfer
	     end
	   endcase

	   // If e_jump is set, a branch was mispredicted...
	   if (e_jump & !e_op.pred_taken)
	     e_next_pc = e_jump_pc;

	   // For an invalid PC, unless we are taking another trap...
	   if (core.TRAP_BADPC) begin
	      if (!e_trap && (e_next_pc & ~core.PC_MASK)) begin
		 e_trap = 1'b1;
		 trap_mcause = MCAUSE_BADPC;
	      end
	   end

	   if (e_trap) begin
	      e_restartpc = mtvec & core.PC_MASK;
	      e_restart_mcontext.m = CTX_MACHINE;
	   end else begin
	     e_restartpc = e_next_pc & core.PC_MASK;
	   end
	end // if (e_accept)

	if (!e_trap & ~e_busy & e_irq) begin
	   e_restartpc   = (mtvec + (e_irq_vector << 2)) & core.PC_MASK;
	   e_restart_mcontext.m = CTX_MACHINE;
	end

	e_kill		= e_trap | (e_irq & ~e_busy) | e_jump;
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

   // XXX: add a "think cycle" for KILL?

   //
   // Handle mepc, mcause, mtvec, mie, cie
   //
   wire [31:0] mtvec_reset = core.MTVEC_RESET & core.PC_MASK;
   wire [31:0] mtvec_wmask = core.MTVEC_WMASK & core.PC_MASK;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	mtvec        <= mtvec_reset;
	mcause       <= 32'b0;
	mepc         <= 32'b0;
	mie          <= 'b0;
	cie	     <= 'b0;
     end else if (e_clken) begin
	if (csrw_mtvec)
	  mtvec <= wmask(e_csr_wval, mtvec_reset, mtvec_wmask);

	// XXX: writing mepc seems to be a frequency limiter; it could
	// probably be written in the M stage (post-kill) instead.
	if (e_trap)
	  mepc  <= e_op.pc & core.PC_MASK;
	else if (e_irq & ~e_busy)
	  mepc  <= e_next_pc & core.PC_MASK;
	else if (csrw_mepc)
	  mepc  <= e_csr_wval & core.PC_MASK;

	if (e_trap)
	  mcause <= trap_mcause;
	else if (e_irq & ~e_busy)
	  mcause <= MCAUSE_IRQ | e_irq_vector;
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
   always @(*)
     unique case (e_op.itype)
       INSN_ALU:  e_dout = e_alu_out;
       INSN_MULL: e_dout = m_mull_o;
       INSN_JAL:  e_dout = e_succ_pc;
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
