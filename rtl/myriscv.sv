`include "myriscv.vh"

module core (rst_n, clk, clken,
	     ctr_time, ctr_cycle, ctr_instret,
	     io_addr, io_wdata, io_valid, io_wrq, io_wbe, io_ready,io_rdata,
	     irq, intack, buserr
	     );
   parameter    bit WITH_Zba		= 1'b1;
   parameter    bit WITH_Zcf		= 1'b1;
   parameter    bit WITH_Zcb		= 1'b1;
   parameter    bit WITH_Zcd		= 1'b1;
   parameter    bit WITH_Zbb		= 1'b1;
   parameter    bit WITH_bitcnt         = 1'b1;
   parameter    bit WITH_Zmmul		= 1'b1;
   parameter    bit WITH_Zicond		= 1'b1;
   parameter    bit WITH_minmax		= 1'b1;
   parameter    bit WITH_extensions	= 1'b1;
   parameter    bit STRICT_UNDEFINED	= 1'b0;

   parameter    bit TRAP_BADINSN	= 1'b1;
   parameter    bit TRAP_BADALU		= 1'b1;
   parameter    bit TRAP_BADPC		= 1'b0;

   parameter    logic [31:0] PC_MASK	= 32'h41ff_fffe;
   parameter    logic [31:0] RESET_PC	= 32'h0000_0010;

   parameter    int	     NUM_IRQS	= 31;
   parameter    int	     IRQ_BITS	= $clog2(NUM_IRQS+1);
   parameter    logic [31:0] MTVEC_RESET	= 32'h0000_0080;
   parameter    logic [31:0] MTVEC_WMASK	= 32'h0;

   parameter    int	     CTR_TIME_WIDTH	= 40;
   parameter    int	     CTR_CYCLE_WIDTH	=  0;
   parameter    int	     CTR_INSTRET_WIDTH	= 40;

   parameter	bit	     ALU_EARLY_DECODE   = 1'b0;
   parameter	bit	     PREDICT_JALR_ZERO	= 1'b0;

   // This allows a c.nop inserted for padding to be
   // fused with a previous c.xxx instruction into a
   // pseudo-32-bit instruction.
   parameter	bit	     FUSE_CNOP = 1'b0;

   parameter	string	     TCM_INIT_FILE = "";

   //
   // The base addresses and the size bits do not need to agree,
   // however, the address reported to the output bus is always
   // the low bits of the CPU address; so if the base is not a
   // multiple of the size the address window will be shifted.
   //
   // It is required that tcm_base <= ram_base < io_base.
   // Memory references below tcm_base will pulse the buserr output;
   // this can be used to trap NULL pointer references.
   //
   // Note that non-power-of-2 bases or small base values may
   // end up generating slower memory logic, which could
   // negatively affect fMAX.
   //
   parameter    logic [31:0] tcm_base		= 32'h0000_0000;
   parameter    int	     tcm_size_bits	= 14;
   parameter    logic [31:0] ram_base		= 32'h4000_0000;
   parameter    int	     ram_size_bits	= 0;
   parameter	logic [31:0] io_base		= 32'h8000_0000;

   // What reading from a nonexistent memory spaces returns
   parameter    logic [31:0] INVALID_DATA       = 32'h0000_0000;

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

   input [NUM_IRQS:1]	     irq;
   output [IRQ_BITS-1:0]     intack;

   output reg		     buserr;

   wire [31:0]		     ibus_a;
   wire			     ibus_valid;
   logic [31:0]		     ibus_rdata;
   wire [31:0]		     ibus_rdata_tcm;
   wire [31:0]		     ibus_rdata_ram;
   wire			     ibus_ready;
   wire			     ibus_ready_tcm;
   wire			     ibus_ready_ram;

   wire [31:0]		     dbus_a;
   wire [31:0]		     dbus_wdata;
   wire			     dbus_valid;
   wire			     dbus_wrq;
   wire [3:0]		     dbus_wbe;
   logic [31:0]		     dbus_rdata;
   wire [31:0]		     dbus_rdata_tcm;
   wire [31:0]		     dbus_rdata_ram;
   reg  [31:0]		     dbus_rdata_io;
   wire			     dbus_ready;
   wire			     dbus_ready_tcm;
   wire			     dbus_ready_ram;
   reg			     dbus_ready_io;

   logic		     dbus_err_sel;
   logic		     dbus_tcm_sel;
   logic		     dbus_ram_sel;
   logic		     dbus_io_sel;

   logic		     ibus_err_sel;
   logic		     ibus_tcm_sel;
   logic		     ibus_ram_sel;

   //
   // Memory map decode
   //
   always @(*)
     begin
	dbus_err_sel = 1'b0;
	dbus_tcm_sel = 1'b0;
	dbus_ram_sel = 1'b0;
	dbus_io_sel  = 1'b0;
	if (dbus_valid) begin
	   if (dbus_a < tcm_base)
	     dbus_err_sel = 1'b1;
	   else if (dbus_a < ram_base)
	     dbus_tcm_sel = tcm_size_bits > 0;
	   else if (dbus_a < io_base)
	     dbus_ram_sel = ram_size_bits > 0;
	   else
	     dbus_io_sel = 1'b1;
	end

	ibus_err_sel = 1'b0;
	ibus_tcm_sel = 1'b0;
	ibus_ram_sel = 1'b0;
	// Instruction fetches from I/O are not supported

	if (ibus_valid) begin
	   if (ibus_a < tcm_base)
	     ibus_err_sel = 1'b1;
	   else if (ibus_a < ram_base)
	     ibus_tcm_sel = tcm_size_bits > 0;
	   else if (ibus_a < io_base)
	     ibus_ram_sel = ram_size_bits > 0;
	end
     end

   // This is necessary to avoid a combinatorial path
   reg dbus_ready_err;
   reg ibus_ready_err;
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	dbus_ready_err <= 1'b0;
	ibus_ready_err <= 1'b0;
     end else begin
	dbus_ready_err <= dbus_err_sel;
	ibus_ready_err <= ibus_err_sel;
     end

   generate
      if (tcm_size_bits) begin
	 tcm #(
	   .sizebits  (tcm_size_bits),
	   .init_file (TCM_INIT_FILE)
	   ) tcm (
	   .rst_n	(rst_n),
	   .clk		(clk),
	   .clken	(clken),
	   .ibus_a	(ibus_a),
	   .ibus_valid	(ibus_valid),
	   .ibus_rdata	(ibus_rdata_tcm),
	   .ibus_ready	(ibus_ready_tcm),

	   .dbus_a	(dbus_a),
	   .dbus_valid	(dbus_valid),
	   .dbus_wrq	(dbus_wrq & dbus_tcm_sel),
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

   // XXX: implement cache/RAM interface
   assign dbus_rdata_ram = 32'bx;
   assign dbus_ready_ram = 1'b0;
   assign ibus_rdata_ram = 32'bx;
   assign ibus_ready_ram = 1'b0;

   // I/O bus
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	io_addr      <= 'bx;
	io_wdata     <= 'bx;
	io_valid     <= 1'b0;
	io_wrq	     <= 1'b0;
	io_wbe	     <= 'b0;
	buserr       <= 1'b0;
     end else if (clken) begin
	buserr <= dbus_valid & (dbus_a < tcm_base);
	dbus_ready_io <= 1'b0;

	if (~io_valid & dbus_io_sel) begin
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

   assign dbus_ready = dbus_ready_err | dbus_ready_io |
		       dbus_ready_tcm | dbus_ready_ram;
   assign ibus_ready = ibus_ready_err | ibus_ready_tcm | ibus_ready_ram;

   reg dbus_io_sel_q;
   reg dbus_ram_sel_q;
   reg dbus_tcm_sel_q;

   reg ibus_ram_sel_q;
   reg ibus_tcm_sel_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	dbus_io_sel_q  <= 1'bx;
	dbus_ram_sel_q <= 1'bx;
	dbus_tcm_sel_q <= 1'bx;

	ibus_ram_sel_q <= 1'bx;
	ibus_tcm_sel_q <= 1'bx;
     end else if (clken) begin
	dbus_io_sel_q  <= dbus_io_sel;
	dbus_ram_sel_q <= dbus_ram_sel;
	dbus_tcm_sel_q <= dbus_tcm_sel;

	ibus_ram_sel_q <= ibus_ram_sel;
	ibus_tcm_sel_q <= ibus_tcm_sel;
     end

   always @(*)
     begin
	unique case ({dbus_io_sel_q, dbus_ram_sel_q, dbus_tcm_sel_q})
	  3'b000: dbus_rdata  = INVALID_DATA;
	  3'b001: dbus_rdata  = dbus_rdata_tcm;
	  3'b010: dbus_rdata  = dbus_rdata_ram;
	  3'b100: dbus_rdata  = dbus_rdata_io;
	  default: dbus_rdata = 32'bx;
	endcase

	unique case ({ibus_ram_sel_q, ibus_tcm_sel_q})
	  2'b00: ibus_rdata   = INVALID_DATA;
	  2'b01: ibus_rdata   = ibus_rdata_tcm;
	  2'b10: ibus_rdata   = ibus_rdata_ram;
	  default: ibus_rdata = 32'bx;
	endcase
     end


   // Fetch unit (F stage)
   wire f_restart;
   wire [31:0] f_restartpc;
   wire	       f_stall;
   wire [31:0] d_insn;
   wire	       d_insn_16;
   wire	       d_valid_i;
   wire	       d_insn_pred_taken;
   wire	[31:0] d_insn_pc;

   fetch fetch (
     .clk		(clk),
     .clken		(clken),
     .rst_n		(rst_n),

     .restart		(f_restart),
     .restart_pc	(f_restartpc),
     .ibus_a		(ibus_a),
     .ibus_rdata	(ibus_rdata),
     .ibus_valid	(ibus_valid),
     .ibus_ready	(ibus_ready),

     .f_stall		(f_stall),
     .d_valid_i		(d_valid_i),
     .d_insn		(d_insn),
     .d_pred_taken	(d_insn_pred_taken),
     .d_pc		(d_insn_pc),
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
     .d_valid_i		(d_valid_i),
     .d_stall		(d_stall),
     .d_killed		(d_killed),
     .d_valid_o		(d_valid_o),
     .d_busy		(d_busy),
     .d_op		(d_op)
     );

   // Interrupt latching
   reg [NUM_IRQS:1] d_irqs;
   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       d_irqs  <= 'b0;
     else if (clken) begin
	d_irqs <= irq;
     end

   // Backend units (E, M, and W stages)
   decoded_insn_t e_op;
   wire	       e_valid_i;
   wire	       e_stall;
   wire	       e_valid_o;
   wire	       e_kill;
   wire	[31:0] e_restartpc;
   wire	       e_busy;
   wire	       e_rs1_m;
   wire	       e_rs1_w;
   wire	       e_rs2_m;
   wire	       e_rs2_w;

   decoded_insn_t m_op;
   wire	       m_valid_i;
   wire	       m_stall;
   wire	       m_valid_o;
   wire	       m_busy;

   wire [31:0] e_dout;
   wire [31:0] m_din;

   backend
     #(.NUM_IRQS	 ( NUM_IRQS ),
       .IRQ_BITS	 ( IRQ_BITS ),
       .ALU_EARLY_DECODE ( ALU_EARLY_DECODE )
       ) backend (
     .rst_n		(rst_n),
     .clk		(clk),
     .clken		(clken),

     .d_op		(d_op),

     .d_irqs		(d_irqs),
     .e_intack		(intack),

     .e_valid_i		(e_valid_i),
     .e_stall		(e_stall),
     .e_valid_o		(e_valid_o),
     .e_kill		(e_kill),
     .e_op		(e_op),
     .e_restartpc	(e_restartpc),
     .e_busy		(e_busy),
     .e_rs1_m		(e_rs1_m),
     .e_rs1_w		(e_rs1_w),
     .e_rs2_m		(e_rs2_m),
     .e_rs2_w		(e_rs2_w),

     .m_valid_i		(m_valid_i),
     .m_stall		(m_stall),
     .m_op		(m_op),
     .m_valid_o		(m_valid_o),
     .m_busy		(m_busy),

     .e_dout		(e_dout),
     .m_din		(m_din),

     .ctr_time          (ctr_time),
     .ctr_cycle		(ctr_cycle),
     .ctr_instret	(ctr_instret),

     .dbus_a		(dbus_a),
     .dbus_valid	(dbus_valid),
     .dbus_wrq		(dbus_wrq),
     .dbus_wbe		(dbus_wbe),
     .dbus_wdata	(dbus_wdata),
     .dbus_rdata	(dbus_rdata),
     .dbus_ready	(dbus_ready)
     );

   assign f_restartpc = e_restartpc;
   assign d_killed    = e_kill;

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

     .e_kill	(e_kill),
     .f_restart	(f_restart),

     .f_stall	(f_stall),
     .d_stall	(d_stall),
     .e_stall	(e_stall),
     .m_stall   (m_stall),

     .e_rs1_m	(e_rs1_m),
     .e_rs1_w	(e_rs1_w),
     .e_rs2_m	(e_rs2_m),
     .e_rs2_w	(e_rs2_w)
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
