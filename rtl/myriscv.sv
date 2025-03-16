`include "myriscv.vh"

module core #(`CONFIG) (rst_n, clk, clken,
	     ctr_time, ctr_cycle, ctr_instret,
  mem_addr, mem_wdata, mem_valid, mem_wrq, mem_wbe,
  mem_ready, mem_rdata, mem_wr, mem_cpu, mem_addr_i,
  io_addr, io_wdata, io_valid, io_wrq, io_wbe, io_ready,io_rdata,
  irq, irq_edge, irq_intable, irq_waitable, irq_intack, buserr,
  rng_data, rng_stb, rng_incr, rng_bist, rng_dead, rng_full
  );

   input		     rst_n;
   input		     clk;
   input		     clken;

   inout tri0 [63:0]	     ctr_time;
   output [63:0]	     ctr_cycle;
   output [63:0]	     ctr_instret;

   output reg [31:0]	     io_addr;
   output reg [31:0]	     io_wdata;
   output reg		     io_valid;
   output reg		     io_wrq;
   output reg [3:0]	     io_wbe;
   input		     io_ready;
   input [31:0]		     io_rdata;

   output reg [ram_size_bits-1:0]	     mem_addr;
   output reg [31:0]	     mem_wdata;
   output reg		     mem_valid;
   output reg		     mem_wrq;
   output reg [3:0]	     mem_wbe;
   input		     mem_ready;
   input [31:0]		     mem_rdata;

   // These signals are used for cache invalidation and to simplify
   // the cache design. If the memory controller does not support any
   // other agents than the CPU, wire mem_cpu to 1'b1, mem_addr_i to
   // mem_addr, and mem_wr to a one-cycle strobe of mem_valid & mem_wrq.
   input [ram_size_bits-1:0] mem_addr_i; // Address of memory bus transaction
   input		     mem_wr;	 // Write to memory strobe
   input		     mem_cpu;	 // Transaction on behalf of CPU

   // irq is the expected IRQ input.
   //
   // irq_enable is intended to be used to compile-time disable.
   // interrupt vectors, but can also be used to suppress otherwise
   // latched edge-triggered interrupts.
   //
   // irq_edge is set to make an input edge-triggered.
   input tri0 [NUM_IRQS:0]   irq;
   input tri0 [NUM_IRQS:0]   irq_edge;
   input tri1 [NUM_IRQS:0]   irq_intable;
   input tri1 [NUM_IRQS:0]   irq_waitable;

   output [IRQ_BITS-1:0]     irq_intack;

   output reg		     buserr;

   input tri0		     rng_data;
   input tri1		     rng_stb;
   input tri0		     rng_incr;
   input tri1		     rng_bist;
   input tri0		     rng_dead;
   output		     rng_full;

   wire [31:0]		     ibus_a;
   wire			     ibus_valid;
   logic [31:0]		     ibus_rdata;
   wire [31:0]		     ibus_rdata_tcm;
   logic		     ibus_ready;
   logic		     ibus_ready_tcm;
   logic		     ibus_ready_mem;

   wire [31:0]		     dbus_a;
   wire [31:0]		     dbus_wdata;
   wire			     dbus_valid;
   cbo_t		     dbus_cbo;
   wire			     dbus_wrq;
   wire [3:0]		     dbus_wbe;
   logic [31:0]		     dbus_rdata;
   wire [31:0]		     dbus_rdata_tcm;
   reg  [31:0]		     dbus_rdata_io;
   logic		     dbus_ready;
   logic		     dbus_ready_tcm;
   logic		     dbus_ready_mem;
   logic		     dbus_ready_io;

   logic		     dbus_err_sel;
   logic		     dbus_tcm_sel;
   logic		     dbus_mem_sel;
   logic		     dbus_io_sel;

   logic		     ibus_err_sel;
   logic		     ibus_tcm_sel;
   logic		     ibus_mem_sel;

   //
   // Memory map decode
   //
   always @(*)
     begin
	dbus_err_sel = 1'b0;
	dbus_tcm_sel = 1'b0;
	dbus_mem_sel = 1'b0;
	dbus_io_sel  = 1'b0;
	if (dbus_valid) begin
	   if (dbus_a < tcm_base)
	     dbus_err_sel = 1'b1;
	   else if (dbus_a < ram_base)
	     dbus_tcm_sel = tcm_size_bits > 0;
	   else if (dbus_a < io_base)
	     dbus_mem_sel = ram_size_bits > 0;
	   else
	     dbus_io_sel = 1'b1;
	end

	ibus_err_sel = 1'b0;
	ibus_tcm_sel = 1'b0;
	ibus_mem_sel = 1'b0;
	// Instruction fetches from I/O are not supported

	if (ibus_valid) begin
	   if (ibus_a < tcm_base)
	     ibus_err_sel = 1'b1;
	   else if (ibus_a < ram_base)
	     ibus_tcm_sel = tcm_size_bits > 0;
	   else if (ibus_a < io_base)
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
	 // Ignore dbus_cbo, it is safe to simply treat them as reads.
	 tcm #(`CFG) tcm (
	   .rst_n	(rst_n),
	   .clk		(clk),
	   .clken	(clken),
	   .ibus_a	(ibus_a),
	   .ibus_valid	(ibus_tcm_sel),
	   .ibus_rdata	(ibus_rdata_tcm),
	   .ibus_ready	(ibus_ready_tcm),

	   .dbus_a	(dbus_a),
	   .dbus_valid	(dbus_tcm_sel),
	   .dbus_wrq	(dbus_wrq),
	   .dbus_wbe	(dbus_wbe),
	   .dbus_wdata	(dbus_wdata),
	   .dbus_rdata	(dbus_rdata_tcm),
	   .dbus_ready	(dbus_ready_tcm)
	   );
      end else begin
	 assign dbus_rdata_tcm = 32'bx;
	 assign dbus_ready_tcm = 1'b0;
	 assign ibus_rdata_tcm = 32'bx;
	 assign ibus_ready_tcm = 1'b0;
      end
   endgenerate

   // External memory and caches

   wire [31:0] ibus_rdata_mem;

   generate
      if (!ram_size_bits) begin
	 assign ibus_rdata_mem = 32'bx;
	 assign ibus_ready_mem = 1'b0;
	 assign dbus_ready_mem = 1'b0;
      end else begin
	 // Instruction cache

	 wire [ram_size_bits-1:0] imem_a;
	 wire			  imem_valid;
	 logic			  imem_ready;
	 icache #(.ram_bits(ram_size_bits))
	 icache (
	   .rst_n (rst_n),
	   .clk   (clk),
	   .clken (clken),

	   .ibus_a (ibus_a),
	   .ibus_valid (ibus_mem_sel),
	   .ibus_rdata (ibus_rdata_mem),
	   .ibus_ready (ibus_ready_mem),

	   .imem_a     (imem_a),
	   .imem_valid (imem_valid),
	   .imem_ready (imem_ready),
	   .imem_rdata (mem_rdata),

	   .imem_a_i   (mem_addr_i),
	   .imem_inval (mem_wr)
	   );

	 // Memory bus
	 reg			  mem_is_dbus;
	 reg			  dbus_ready_cbo;
	 always @(*) begin
	    dbus_ready_mem = dbus_ready_cbo;
	    imem_ready	   = 1'b0;
	    if (mem_valid & mem_ready) begin
	       dbus_ready_mem =  mem_is_dbus;
	       imem_ready     = ~mem_is_dbus;
	    end
	 end

	 always @(negedge rst_n or posedge clk)
	   if (~rst_n) begin
	      mem_valid      <= 1'b0;
	      mem_wrq        <= 1'bx;
	      mem_wbe	     <= 4'bx;
	      mem_is_dbus    <= 1'bx;
	      mem_addr	     <= 'bx;
	      mem_wdata      <= 32'bx;
	      dbus_ready_cbo <= 1'b0;
	   end else if (clken) begin
	      // The data bus gets priority!

	      dbus_ready_cbo <= 1'b0;

	      if (~mem_valid & dbus_mem_sel & ~dbus_cbo.valid) begin
		 // Note: CBO requests don't go to actual memory; they
		 // will go to the dcache when implemented.
		 mem_addr    <= dbus_a[ram_size_bits-1:0];
		 mem_is_dbus <= 1'b1;
		 mem_valid   <= ~dbus_cbo.valid;
		 dbus_ready_cbo <= dbus_cbo.valid;
		 mem_wrq     <= dbus_wrq;
		 mem_wdata   <= dbus_wdata;
		 mem_wbe     <= dbus_wbe;
	      end else if (~mem_valid & imem_valid) begin
		 mem_addr	<= imem_a;
		 mem_is_dbus	<= 1'b0;
		 mem_valid	<= 1'b1;
		 mem_wrq	<= 1'b0;
		 mem_wdata	<= 32'bx;
		 mem_wbe	<= 4'bx;
	      end else if (mem_valid & mem_ready) begin
		 mem_addr	<= 'bx;
		 mem_is_dbus	<= 1'bx;
		 mem_valid	<= 1'b0;
		 mem_wrq	<= 1'bx;
		 mem_wbe	<= 4'bx;
	      end
	   end
      end
   endgenerate

   // I/O bus
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	io_addr      <= 'bx;
	io_wdata     <= 'bx;
	io_valid     <= 1'b0;
	io_wrq	     <= 1'b0;
	io_wbe	     <= 'b0;
     end else if (clken) begin
	dbus_ready_io <= 1'b0;

	if (~io_valid & dbus_io_sel & ~dbus_cbo.valid) begin
	   io_addr       <= dbus_a;
	   io_wdata      <= dbus_wdata;
	   io_valid      <= 1'b1;
	   io_wrq        <= dbus_wrq;
	   io_wbe	 <= dbus_wbe;
	end else if (io_valid & io_ready) begin
	   dbus_ready_io <= 1'b1;
	   dbus_rdata_io <= io_rdata;
	   io_valid	 <= 1'b0;
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
	  3'b000:  dbus_rdata = INVALID_DATA;
	  3'b001:  dbus_rdata = dbus_rdata_tcm;
	  3'b010:  dbus_rdata = mem_rdata;
	  3'b100:  dbus_rdata = dbus_rdata_io;
	  default: dbus_rdata = 32'bx;
	endcase

	unique case ({dbus_io_sel_q, dbus_mem_sel_q, dbus_tcm_sel_q})
	  3'b000:  dbus_ready = dbus_err_sel_q;
	  3'b001:  dbus_ready = dbus_ready_tcm;
	  3'b010:  dbus_ready = dbus_ready_mem;
	  3'b100:  dbus_ready = dbus_ready_io;
	  default: dbus_ready = 32'bx;
	endcase

	unique case ({ibus_mem_sel_q, ibus_tcm_sel_q})
	  2'b00:   ibus_rdata = INVALID_DATA;
	  2'b01:   ibus_rdata = ibus_rdata_tcm;
	  2'b10:   ibus_rdata = ibus_rdata_mem;
	  default: ibus_rdata = 32'bx;
	endcase

	unique case ({ibus_mem_sel_q, ibus_tcm_sel_q})
	  2'b00:   ibus_ready = ibus_err_sel_q;
	  2'b01:   ibus_ready = ibus_ready_tcm;
	  2'b10:   ibus_ready = ibus_ready_mem;
	  default: ibus_ready = 1'bx;
	endcase
     end

   // Fetch unit (F stage)
   wire	       f_restart;
   wire [31:0] f_restartpc;
   mcontext_t  f_restart_mcontext;
   wire	       f_stall;
   wire [31:0] d_insn;
   mcontext_t  d_mcontext;
   wire	       d_insn_16;
   wire	       d_valid_i;
   wire	       d_insn_pred_taken;
   wire	[31:0] d_insn_pc;
   wire	       f_valid_o;
   regnum_t    f_rs1;
   regnum_t    f_rs2;

   fetch fetch (
     .clk		(clk),
     .clken		(clken),
     .rst_n		(rst_n),

     .restart		(f_restart),
     .restart_pc	(f_restartpc),
     .restart_mcontext  (f_restart_mcontext),
     .ibus_a		(ibus_a),
     .ibus_rdata	(ibus_rdata),
     .ibus_valid	(ibus_valid),
     .ibus_ready	(ibus_ready),

     .f_stall		(f_stall),

     .f_valid_o         (f_valid_o),
     .f_rs1             (f_rs1),
     .f_rs2             (f_rs2),

     .d_valid_i		(d_valid_i),
     .d_insn		(d_insn),
     .d_pred_taken	(d_insn_pred_taken),
     .d_pc		(d_insn_pc),
     .d_mcontext        (d_mcontext),
     .d_insn_16		(d_insn_16)
     );

   // Decode unit (D stage)
   decoded_insn_t d_op;
   wire	       d_stall;
   wire	       d_killed;
   wire	       d_valid_o;
   wire	       d_busy;

   decode decode (
     .rst_n		(rst_n),
     .clk		(clk),
     .clken		(clken),

     .d_din		(d_insn),
     .d_insn_16		(d_insn_16),
     .d_pred_taken	(d_insn_pred_taken),
     .d_pc		(d_insn_pc),
     .d_mcontext	(d_mcontext),
     .d_valid_i		(d_valid_i),
     .d_stall		(d_stall),
     .d_killed		(d_killed),
     .d_valid_o		(d_valid_o),
     .d_busy		(d_busy),
     .d_op		(d_op)
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

   wire [31:0] e_dout;
   wire [31:0] m_din;

   rng_bus_t   rng;
   assign rng = { rng_data, rng_stb, rng_incr, rng_bist, rng_dead };

   backend
     #(.NUM_IRQS	 ( NUM_IRQS ),
       .IRQ_BITS	 ( IRQ_BITS ),
       .ALU_EARLY_DECODE ( ALU_EARLY_DECODE ),
       .EARLY_BYPASS_MUX ( EARLY_BYPASS_MUX )
       ) backend (
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

     .ctr_time          (ctr_time),
     .ctr_cycle		(ctr_cycle),
     .ctr_instret	(ctr_instret),

     .rng		(rng),
     .rng_full		(rng_full),

     .dbus_a		(dbus_a),
     .dbus_valid	(dbus_valid),
     .dbus_cbo		(dbus_cbo),
     .dbus_wrq		(dbus_wrq),
     .dbus_wbe		(dbus_wbe),
     .dbus_wdata	(dbus_wdata),
     .dbus_rdata	(dbus_rdata),
     .dbus_ready	(dbus_ready)
     );

   assign f_restartpc        = m_restartpc;
   assign f_restart_mcontext = m_restart_mcontext;
   assign d_killed           = m_kill;

   //
   // Pipeline control
   //
   pipe_ctl pipe_ctl (
     .rst_n	(rst_n),
     .clk	(clk),
     .clken	(clken),

     .d_valid_i	(d_valid_i),
     .d_valid_o	(d_valid_o),
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
