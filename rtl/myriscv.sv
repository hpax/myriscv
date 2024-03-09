module core (rst_n, clk, clken,
  io_addr, io_wdata, io_valid, io_wrq, io_wbe, io_ready,io_rdata,
  irq, intack
    );
   parameter    bit WITH_Zba		= 1'b1;
   parameter    bit WITH_Zcf		= 1'b1;
   parameter    bit WITH_Zcb		= 1'b1;
   parameter    bit WITH_Zcd		= 1'b1;
   parameter    bit WITH_Zbb		= 1'b1;
   parameter    bit WITH_Zmmul		= 1'b1;
   parameter    bit WITH_Zicond		= 1'b1;
   parameter    bit WITH_minmax		= 1'b1;
   parameter    bit WITH_extensions	= 1'b1;
   parameter    bit STRICT_UNDEFINED	= 1'b0;

   parameter    bit TRAP_BADINSN	= 1'b1;
   parameter    bit TRAP_BADALU		= 1'b1;

   parameter    logic [31:0] PC_MASK	= 32'h41ff_fffe;
   parameter    logic [31:0] RESET_PC	= 32'h0000_0010;

   parameter    int	     NUM_IRQS	= 31;
   parameter    int	     IRQ_BITS	= $clog2(NUM_IRQS+1);
   parameter    logic [31:0] MTVEC_RESET	= 32'h0000_0080;
   parameter    logic [31:0] MTVEC_WMASK	= 32'h0;

   parameter    int	     CTR_TIME_WIDTH	= 40;
   parameter    int	     CTR_CYCLE_WIDTH	= 40;
   parameter    int	     CTR_INSTRET_WIDTH	= 40;

   parameter bit	     ALU_EARLY_DECODE = 1'b0;

   parameter    logic [31:0] tcm_base		= 32'h0000_0000;
   parameter    logic [31:0] tcm_mask		= 32'h3fff_ffff;
   parameter    logic [31:0] ram_base		= 32'h4000_0000;
   parameter    logic [31:0] ram_mask		= 32'h3fff_ffff;
   parameter	logic [31:0] io_base		= 32'h8000_0000;

   input		     rst_n;
   input		     clk;
   input		     clken;

   output reg [31:0]	     io_addr;
   output reg [31:0]	     io_wdata;
   output reg		     io_valid;
   output reg		     io_wrq;
   output reg [3:0]	     io_wbe;
   input		     io_ready;
   input [31:0]		     io_rdata;

   input [NUM_IRQS:1]	     irq;
   output [IRQ_BITS-1:0]     intack;

   wire [31:0]		     ibus_a;
   wire			     ibus_valid;
   wire [31:0]		     ibus_rdata;
   wire			     ibus_ready;

   wire [31:0]		     dbus_a;
   wire [31:0]		     dbus_wdata;
   wire			     dbus_valid;
   wire			     dbus_wrq;
   wire [3:0]		     dbus_wbe;
   wire [31:0]		     dbus_rdata;
   wire [31:0]		     dbus_rdata_tcm;
   reg [31:0]		     dbus_rdata_io;
   wire			     dbus_ready;
   wire			     dbus_ready_tcm;
   reg			     dbus_ready_io;

   tcm tcm (
     .rst_n		(rst_n),
     .clk		(clk),
     .ibus_a		(ibus_a),
     .ibus_valid	(ibus_valid),
     .ibus_rdata	(ibus_rdata),
     .ibus_ready	(ibus_ready),

     .dbus_a		(dbus_a),
     .dbus_valid	(dbus_valid),
     .dbus_wrq		(dbus_wrq & (dbus_a < io_base)),
     .dbus_wbe		(dbus_wbe),
     .dbus_rdata	(dbus_rdata_tcm),
     .dbus_ready	(dbus_ready_tcm)
     );

   reg			     dbus_valid_q;

   // I/O bus
   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	dbus_valid_q <= 1'b0;

	io_addr      <= 'bx;
	io_wdata     <= 'bx;
	io_valid     <= 1'b0;
	io_wrq	     <= 1'b0;
	io_wbe	     <= 'b0;
     end else if (clken) begin
	if (~io_valid & dbus_valid & (dbus_a >= io_base)) begin
	   dbus_ready_io <= 1'b0;
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
	end else begin
	   dbus_ready_io <= 1'b0;
	end
     end

   assign dbus_ready = dbus_ready_io | dbus_ready_tcm;

   // Fetch unit (F stage)
   wire f_restart;
   wire [31:0] f_restart_pc;
   wire	       f_stall;
   wire [31:0] d_insn;
   wire	       d_valid_i;
   wire	       d_insn_pred_taken;
   wire	[31:0] d_insn_pc;

   fetch fetch (
     .clk		(clk),
     .clken		(clken),
     .rst_n		(rst_n),

     .restart		(f_restart),
     .restart_pc	(f_restart_pc),
     .ibus_a		(ibus_a),
     .ibus_rdata	(ibus_rdata),
     .ibus_valid	(ibus_valid),
     .ibus_ready	(ibus_ready),

     .stall		(f_stall),
     .insn		(d_insn),
     .valid_o		(d_valid_i),
     .insn_pred_taken	(d_insn_pred_taken),
     .insn_pc		(d_insn_pc)
     );

   // Decode unit (D stage)
   decoded_insn_t d_op;
   wire	       d_stall;
   wire	       d_killed;
   wire	       d_valid_o;
   wire	       d_busy;

   decode decode (
     .rst_n	(rst_n),
     .clk	(clk),
     .clken	(clken),

     .d_din	(d_insn),
     .d_was_16	(1'b0),
     .d_pred_taken	(d_insn_pred_taken),
     .d_pc	(d_insn_pc),
     .d_valid_i	(d_valid_i),
     .d_stall	(d_stall),
     .d_killed	(d_killed),
     .d_valid_o	(d_valid_o),
     .d_busy	(d_busy),
     .d_op	(d_op)
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

   wire	       m_valid_i;
   wire	       m_stall;
   wire	       m_valid_o;
   wire	       m_busy;

   wire [31:0] e_dout;
   wire [31:0] m_din;

   backend
     #(.NUM_IRQS ( NUM_IRQS ),
       .IRQ_BITS ( IRQ_BITS ),
     .ALU_EARLY_DECODE ( ALU_EARLY_DECODE )
       ) backend (
     .rst_n     (rst_n),
     .clk	(clk),
     .clken	(clken),

     .d_op	(d_op),

     .d_irqs	(d_irqs),
     .e_intack	(intack),

     .e_valid_i	(e_valid_i),
     .e_stall	(e_stall),
     .e_valid_o	(e_valid_o),
     .e_kill	(e_kill),
     .e_restartpc	(e_restartpc),
     .e_busy	(e_busy),
     .e_rs1_m	(e_rs1_m),
     .e_rs1_w	(e_rs1_w),
     .e_rs2_m	(e_rs2_m),
     .e_rs2_w	(e_rs2_w),

     .m_valid_i	(m_valid_i),
     .m_stall	(m_stall),
     .m_valid_o	(m_valid_o),
     .m_busy	(m_busy),

     .e_dout	(e_dout),
     .m_din	(m_din)
     );
endmodule
