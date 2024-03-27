//
// Very simple test bench
//

`timescale 1 ps / 1 ps

module test #(
  parameter int	NUM_IRQS = 31
   );

   localparam int IRQ_BITS = $clog2(NUM_IRQS+1);
   localparam int ram_size_bits = 25;

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

   wire [ram_size_bits-1:0]	mem_addr;
   wire [31:0]	mem_wdata;
   wire		mem_valid;
   wire		mem_wrq;
   wire [3:0]	mem_wbe;
   wire		mem_ready;
   wire [31:0]	mem_rdata;
   wire [ram_size_bits-1:0] mem_addr_i;
   logic		    mem_wr;
   logic		    mem_cpu;

   logic [NUM_IRQS:1] irq;
   wire [IRQ_BITS-1:0]	intack;

   wire			buserr;

   //
   // Clock and reset
   //
   assign clken = 1'b1;
   localparam int	CLOCK = 1000;

   initial
     begin
	clk       <= 1'b1;
	rst_n	  <= 1'b0;
	#(10*CLOCK) rst_n <= 1'b1;
     end

   always #(CLOCK >> 1) clk <= ~clk;

   //
   // CPU core with TCM
   //
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

     .mem_addr	( mem_addr ),
     .mem_wdata	( mem_wdata ),
     .mem_valid	( mem_valid ),
     .mem_wrq	( mem_wrq ),
     .mem_wbe	( mem_wbe ),
     .mem_ready	( mem_ready ),
     .mem_rdata	( mem_rdata ),
     .mem_addr_i ( mem_addr_i ),
     .mem_wr	( mem_wr ),
     .mem_cpu	( mem_cpu ),

     .irq	( irq ),
     .intack	( intack ),

     .buserr	( buserr )
     );

   // External memory

   // No DMA support at the moment...
   assign mem_cpu = 1'b1;

   extmem #(.ram_bits( ram_size_bits ), .size_bits ( 16 ))
   extmem (
     .rst_n	( rst_n ),
     .clk	( clk ),
     .mem_a	( mem_addr ),
     .mem_wdata ( mem_wdata ),
     .mem_valid ( mem_valid ),
     .mem_wrq   ( mem_wrq ),
     .mem_wbe   ( mem_wbe ),
     .mem_ready ( mem_ready ),
     .mem_rdata ( mem_rdata ),
     .mem_a_o   ( mem_addr_i ),
     .mem_wr_o  ( mem_wr )
     );

   // I/O

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
	      if (!need_nl) begin
		 // Print a timestamp prefix at the beginning of the line
		 $write("(%d) ", $time/CLOCK);
	      end
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
