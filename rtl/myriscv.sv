// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>

`include "myriscv.vh"

module myriscv #(`CONFIG) (
   input		     rst_n,
   input		     clk,
   input		     clken,

   inout tri0 [63:0]	     ctr_time,
   output [63:0]	     ctr_cycle,
   output [63:0]	     ctr_instret,

   bus_if.memory_initiator    mem,
   bus_if.initiator	     io,

   // irq_edge selects edge-triggered inputs. irq_intable and
   // irq_waitable can disable inputs at compile time.
   input tri0 [NUM_IRQS:0]    irq,
   input tri0 [NUM_IRQS:0]    irq_edge,
   input tri1 [NUM_IRQS:0]    irq_intable,
   input tri1 [NUM_IRQS:0]    irq_waitable,
   output [IRQ_BITS-1:0]      irq_intack,
   output reg		     buserr,

   input tri0		     rng_data,
   input tri1		     rng_stb,
   input tri0		     rng_incr,
   input tri1		     rng_bist,
   input tri0		     rng_dead,
   output		     rng_full
   );

   bus_if ibus();
   bus_if #(.writeable(1'b1), .cache_ops(1'b1), .posted(1'b1)) dbus();
   bus_if ibus_tcm();
   bus_if #(.writeable(1'b1)) dbus_tcm();
   bus_if ibus_mem();
   bus_if #(.writeable(1'b1), .cache_ops(1'b1), .posted(1'b1)) dbus_mem();

   logic [31:0]		     io_wdata;
   logic		     io_wrq;
   logic [3:0]		     io_wbe;
   logic [31:0]		     mem_wdata;
   logic		     mem_wrq;
   logic [3:0]		     mem_wbe;
   assign io.wdata = io_wdata;
   assign io.wrq = io_wrq;
   assign io.wbe = io_wbe;
   assign mem.wdata = mem_wdata;
   assign mem.wrq = mem_wrq;
   assign mem.wbe = mem_wbe;

   logic [31:0]		     io_rdata_q;
   logic		     io_ready_q;
   logic		     dbus_is_cbo;
   wire [31:0]		     dcache_lookup_a;
   wire			     dcache_lookup_valid;
   wire			     dcache_lookup_hold;
   wire			     d_advance;
   cbo_t		     dcache_lookup_cbo;
   wire			     dcache_lookup_wrq;

   logic		     dbus_err_sel;
   logic		     dbus_tcm_sel;
   logic		     dbus_mem_sel;
   logic		     dbus_io_sel;

   logic		     ibus_err_sel;
   logic		     ibus_tcm_sel;
   logic		     ibus_mem_sel;

   //
   // Common control signal
   //
   assign dbus_is_cbo = cbo_valid(dbus.cbo);

   assign ibus_tcm.a = ibus.a;
   assign ibus_tcm.valid = ibus_tcm_sel;
   assign ibus_mem.a = ibus.a;
   assign ibus_mem.valid = ibus_mem_sel;
   assign dbus_tcm.a = dbus.a;
   assign dbus_tcm.valid = dbus_tcm_sel;
   assign dbus_tcm.wdata = dbus.wdata;
   assign dbus_tcm.wrq = dbus.wrq;
   assign dbus_tcm.wbe = dbus.wbe;
   assign dbus_mem.a = dbus.a;
   assign dbus_mem.valid = dbus.valid;
   assign dbus_mem.wdata = dbus.wdata;
   assign dbus_mem.wrq = dbus.wrq;
   assign dbus_mem.wbe = dbus.wbe;
   assign dbus_mem.cbo = dbus.cbo;

   //
   // Memory map decode
   //
   always @(*)
     begin
	dbus_err_sel = 1'b0;
	dbus_tcm_sel = 1'b0;
	dbus_mem_sel = 1'b0;
	dbus_io_sel  = 1'b0;
	if (dbus.valid) begin
	   if (dbus.a < tcm_base)
	     dbus_err_sel = 1'b1;
	   else if (dbus.a < ram_base)
	     dbus_tcm_sel = tcm_size_bits > 0;
	   else if (dbus.a < io_base)
	     dbus_mem_sel = ram_size_bits > 0;
	   else
	     dbus_io_sel = 1'b1;
	end

	ibus_err_sel = 1'b0;
	ibus_tcm_sel = 1'b0;
	ibus_mem_sel = 1'b0;
	// Instruction fetches from I/O are not supported

	if (ibus.valid) begin
	   if (ibus.a < tcm_base)
	     ibus_err_sel = 1'b1;
	   else if (ibus.a < ram_base)
	     ibus_tcm_sel = tcm_size_bits > 0;
	   else if (ibus.a < io_base)
	     ibus_mem_sel = ram_size_bits > 0;
	   else
	     ibus_err_sel = 1'b1;
	end
     end

   // Bus error
   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       buserr <= 1'b0;
     else
       buserr <= ibus_err_sel | dbus_err_sel;

   generate
      if (tcm_size_bits) begin
	 // Ignore dbus.cbo, it is safe to simply treat them as reads.
	 tcm #(`CFG) tcm (
	   .rst_n	(rst_n),
	   .clk		(clk),
	   .clken	(clken),
	   .ibus	(ibus_tcm),
	   .dbus	(dbus_tcm)
	   );
      end else begin
	 assign dbus_tcm.rdata = 32'bx;
	 assign dbus_tcm.ready = 1'b0;
	 assign ibus_tcm.rdata = 32'bx;
	 assign ibus_tcm.ready = 1'b0;
      end
   endgenerate

   // External memory and caches

   generate
      if (!ram_size_bits) begin
	 assign ibus_mem.rdata = 32'bx;
	 assign ibus_mem.ready = 1'b0;
	 assign dbus_mem.rdata = 32'bx;
	 assign dbus_mem.ready = 1'b0;
	 assign dbus_mem.busy = 1'b0;
	 assign mem.a = '0;
	 assign mem.valid = 1'b0;
	 assign mem_wdata = '0;
	 assign mem_wrq = 1'b0;
	 assign mem_wbe = '0;
      end else begin
	 // Instruction cache

	 bus_if #(.address_bits(ram_size_bits), .snoop(1'b1)) imem();
	 bus_if #(.address_bits(ram_size_bits), .writeable(1'b1),
		  .posted(1'b1)) dmem();

	 assign imem.rdata = mem.rdata;
	 assign imem.a_in = mem.a_in;
	 assign imem.inval = mem.inval;
	 assign dmem.rdata = mem.rdata;

	 icache #(`CFG) icache (
	   .rst_n (rst_n),
	   .clk   (clk),
	   .clken (clken),

	   .ibus (ibus_mem),
	   .imem (imem)
	   );

	 // Data cache
	 dcache #(`CFG) dcache (
	    .rst_n (rst_n),
	    .clk   (clk),
	    .clken (clken),

	    .dbus (dbus_mem),

	    .lookup_a_i     (dcache_lookup_a),
	    .lookup_valid_i (dcache_lookup_valid),
	    .lookup_hold_i  (dcache_lookup_hold),
	    .lookup_cbo_i   (dcache_lookup_cbo),
	    .lookup_wrq_i   (dcache_lookup_wrq),

	    .dmem (dmem)
	 );

	 // Memory bus
	 reg			  mem_is_dbus;
	 assign dmem.ready = mem.ready &  mem_is_dbus;
	 assign imem.ready = mem.ready & ~mem_is_dbus;
	 assign dmem.busy  = mem.busy  &  mem_is_dbus;

	 always @(negedge rst_n or posedge clk)
	   if (~rst_n) begin
	      mem.valid      <= 1'b0;
	      mem_wrq        <= 1'bx;
	      mem_wbe	     <= 4'bx;
	      mem_is_dbus    <= 1'bx;
	      mem.a	     <= 'bx;
	      mem_wdata      <= 32'bx;
	   end else if (clken) begin
	      // This adds a dead cycle between each transaction for
	      // no really good reason; fix that later.
	      if (~mem.valid & dmem.valid) begin
		 mem.a    <= dmem.a;
		 mem_is_dbus <= 1'b1;
		 mem.valid   <= 1'b1;
		 mem_wrq     <= dmem.wrq;
		 mem_wdata   <= dmem.wdata;
		 mem_wbe     <= dmem.wbe;
	      end else if (~mem.valid & imem.valid) begin
		 mem.a    <= imem.a;
		 mem_is_dbus <= 1'b0;
		 mem.valid   <= 1'b1;
		 mem_wrq     <= 1'b0;
		 mem_wdata   <= 32'bx;
		 mem_wbe     <= 4'bx;
	      end else if (mem.valid & mem.ready) begin
		 mem.a    <= 'bx;
		 mem_is_dbus <= 1'bx;
		 mem.valid   <= 1'b0;
		 mem_wrq     <= 1'bx;
		 mem_wbe     <= 4'bx;
	      end
	   end
      end
   endgenerate

   reg io_pending;

   assign io.valid = io_pending & ~io.ready;

   // I/O bus
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	io_ready_q    <= 1'b0;
	io.a          <= 'bx;
	io_wdata	 <= 'bx;
	io_pending	 <= 1'b0;
	io_wrq		 <= 1'b0;
	io_wbe		 <= 'b0;
     end else if (clken) begin
	io_ready_q    <= 1'b0;

	if (~io_pending & dbus_io_sel) begin
	   io.a       <= dbus.a;
	   io_wdata      <= dbus.wdata;
	   io_pending    <= ~dbus_is_cbo; // No CBO to I/O space
	   io_wrq        <= dbus.wrq;
	   io_wbe	 <= dbus.wbe;
	   io_ready_q <= dbus_is_cbo;  // Ack CBO immediately
	end else if (io_pending & io.ready) begin
	   io_ready_q <= 1'b1;
	   io_rdata_q <= io.rdata;
	   io_pending	 <= 1'b0;
	   io_wrq	 <= 1'b0;
	   io_wbe	 <= 'b0;
	end
     end

   reg dbus_io_sel_q;
   reg dbus_mem_sel_q;
   reg dbus_tcm_sel_q;
   reg dbus_err_sel_q;

   reg ibus_mem_sel_q;
   reg ibus_tcm_sel_q;
   reg ibus_err_sel_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	dbus_io_sel_q  <= 1'bx;
	dbus_mem_sel_q <= 1'bx;
	dbus_tcm_sel_q <= 1'bx;
	dbus_err_sel_q <= 1'bx;

	ibus_mem_sel_q <= 1'bx;
	ibus_tcm_sel_q <= 1'bx;
	ibus_err_sel_q <= 1'bx;
     end else if (clken) begin
	dbus_io_sel_q  <= dbus_io_sel;
	dbus_mem_sel_q <= dbus_mem_sel;
	dbus_tcm_sel_q <= dbus_tcm_sel;
	dbus_err_sel_q <= dbus_err_sel;

	ibus_mem_sel_q <= ibus_mem_sel;
	ibus_tcm_sel_q <= ibus_tcm_sel;
	ibus_err_sel_q <= ibus_err_sel;
     end

   always @(*)
     begin
	unique case ({dbus_io_sel_q, dbus_mem_sel_q, dbus_tcm_sel_q})
	  3'b000:  dbus.rdata = INVALID_DATA;
	  3'b001:  dbus.rdata = dbus_tcm.rdata;
	  3'b010:  dbus.rdata = dbus_mem.rdata;
	  3'b100:  dbus.rdata = io_rdata_q;
	  default: dbus.rdata = 32'bx;
	endcase

	unique case ({dbus_io_sel_q, dbus_mem_sel_q, dbus_tcm_sel_q})
	  3'b000:  dbus.ready = dbus_err_sel_q;
	  3'b001:  dbus.ready = dbus_tcm.ready;
	  3'b010:  dbus.ready = dbus_mem.ready;
	  3'b100:  dbus.ready = io_ready_q;
	  default: dbus.ready = 1'bx;
	endcase

	unique case ({ibus_mem_sel_q, ibus_tcm_sel_q})
	  2'b00:   ibus.rdata = INVALID_DATA;
	  2'b01:   ibus.rdata = ibus_tcm.rdata;
	  2'b10:   ibus.rdata = ibus_mem.rdata;
	  default: ibus.rdata = 32'bx;
	endcase

	unique case ({ibus_mem_sel_q, ibus_tcm_sel_q})
	  2'b00:   ibus.ready = ibus_err_sel_q;
	  2'b01:   ibus.ready = ibus_tcm.ready;
	  2'b10:   ibus.ready = ibus_mem.ready;
	  default: ibus.ready = 1'bx;
	endcase
     end

   assign dbus.busy = dbus_mem.busy | io_pending;

   // Fetch unit (F stage)
   wire	       f_restart;
   wire [31:0] f_restartpc;
   mcontext_t  f_restart_mcontext;
   retstack_t  f_restart_retstack;
   wire	       f_stall;
   wire [31:0] d_insn;
   mcontext_t  d_mcontext;
   wire	       d_insn_16;
   wire	       d_valid_i;
   wire	[31:0] d_insn_pc;
   retstack_t  d_retstack;
   wire	       f_valid_o;
   d_pred_t    d_pred;
   regnum_t    f_rs1;
   regnum_t    f_rs2;

   fetch #(`CFG) fetch (
     .clk		(clk),
     .clken		(clken),
     .rst_n		(rst_n),

     .restart		(f_restart),
     .restart_pc	(f_restartpc),
     .restart_mcontext  (f_restart_mcontext),
     .restart_retstack  (f_restart_retstack),
     .ibus		(ibus),

     .f_stall		(f_stall),

     .f_valid_o         (f_valid_o),
     .f_rs1             (f_rs1),
     .f_rs2             (f_rs2),

     .d_valid_i		(d_valid_i),
     .d_insn		(d_insn),
     .d_pc		(d_insn_pc),
     .d_mcontext        (d_mcontext),
     .d_insn_16		(d_insn_16),
     .d_retstack        (d_retstack),

     .d_pred            (d_pred)
     );

   // Decode unit (D stage)
   decoded_insn_t d_op;
   wire	       d_stall;
   wire	       d_killed;
   wire	       d_valid_o;
   wire	       d_busy;

   decode #(`CFG) decode (
     .rst_n		(rst_n),
     .clk		(clk),
     .clken		(clken),

     .d_din		(d_insn),
     .d_insn_16		(d_insn_16),
     .d_pc		(d_insn_pc),
     .d_mcontext	(d_mcontext),
     .d_valid_i		(d_valid_i),
     .d_stall		(d_stall),
     .d_killed		(d_killed),
     .d_valid_o		(d_valid_o),
     .d_busy		(d_busy),
     .d_op		(d_op),
     .d_retstack        (d_retstack),

     .d_pred            (d_pred)
     );

   // Interrupt latching
   reg [NUM_IRQS:0] d_irqs;	// Pending IRQs
   reg [NUM_IRQS:0] d_irq_q;	// irq input delayed (for edge detect)
   reg [NUM_IRQS:0] d_irq_edge;	// edge detected interrupt latched

   wire [NUM_IRQS:0] d_irqs_clear;

   wire [NUM_IRQS:0] irq_mask = { {NUM_IRQS{1'b1}}, 1'b0 };

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	d_irqs     <= 'b0;
	d_irq_q    <= 'b0;
	d_irq_edge <= 'b0;
     end else if (clken) begin
	// Edge-trigger logic
	d_irq_q    <= irq_edge & irq_mask & irq;
	d_irq_edge <= irq_edge & irq_mask &
		      ((d_irq_edge & ~d_irqs_clear) | (irq & ~d_irq_q));
	d_irqs     <= ((~irq_edge & irq) | d_irq_edge) & irq_mask;
     end

   // Backend units (E, M, and W stages)
   decoded_insn_t e_op;
   wire	       e_valid_i;
   wire	       e_stall;
   wire	       e_valid_o;
   wire	       e_busy;
   wire	       d_rs1_e;
   wire	       d_rs1_m;
   wire	       d_rs1_w;
   wire	       d_rs2_e;
   wire	       d_rs2_m;
   wire	       d_rs2_w;

   decoded_insn_t m_op;
   wire	       m_valid_i;
   wire	       m_stall;
   wire	       m_valid_o;
   wire	       m_busy;

   wire	       m_kill;
   wire	[31:0] m_restartpc;
   mcontext_t  m_restart_mcontext;
   retstack_t  m_restart_retstack;

   wire [31:0] e_dout;
   wire [31:0] m_din;

   rng_bus_t   rng;
   assign rng = { rng_data, rng_stb, rng_incr, rng_bist, rng_dead };

   backend #(`CFG) backend (
     .rst_n		(rst_n),
     .clk		(clk),
     .clken		(clken),

     .f_valid_o		(f_valid_o),
     .f_rs1		(f_rs1),
     .f_rs2		(f_rs2),

     .d_op		(d_op),

     .d_irqs		(d_irqs),
     .d_irqs_clear      (d_irqs_clear),
     .irq_intable	(irq_intable  & irq_mask),
     .irq_waitable	(irq_waitable & irq_mask),
     .e_intack		(irq_intack),

     .e_valid_i		(e_valid_i),
     .e_stall		(e_stall),
     .e_valid_o		(e_valid_o),
     .e_op		(e_op),
     .e_busy		(e_busy),
     .d_rs1_e		(d_rs1_e),
     .d_rs1_m		(d_rs1_m),
     .d_rs1_w		(d_rs1_w),
     .d_rs2_e		(d_rs2_e),
     .d_rs2_m		(d_rs2_m),
     .d_rs2_w		(d_rs2_w),

     .d_valid_o		(d_valid_o),
     .dcache_lookup_a	(dcache_lookup_a),
     .dcache_lookup_valid (dcache_lookup_valid),
     .dcache_lookup_hold (dcache_lookup_hold),
     .dcache_lookup_cbo (dcache_lookup_cbo),
     .dcache_lookup_wrq (dcache_lookup_wrq),

     .m_valid_i		(m_valid_i),
     .m_stall		(m_stall),
     .m_op		(m_op),
     .m_valid_o		(m_valid_o),
     .m_busy		(m_busy),

     .e_dout		(e_dout),
     .m_din		(m_din),

     .m_kill		(m_kill),
     .m_restartpc	(m_restartpc),
     .m_restart_mcontext (m_restart_mcontext),
     .m_restart_retstack (m_restart_retstack),

     .ctr_time          (ctr_time),
     .ctr_cycle		(ctr_cycle),
     .ctr_instret	(ctr_instret),

     .rng		(rng),
     .rng_full		(rng_full),

     .dbus		(dbus)
     );

   assign f_restartpc        = m_restartpc;
   assign f_restart_mcontext = m_restart_mcontext;
   assign f_restart_retstack = m_restart_retstack;
   assign d_killed           = m_kill;

   //
   // Pipeline control
   //
   pipe_ctl #(`CFG) pipe_ctl (
     .rst_n	(rst_n),
     .clk	(clk),
     .clken	(clken),

     .d_valid_i	(d_valid_i),
     .d_valid_o	(d_valid_o),
     .d_advance		(d_advance),
     .e_valid_o	(e_valid_o),
     .m_valid_o	(m_valid_o),

     .e_valid_i	(e_valid_i),
     .m_valid_i	(m_valid_i),

     .d_op	(d_op),
     .e_op	(e_op),
     .m_op	(m_op),

     .d_busy	(d_busy),
     .e_busy	(e_busy),
     .m_busy	(m_busy),

     .m_kill	(m_kill),
     .f_restart	(f_restart),

     .f_stall	(f_stall),
     .d_stall	(d_stall),
     .e_stall	(e_stall),
     .m_stall   (m_stall),

     .d_rs1_e	(d_rs1_e),
     .d_rs1_m	(d_rs1_m),
     .d_rs1_w	(d_rs1_w),
     .d_rs2_e	(d_rs2_e),
     .d_rs2_m	(d_rs2_m),
     .d_rs2_w	(d_rs2_w)
     );
   // Time counter. If CTR_TIME_WIDTH is 0, ctr_time is an input
   // which can be connected to an external counter or set to 0;
   // otherwise it is an output.
   generate
      if (CTR_TIME_WIDTH) begin
	 counter #(.o_bits(64), .c_bits(CTR_TIME_WIDTH))
	 timectr (.clk(clk), .ctr(ctr_time));
      end
   endgenerate

   // Other counters. All counters are read only, even when using the m-
   // CSR numbers.
   generate
      if (CTR_CYCLE_WIDTH) begin
	 counter #(.o_bits(64), .c_bits(CTR_CYCLE_WIDTH))
         cyclectr (.rst_n (rst_n), .clk(clk), .clken(clken), .ctr(ctr_cycle));
      end else begin
	 assign ctr_cycle = ctr_time;
      end
   endgenerate

   counter #(.o_bits(64), .c_bits(CTR_INSTRET_WIDTH))
   instretctr (.rst_n (rst_n), .clk(clk), .clken(clken),
	       .count(m_valid_o & ~m_stall), .ctr(ctr_instret));


endmodule
