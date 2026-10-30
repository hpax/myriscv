//
// Copyright (C) 2024-2026 H. Peter Anvin <hpa@zytor.com>
//
// This handles the backend of the pipe; the E, M and W pipeline stages.
//

`include "myriscv.vh"

// Compute the new value for a register under mask
function automatic logic [31:0] wmask(
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
 // Bit 0 is included in these bitmasks mostly to make simulation easier
 // to read.
 input [NUM_IRQS:0]	   d_irqs,
 output reg [NUM_IRQS:0]   d_irqs_clear, // Clear edge-triggered interrupts
 output reg [IRQ_BITS-1:0] e_intack,

 // These are ports rather than parameters mainly to benefit simulation;
 // they are expected to be synthesis-time constants when generating logic.
 input [NUM_IRQS:0]	   irq_intable,	 // IRQ events can trigger interrupts
 input [NUM_IRQS:0]	   irq_waitable, // IRQ events can be waited for

 input			   e_valid_i,
 input			   e_stall,
 input			   decoded_insn_t e_op,
 output reg		   e_valid_o,
 output reg		   m_kill,
 output reg [31:0]	   m_restartpc,	 // Address for the front end after kill
 output			   mcontext_t m_restart_mcontext,
 output			   retstack_t m_restart_retstack,
 output reg		   e_busy,
 input			   d_rs1_e,
 input			   d_rs1_m,
 input			   d_rs1_w,
 input			   d_rs2_e,
 input			   d_rs2_m,
 input			   d_rs2_w,

 // D-stage cache lookup bypass
 input			   d_valid_o,
 input			   d_advance,
 output logic [31:0]	   dcache_lookup_a,
 output logic		   dcache_lookup_valid,
 output logic		   dcache_lookup_hold,
 output cbo_t		   dcache_lookup_cbo,
 output logic		   dcache_lookup_wrq,

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
 input			   rng_bus_t rng,
 output			   rng_full,

 // Data output, unregistered and registered
 output reg [31:0]	   e_dout,
 output reg [31:0]	   m_din,

 // Data bus from ldst unit
 output [31:0]		   dbus_a,
 output			   dbus_valid,
 output			   cbo_t dbus_cbo,
 output			   dbus_wrq,
 output [3:0]		   dbus_wbe,
 output [31:0]		   dbus_wdata,
 input [31:0]		   dbus_rdata,
 input			   dbus_ready,
 input			   dbus_busy
 );

   function logic [4:0] tocontext(logic [31:0] ctx);
      tocontext = (ctx >= CONTEXTS) ? CTX_X : (ctx[4:0] & CTX_MASK);
   endfunction

   // Canonical MISA value, regardless if it is exposed as CSR or not
   localparam [31:0] MISA = {
	       WITH_Zalrsc & WITH_Zaamo,	// A
	       WITH_Zba & WITH_Zbb & WITH_Zbs,	// B
	       WITH_RVC,			// C
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

   //
   // CSR registers
   //
   localparam bit vectored_irqs_supported = IRQ_VECTOR_BITS > 0;

   // These are the bits that can possibly be 1 in MTVEC, regardless
   // of whether or not they are actually set or settable.
   localparam [31:0]	  mtvec_mask =
			  { PC_MASK[31:2], 1'b0, vectored_irqs_supported };

   localparam [31:0] mtvec_reset = MTVEC_RESET & mtvec_mask;
   localparam [31:0] mtvec_wmask = MTVEC_WMASK & mtvec_mask;

   reg [31:0]  mtvec	   = mtvec_reset;
   reg [31:0]  mepc;
   localparam [31:0] mcause_mask = MCAUSE_FIXED_MASK | {IRQ_BITS{1'b1}};
   reg [31:0]  mcause;
   reg [NUM_IRQS:0] mie        = 'b0;
   reg [CONTEXTS-1:0] cie = 'b0; // Context interrupt enable
   wire [31:0] csrval_misa = WITH_misa ? MISA : 32'b0;

   wire [31:0] csrval_ncontexts;
   assign csrval_ncontexts[31:16] = 16'b0;
   assign csrval_ncontexts[15:8]  = WITH_ncontexts ? CONTEXTS-1 : 8'b0;
   assign csrval_ncontexts[7:0]   = WITH_ncontexts ? CTX_MIN_USER : 8'b0;

   //
   // Pipeline control signals and pipeline stage input/output
   //
   logic	   e_kill;

   wire		   e_clken = clken & (~e_stall | e_busy | e_kill);
   wire		   m_clken = clken & (~m_stall | m_busy | m_kill);
   wire		   w_clken = clken & m_valid_o;

   wire [31:0]	   d_rs1_data;
   wire [31:0]	   d_rs2_data;
   reg [31:0]	   m_dout;
   reg [3:0]	   m_dout_be;

   // LR/SC state machine outputs
   logic lrsc_resv;		// Reservation set held (SC returns 0)
   logic lrsc_hold;		// Inhibit interrupts (atomic sequence)

   // E-stage pipeline synchronization signals
   logic	   e_restart;           // Pipeline restart needed
   logic	   e_trap;		// Taking a trap
   logic	   e_really_busy;	// Uninterruptably busy
   logic	   e_waiting;		// Waiting for an event
   logic	   e_irq_ok;		// May take interrupts
   logic	   e_pc_ok;		// e_op.pc == e_pc

   assign e_really_busy = 1'b0;
   assign e_busy        = e_waiting | e_really_busy;
   assign e_irq_ok      = cie[e_op.mcontext.m] & ~lrsc_hold & ~e_really_busy;

   // e_op contains an instruction which *could* be accepted.
   // m_kill will not be reflected in e_valid_i because it ends
   // up on the wrong side of a register; this could be fixed,
   // though...

   // e_op contains an instruction which *could* be accepted
   wire e_acceptable = e_valid_i & ~e_really_busy & ~m_kill;

   // Trigger a branch mispredict restart
   wire	e_mispredict = e_acceptable & ~e_pc_ok & e_op.pc_valid;

   // Actually perform this instruction
   wire	e_accept     = e_acceptable & ~e_waiting & e_pc_ok;

   // This does not consider m_trap due to a speed path.
   assign e_valid_o = e_accept;

   // M-stage pipeline synchronization signals
   reg	  m_trap;

   wire	  m_accept = m_valid_i & ~m_busy & ~m_trap;

   // Latched output to M stage; also used by the bypass network
   always @(posedge clk)
     if (e_clken)
       m_din <= e_dout;

   // Register file
   regfile #(`CFG) regs
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

   // D stage bypass (combinatorial)
   logic [31:0]	      d_srs1;	// rs1 value reg-only mux
   logic [31:0]	      d_srs2;	// rs2 value reg-only mux
   logic [31:0]	      d_src1;
   logic [31:0]	      d_src2;

   always_comb begin
      if (d_rs1_e)
	d_srs1 = e_dout;	// Data comes from the E stage
      else if (d_rs1_m)
	d_srs1 = m_dout;	// Data comes from the M stage
      else if (d_rs1_w)
	d_srs1 = w_dout;	// Data comes from the W stage
      else
	d_srs1 = d_rs1_data;	// Data comes from the register file

      // rs1.r can be used an immediate
      d_src1 = d_op.rs1_valid ? d_srs1 : d_op.rs1.r;

      if (d_rs2_e)
	d_srs2 = e_dout;	// Data comes from the E stage
      else if (d_rs2_m)
	d_srs2 = m_dout;	// Data comes from the M stage
      else if (d_rs2_w)
	d_srs2 = w_dout;	// Data comes from the W stage
      else if (!REGFILE_ZERO_INIT && !d_op.rs2.r)
	d_srs2 = 32'b0;		// Data comes from register x0
      else
	d_srs2 = d_rs2_data;	// Data comes from the register file

      // src2 can be an arbitrary immediate, independent of d_op.rs2.r
      d_src2 = d_op.rs2_valid ? d_srs2 : d_op.imm;
   end

   logic [31:0] e_src1;
   logic [31:0] e_src2;
   generate
      if (EARLY_BYPASS_MUX) begin : bypass_early
	always @(negedge rst_n or posedge clk)
	  if (~rst_n) begin
	     e_src1 <= 32'bx;
	     e_src2 <= 32'bx;
	  end else if (!d_src_hold) begin
	     e_src1 <= d_src1;
	     e_src2 <= d_src2;
	  end
      end else begin : bypass_late
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
	     //
	     // XXX: THIS IS NO LONGER TRUE WITH WAITFOR
	     if (~d_src_hold) begin
		e_rs1_m <= d_rs1_e;
		e_rs1_w <= d_rs1_m;
		e_rs2_m <= d_rs2_e;
		e_rs2_w <= d_rs2_m;
	     end
	  end

	 always_comb begin
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

   // Early address computation for dcache
   assign dcache_lookup_hold = d_src_hold;

   always_comb begin
      logic [1:0]  a_scale;
      logic [31:0] a_addend;
      a_scale		     = 2'd0;
      a_addend               = d_op.imm;
      dcache_lookup_valid    = d_advance & insn_mem(d_op.itype);
      dcache_lookup_cbo      = CBO_NONE;
      dcache_lookup_wrq      = d_op.itype[0];

      unique case (d_op.itype)
	 INSN_LD: begin
	    if (WITH_Zilx && d_op.rs2_valid) begin
	       a_scale	= d_op.funct3[1:0];
	       a_addend = d_srs2;
	    end
	 end
	 INSN_CBO: begin
            unique casez (d_op.rs2.r)
              5'b00000: dcache_lookup_cbo = CBO_INVAL;
              5'b00001: dcache_lookup_cbo = CBO_CLEAN;
              5'b00010: dcache_lookup_cbo = CBO_FLUSH;
              default:  dcache_lookup_cbo = CBO_X;
            endcase
            dcache_lookup_valid = dcache_lookup_valid &
				  cbo_valid(dcache_lookup_cbo);
	 end
	default: begin
	   // No changes
	end
      endcase

      // Using d_src1 rather than d_srs1 here is necessary because
      // the JAL logic uses e_addr which is produced from this value
      if (a_scale < 2'd2)
	dcache_lookup_a = (d_src1 << a_scale) + a_addend;
      else
	dcache_lookup_a = 'bx;
   end

   //
   // AGU adder; reuse the value already calculated for dcache_lookup_a
   // XXX: does this make sense for WITH_Zilx?
   //
   logic [31:0]	e_addr;
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	e_addr <= 'bx;
     end else if (clken) begin
	if (!d_src_hold)
	  e_addr <= dcache_lookup_a;
     end

   // ALU
   aluctl_t e_aluctl;
   wire [31:0] e_alu_out;
   wire	       e_cmp_out;

   generate
      if (ALU_EARLY_DECODE) begin : alu_decode_early
	 aluctl_t d_aluctl;
	 alu_decode #(`CFG) alu_decode (.op(d_op), .ctl(d_aluctl));
	 always @(negedge rst_n or posedge clk)
	   if (~rst_n)
	     e_aluctl <= 'bx;
	   else if (e_clken)
	     e_aluctl <= d_aluctl;
      end else begin : alu_decode
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
   // mscratch CSR
   //
   logic [31:0] csrval_mscratch;

   //
   // CSR read/write logic
   //
   logic [31:0]	e_csr_rval;
   logic [31:0]	e_csr_wval;

   // If !WITH_indcsr there is no reason to wait for e_src2...
   wire  [11:0]	ncsr = WITH_indcsr ? e_src2[11:0] : e_op.imm[11:0];

   // For a CSR with read side effects, the read side effect
   // should be conditioned on e_accept & e_op.csrr.
   always @(*) begin
      e_rng_rstb = 1'b0;
      e_csr_rval = 32'b0;

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
	  e_csr_rval  = d_irqs;
	CSR_MIE:
	  e_csr_rval  = mie;
	CSR_MSTATUS:
	  e_csr_rval  = { 28'b0,
	  WITH_mstatus & cie[e_op.mcontext.m], 1'b0,
	  WITH_mstatus & cie[e_op.mcontext.u], 1'b0 };
	CSR_USER_CONTEXT:
	  e_csr_rval  = e_op.mcontext.u;
	CSR_SYS_CONTEXT:
	  e_csr_rval  = WITH_sys_context ? e_op.mcontext.m : 32'b0;
	CSR_NCONTEXTS:
	  e_csr_rval  = csrval_ncontexts;
	CSR_CIE:
	  e_csr_rval  = cie;
	CSR_MSCRATCH:
	  e_csr_rval  = WITH_mscratch ? csrval_mscratch : 32'b0;
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

   logic csrw_mtvec;
   logic csrw_mepc;
   logic csrw_mcause;
   logic csrw_mip;
   logic csrw_mie;
   logic csrw_mstatus;
   logic csrw_user_context;
   logic csrw_cie;
   logic csrw_waitfor;
   logic csrw_mscratch;

   always_comb
     begin
        csrw_mtvec        = 1'b0;
        csrw_mepc         = 1'b0;
        csrw_mcause       = 1'b0;
        csrw_mip          = 1'b0;
        csrw_mie          = 1'b0;
        csrw_mstatus      = 1'b0;
        csrw_user_context = 1'b0;
        csrw_cie          = 1'b0;
        csrw_waitfor      = 1'b0;
        csrw_mscratch     = 1'b0;

	if (e_valid_i & e_op.undead & e_op.csrw) begin
	   unique case (ncsr)
	     CSR_MTVEC:		csrw_mtvec	  = |MTVEC_WMASK;
	     CSR_MEPC:          csrw_mepc	  = 1'b1;
	     CSR_MCAUSE:        csrw_mcause	  = 1'b1;
	     CSR_MIP:           csrw_mip	  = NUM_IRQS != 0;
	     CSR_MIE:           csrw_mie	  = NUM_IRQS != 0;
	     CSR_MSTATUS:       csrw_mstatus	  = WITH_mstatus;
	     CSR_USER_CONTEXT:  csrw_user_context = 1'b1;
	     CSR_CIE:		csrw_cie	  = NUM_IRQS != 0;
	     CSR_WAITFOR:       csrw_waitfor	  = WITH_waitfor && NUM_IRQS;
	     CSR_MSCRATCH:      csrw_mscratch     = WITH_mscratch;
	     default: begin end
	   endcase
	end
     end

   //
   // mscratch register, if implemented; it isn't that useful for
   // anything other than CSR logic testing given the register context
   // system, but it *is* useful for that...
   //
   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       csrval_mscratch <= 'b0;
     else if (clken)
       if (csrw_mscratch) begin
	  csrval_mscratch <= e_csr_wval;
       end

   //
   // Interrupt recognition
   //
   reg [IRQ_BITS-1:0] e_irq_vector;
   reg		      e_irq;
   reg		      e_wakeup;

   // Note that e_irq_vector must be zero if !e_irq
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	e_irq		<= 1'b0;
	e_wakeup	<= 1'b0;
	e_irq_vector	<= 'b0;
     end else if (clken) begin
	// IRQs that generates interrupts
	logic [NUM_IRQS:0] irq_int;
	// IRQs that generate wait wakeups
	logic [NUM_IRQS:0] irq_wakeup;

	irq_int		= d_irqs & irq_intable & mie;
	irq_wakeup	 = d_irqs & irq_waitable & e_csr_wval[NUM_IRQS:0];

	// Waiting for an event? Check for wakeup. Because this adds a
	// cycle of latency, we must already have waited for one cycle;
	// thus, writing waitfor takes 2 cycles if the event is
	// already pending. This is needed so e_csr_wval can stabilize.
	e_wakeup	<= e_waiting & |irq_wakeup;
	e_irq		<= |irq_int;

	// Priority vector encoder
	e_irq_vector	<= 'b0;
	for (int i = NUM_IRQS; i > 0; i--)
	  if (irq_int[i]) e_irq_vector <= i;
     end

   //
   // Waiting...
   //
   assign e_waiting = csrw_waitfor & !e_wakeup;

   //
   // Branch, jump, trap and interrupt handling.
   //
   // Traps have the highest priority, followed by interrupts.
   //
   // e_pc is the expected PC for the current instruction. If this is
   // different from e_op.pc for an instruction that would otherwise
   // be accepted this constitutes a branch mispredict.
   //
   // e_succ_pc is always the subsequent instruction.
   // It is used to set the target register of JAL(R).
   //
   // e_jump_pc reflects the taken address of jumps.
   //
   // e_next_pc reflects jumps, but not traps or interrupts;
   // it is used to set mepc after an interrupt.
   //
   // e_restartpc is the next instruction to be executed, regardless
   // of if a pipeline restart is required or not.
   //
   // For dead cycles, all are equivalent to the current PC.
   // e_succ_pc and e_next_pc are *not* masked, in order to detect
   // the BADPC trap.
   //
   reg   [31:0] e_pc;
   logic [31:0] e_restartpc;
   mcontext_t   e_restart_mcontext;
   logic [31:0]	e_succ_pc;
   logic [31:0]	e_next_pc;
   logic [31:0]	e_jump_pc;

   logic	e_fencei;

   // Values to write to these register IF they are to be written...
   logic [31:0]	e_mepc;
   logic [31:0]	e_mcause;

   wire		do_vector_interrupts = IRQ_VECTOR_BITS && (mtvec & 1);
   wire [31:0]	mtvec_addr = { mtvec[31:2], 2'b00 } & PC_MASK;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       e_pc <= RESET_PC & PC_MASK;
     else if (e_accept & (e_kill | ~e_stall)) // e_kill correct here?
       e_pc <= e_restartpc;

   assign e_pc_ok = e_op.pc == e_pc;

   always @(*)
     begin
	e_fencei	   = 1'b0;
	e_succ_pc	   = e_pc;
	e_next_pc	   = e_pc;
	e_restartpc	   = e_pc;
	e_restart	   = 1'b0;
	e_restart_mcontext = e_op.mcontext;
	e_trap		   = 1'b0;
	e_mepc		   = 32'bx;
	e_mcause	   = 32'bx;

	if (e_accept) begin
	   e_succ_pc  += e_op.i16 ? 3'd2 : 3'd4;
	   e_next_pc   = e_succ_pc;

	   unique case (e_op.itype)
	     INSN_ERR: if (TRAP_BADINSN) begin
		e_trap		      = 1'b1;
		e_mcause              = MCAUSE_BADINSN;
	     end
	     INSN_ECALL: begin
		// ECALL, EBREAK
		e_trap                = 1'b1;
		e_mcause              = e_op.imm[0]
					? MCAUSE_BREAK : MCAUSE_ECALLM;
	     end
	     INSN_ALU: if (TRAP_BADALU) begin
		e_trap                = e_aluctl.unit == ALUSRC_ERR;
		e_mcause              = MCAUSE_BADINSN;
	     end
	     INSN_XALU:
	     if (TRAP_BADALU) begin
		e_trap		      = e_aluctl.unit == ALUSRC_ERR;
		e_mcause	      = MCAUSE_BADINSN;
	     end else if (e_op.funct3 == 3'b011) begin
		// .su, .sc	-> switch to context
		// Could check if the context changes
		// XXX: make sure that the rest of the instruction retires!
		e_restart	     = 1'b1;
		e_restart_mcontext.m = e_op.rd.c;
	     end
	     INSN_JAL: begin	// JAL, JALR
		e_next_pc	     = e_addr;
	     end
	     INSN_BR: begin
		if (e_cmp_out)
		  e_next_pc          = e_op.imm;
	     end
	     INSN_MRET: begin
		// XXX: MRET should be fully predictable now
		e_restart            = 1'b1;
		e_next_pc            = mepc;
		e_restart_mcontext.m = e_restart_mcontext.u;
	     end
	     INSN_FENCEI: begin
		e_fencei             = 1'b1;
	     end
	     default: begin
		if (csrw_user_context) begin
		   // Force a restart when writing the user context;
		   // the actual CSR write is done by the restart.
		   e_restart            = 1'b1;
		   e_restart_mcontext.u = tocontext(e_csr_wval);
		   e_restart_mcontext.m = CTX_MACHINE;
		end
		// No control transfer
	     end
	   endcase

	   // By specification, bit 0 in jump targets is ignored
	   // and does not cause a bad PC trap
	   e_next_pc[0] = 1'b0;

	   // For an invalid PC, unless we are taking another trap...
	   if (TRAP_BADPC && !e_trap && (e_next_pc & ~PC_MASK)) begin
	      e_trap   = 1'b1;
	      e_mcause = MCAUSE_BADPC;
	   end

	   if (e_trap) begin
	      e_mepc               = e_op.pc;
	      e_restartpc          = mtvec_addr;
	      e_restart_mcontext.m = CTX_MACHINE;
	   end else begin
	      e_restartpc          = e_next_pc;
	   end
	end

	if (~e_trap & e_irq & e_irq_ok) begin
	   e_restartpc    = mtvec_addr;
	   if (do_vector_interrupts)
	     e_restartpc += e_irq_vector << IRQ_VECTOR_BITS;
	   e_mepc	 = e_next_pc;
	   e_mcause	 = MCAUSE_IRQ | e_irq_vector;
	   e_restart     = 1'b1;
	end

	e_mepc      &= PC_MASK;
	e_restartpc &= PC_MASK;

	e_kill = e_restart | e_trap | e_mispredict | e_fencei;
     end

   //
   // Register for pipeline kill "think cycle"
   //
   // These are notionally in the M stage, but DO NOT depend on
   // m_valid_i or m_busy; the pipeline will be killed at that point,
   // and these operations are touching E stage registers not M stage.
   //
   reg	       m_xcpt;		// trap or interrupt
   reg [31:0]  m_mepc;		// epc to be written if m_xcpt
   reg [31:0]  m_mcause;	// mcause to be written in m_xcpt
   reg	       m_fencei;	// Don't unkill until the real M stage is done

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	m_kill		     <= 1'b0;
	m_fencei	     <= 1'b0;
	m_trap		     <= 1'b0;
	m_xcpt		     <= 1'b0;
	m_restartpc	     <= RESET_PC & PC_MASK;
	m_restart_mcontext.m <= CTX_MACHINE;
	m_restart_mcontext.u <= CTX_MIN_USER;
	m_restart_retstack   <= 'bx;
	m_mepc		     <= 32'bx;
	m_mcause	     <= 32'bx;
     end else if (clken & ~(m_fencei & (dbus_busy | m_busy | m_valid_o))) begin
	// For FENCE.I, keep asserting kill until the pipeline
	// is fully drained (the result of the last active instruction
	// has been accepted into the W stage.)
	m_kill		   <= e_kill;
	m_fencei	   <= e_fencei;
	m_trap		   <= e_trap;
	m_xcpt		   <= e_trap | (e_irq & e_irq_ok);
	m_restartpc	   <= e_restartpc & PC_MASK;
	m_restart_mcontext <= e_restart_mcontext;
	if (e_accept)
	  m_restart_retstack <= e_op.retstack;
	m_mepc		   <= e_mepc & PC_MASK;
	m_mcause	   <= e_mcause;
     end

   // Handle intack and d_irq_clear
   always @(*) begin
      e_intack      = 'b0;
      d_irqs_clear  = 'b0;
      if (~e_trap & e_irq & e_irq_ok) begin
	 e_intack     = e_irq_vector;
	 d_irqs_clear = 1'b1 << e_irq_vector;
      end else if (csrw_mip) begin
	 d_irqs_clear = ~e_csr_wval[NUM_IRQS:1]; // Write 0 to clear(?!)
      end
   end

   //
   // Handle mepc, mcause, mtvec, mie, cie
   //

   //
   // Flags for delayed updates of mepc, mcause, etc.
   //

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	mtvec        <= mtvec_reset;
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
	  mie <= e_csr_wval[NUM_IRQS:0] & irq_intable;

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
      ldst_cbo   = CBO_NONE;

      if (ldst_valid && e_op.itype == INSN_CBO) begin
	 unique casez (e_op.rs2.r)
	   5'b00000: ldst_cbo = CBO_INVAL;
	   5'b00001: ldst_cbo = CBO_CLEAN;
	   5'b00010: ldst_cbo = CBO_FLUSH;
	   // 5'b00100: ldst_cbo = CBO_ZERO;
	   default:  ldst_cbo = CBO_X;
	 endcase
	 ldst_valid = cbo_valid(ldst_cbo);
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
      if (WITH_Zalrsc && WITH_Ziccrse && Ziccrse_bits) begin : zirccrse
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
      end else begin : no_zirccrse
	 assign lrsc_clear_hold = 1'b0;
      end
   endgenerate

   generate
      if (WITH_Zalrsc) begin : zalrsc
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
      end else begin : no_zalrsc
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
