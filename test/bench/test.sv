// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// Very simple test bench
//

`timescale 1 ps / 1 ps

module test #(
   parameter int NUM_IRQS = 31,
   parameter bit TRACE_PC = 1'b0
   );

   localparam int IRQ_BITS = $clog2(NUM_IRQS+1);
   localparam int ram_size_bits = 25;

   logic	rst_n;
   logic	clk;
   logic	clken;

   bus_if #(.writeable(1'b1)) io();
   bus_if #(.address_bits(ram_size_bits), .writeable(1'b1),
	    .snoop(1'b1)) mem();

   logic [NUM_IRQS:1]	irq;
   logic [NUM_IRQS:1]	irq_edge;
   wire [IRQ_BITS-1:0]	intack;
   logic [15:0] irq_pend_timer [1:NUM_IRQS];
   logic [15:0]	irq_clr_timer  [1:NUM_IRQS];


   wire			buserr;

   //
   // Initialization
   //
   initial begin
      irq      = 'b0;
      irq_edge = 'b0;
      for (int i = 1; i < NUM_IRQS; i++) begin
	 irq_pend_timer[i] = 'b0;
	 irq_clr_timer[i]  = 'b0;
      end
   end

   //
   // Clock and reset
   //
   assign clken = 1'b1;
   localparam int	CLOCK = 1000;

   initial
     begin
	clk       <= 1'b1;
	rst_n	  <= 1'b0;
	repeat (10) @(negedge clk);
	rst_n <= 1'b1;
     end

   always #(CLOCK >> 1) clk <= ~clk;

   //
   // CPU core with TCM
   //
   myriscv #(
     .NUM_IRQS		(NUM_IRQS),
     .ram_size_bits	(ram_size_bits),
     .WITH_mscratch     (1'b1),		// For CSR ISA testing
     .CLOCK             (CLOCK),	// clock scaling factor for $displays
     .TRACE_PC          (TRACE_PC)	// Enable/disable tracing for this run
   ) cpu (
     .rst_n	( rst_n ),
     .clk	( clk ),
     .clken	( clken ),

     .io	( io ),
     .mem	( mem ),

     .irq	   ( { irq, 1'b0 } ),
     .irq_edge     ( { irq_edge, 1'b0 } ),
     .irq_intack   ( intack ),
     .irq_intable  ( {{NUM_IRQS{1'b1}}, 1'b0} ),
     .irq_waitable ( {{NUM_IRQS{1'b1}}, 1'b0} ),

     .buserr	( buserr )
     );

   // External memory

   extmem #(.ram_bits( ram_size_bits ), .size_bits ( ram_size_bits ))
   extmem (
     .rst_n	( rst_n ),
     .clk	( clk ),
     .mem	( mem )
     );

   // I/O
   reg        io_sleeping  = 1'b0;
   reg [7:0]  io_sleep_ctr = 'b0;
   wire [7:0] io_req_sleep = ~io.a[29] ? io.a[7:0] : 8'b0;
   wire [31:0] busaddr	   = { io.a[31:2], 2'b00 };

   wire [31:0] rdata       = io.a;
   string      conout	   = "";

   always @(posedge clk)
     begin
	io.ready <= 1'b0;
	io.rdata <= rdata;

	if (io.valid) begin
	   if (~io_sleeping && |io_req_sleep) begin
	      io_sleep_ctr <= io_req_sleep - 1'b1;
	      io_sleeping  <= 1'b1;
	   end else if (io_sleep_ctr) begin
	      io_sleep_ctr <= io_sleep_ctr - 1'b1;
	   end else begin
	      logic [3:0][7:0] data;
	      logic [3:0][7:0] dstr;
	      logic [7:0]      chr;
	      logic	       putc;
	      logic	       quit;

	      io.ready	  <= 1'b1;
	      io_sleeping <= 1'b0;

	      putc	   = 1'b0;
	      quit	   = 1'b0;

	      data	   = io.wrq ? io.wdata : io.rdata;
	      for (int i = 0; i < 4; i++) begin
		 dstr[i] = data[3-i];
		 if (dstr[i] < 8'h20 || dstr[i] > 8'h7e)
		   dstr[i] = 8'h2e; // Non-ASCII character; print as .
	      end

	      if (io.wrq && |io.wbe && busaddr[31:16] == 16'hffff) begin
		 priority casez ({busaddr[15:0], io.wbe})
		   20'b1111_1111_1111_11??_1???: begin
		      // Byte address -1 is console output; it prints bytes
		      // directly to the console without ASCIIfying the output,
		      // and so can print newline, tab, unicode, etc.
		      chr	= io.wdata[31:24];
		      putc = 1'b1;
		   end
		   20'b1111_1111_1111_1000_1111: begin
		      // Address -8 is test termination; should be a 4-byte
		      // write with a status string:
		      // "PASS" - test passed
		      // "FAIL" - test failed
		      // "STOP" - test is not self-checking, no error detected
		      // "TRAP" - test failed with an unexpected trap
		      quit = 1'b1;
		   end
		   20'b1111_1110_????_????_????: begin
		      // Byte address -512 + char:
		      // Hack to print a single fixed character using only the
		      // bus address, allowing it to be executed without clobbering
		      // any registers at all.
		      chr[7:2] = busaddr[7:2];
		      chr[1]   = |io.wbe[3:2];
		      chr[0]   = io.wbe[3] | io.wbe[1];
		      putc     = 1'b1;
		   end
		   20'b1111_1100_0000_0000_????: begin
		      // Byte address -1024
		      // Bitmask of IRQs that are edge triggered
		      // (sticky asserted, cleared on intack)
		      if (io.wbe[0]) irq_edge[7:1]   = io.wdata[7:1];
		      if (io.wbe[1]) irq_edge[15:8]  = io.wdata[15:8];
		      if (io.wbe[2]) irq_edge[23:16] = io.wdata[23:16];
		      if (io.wbe[3]) irq_edge[31:24] = io.wdata[31:24];
		   end
		   20'b1111_1100_0???_????_????: begin
		      // Byte address -1024 + (irq << 2):
		      //  [15:0] -> cycles before asserting the interrupt
		      // [31:16] -> cycles before deasserting the interrupt
		      automatic logic [4:0] irq_num = busaddr[7:2];
		      if (irq_num <= NUM_IRQS) begin
			 if (io.wbe[0]) irq_pend_timer[irq_num][7:0]  = io.wdata[7:0];
			 if (io.wbe[1]) irq_pend_timer[irq_num][15:8] = io.wdata[15:8];
			 if (io.wbe[2]) irq_clr_timer[irq_num][7:0]   = io.wdata[23:16];
			 if (io.wbe[3]) irq_clr_timer[irq_num][15:8]  = io.wdata[31:24];
		      end
		   end
		   default: begin
		   end
		 endcase
	      end

	      if (putc) begin
		 if (chr == 8'd10) begin
		    $display("(%d) console: %s", $time/CLOCK, conout);
		    conout = "";
		 end else begin
		    conout = $sformatf("%s%c", conout, chr);
		 end
	      end else begin
		 if (quit) begin
		    if (conout != "") begin
		       $display("(%d) console: %s", $time/CLOCK, conout);
		       conout = "";
		    end
		    $display("(%d) %s: test terminating", $time/CLOCK, dstr);
		    $finish;
		 end else begin
		    $display("(%d) io: %h %s %b %h \"%s\"",
			     $time/CLOCK, io.a, io.wrq ? "w" : "r",
			     io.wbe, data, dstr);
		 end
	      end
	   end

	end

	// IRQ assertion and deassertion
	for (int i = 1; i < NUM_IRQS; i++) begin
	   if (irq_pend_timer[i]) begin
	      automatic logic [15:0] new_timer = irq_pend_timer[i] - 1'b1;
	      irq_pend_timer[i] <= new_timer;
	      if (!new_timer)
		irq[i]		<= 1'b1;
	   end
	   if (irq_clr_timer[i]) begin
	      automatic logic [15:0] new_timer = irq_clr_timer[i] - 1'b1;
	      irq_clr_timer[i]  <= new_timer;
	      if (!new_timer)
		irq[i]		<= 1'b0;
	   end
	end
     end
endmodule
