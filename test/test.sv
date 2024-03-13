//
// Very simple test bench
//

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

   core #(.TCM_INIT_FILE ("/home/hpa/hwhacks/riscv/myriscv/test/test1.hex"))
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
   assign io_ready = io_valid;

   always @(posedge clk)
     begin
	if (io_valid) begin
	   logic [31:0]	    data;
	   logic [3:0][7:0] dstr;

	   data = io_wrq ? io_wdata : io_rdata;
	   dstr = data;
	   for (int i = 0; i < 4; i++) begin
	      if (dstr[i] < 8'h20 || dstr[i] > 8'h7e)
		dstr[i] = 8'h20;
	   end

	   $display("(%u) io: %h %s %b %h \"%s\"",
	     $time/CLOCK, io_addr, io_wrq ? "w" : "r",
	     io_wbe, data, dstr);
	end
     end
endmodule
