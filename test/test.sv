//
// Very simple test bench
//

`timescale 1 ps / 1 ps

module test #(
  parameter int	NUM_IRQS = 31
   );

   localparam int IRQ_BITS = $clog2(NUM_IRQS+1);

   logic	rst_n;
   logic	clk;
   logic	clken;

   wire [31:0]	io_addr;
   wire [31:0]	io_wdata;
   wire		io_valid;
   wire		io_wrq;
   wire [3:0]	io_wbe;
   wire		io_ready;
   wire [31:0]	io_rdata;

   logic [NUM_IRQS:1] irq;
   wire [IRQ_BITS-1:0]	intack;

   wire			buserr;

   assign clken = 1'b1;

   core #(.TCM_INIT_FILE ("/home/hpa/hwhacks/riscv/myriscv/test/test2.hex"))
   cpu (
     .rst_n	( rst_n ),
     .clk	( clk ),
     .clken	( clken ),

     .io_addr	( io_addr ),
     .io_wdata	( io_wdata ),
     .io_valid	( io_valid ),
     .io_wrq	( io_wrq ),
     .io_wbe	( io_wbe ),
     .io_ready	( io_ready ),
     .io_rdata	( io_rdata ),

     .irq	( irq ),
     .intack	( intack ),

     .buserr	( buserr )
     );

   localparam int	CLOCK = 1000;

   initial
     begin
	clk       <= 1'b1;
	rst_n	  <= 1'b0;
	#(16*CLOCK) rst_n <= 1'b1;
     end

   always #(CLOCK >> 1) clk <= ~clk;

   assign irq = 'b0;
   assign io_rdata = io_addr;

   reg io_sleeping = 1'b0;
   reg [7:0] io_sleep_ctr;

   wire [7:0] io_sleep = ~io_addr[30] ? io_addr[7:0] : 8'b0;

   assign io_rdata = io_addr + io_sleep_ctr;
   assign io_ready = io_valid && (!io_sleep || !io_sleep_ctr);

   wire [31:0] busaddr = { io_addr[31:2], 2'b00 };

   bit need_nl = 1'b0;

   always @(posedge clk)
     begin
	io_sleeping <= io_sleeping & ~io_ready;
	io_sleep_ctr <= io_sleep_ctr - io_sleeping;

	if (io_valid & ~io_sleeping) begin
	   logic [3:0][7:0] data;
	   logic [3:0][7:0] dstr;

	   io_sleep_ctr <= io_sleep - 1'b1;
	   io_sleeping  <= |io_sleep;

	   data = io_wrq ? io_wdata : io_rdata;
	   for (int i = 0; i < 4; i++) begin
	      dstr[i] = data[3-i];
	      if (dstr[i] < 8'h20)
		dstr[i] = 8'h20;
	   end

	   if (io_wrq && io_wbe[3] && busaddr == 32'hffff_fffc) begin
	      logic [7:0] chr;
	      chr = io_wdata[31:24];
	      $write("%c", chr);
	      need_nl = chr != 8'd10;
	   end else begin
	      if (need_nl)
		$display("");
	      $display("(%d) io: %h %s %b %h \"%s\"",
		      $time/CLOCK, io_addr, io_wrq ? "w" : "r",
		      io_wbe, data, dstr);
	      need_nl = 1'b0;
	   end

	   if (io_wrq && io_wbe[0] && io_addr == 32'hffff_fff8)
	     $stop;		// Simulation break
	end
     end
endmodule
