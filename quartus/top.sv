// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// Top level for benchmarking with Quartus
//

`include "../rtl/params.vh"

module pll (
	    input  rst_n_i,
	    input  clk_i,
	    output rst_n_o,
	    output clk_o
	    );

   altpll #(.inclk0_input_frequency(62500),	// Period in ps (16 MHz)
	    .operation_mode ("NORMAL"),
	    .clk0_divide_by ( 4 ),
	    .clk0_duty_cycle ( 50 ),		// 50%
	    .clk0_multiply_by ( 21 ),
	    .clk0_phase_shift( "0" )
   ) pll (
	    .areset (~rst_n_i),
	    .inclk  (clk_i),
	    .clk    (clk_o),
	    .locked (rst_n_o),
	    .clkbad (),
	    .clkena (1'b1),
	    .clkloss ()
   );
endmodule

module benchmark #(`CONFIG)
(
	    input	  rst_n,
	    input	  clk,
	    output [30:2] io_addr,
	    output [31:0] io_wdata,
	    output	  io_valid,
	    output	  io_wrq,
	    output [3:0]  io_wbe,
	    input	  io_ready,
	    input [31:0]  io_rdata,
	    input [NUM_IRQS:1]  irq_in,
	    output [$clog2(NUM_IRQS+1)-1:0]  irq_intack,

	    output [ram_size_bits-1:0] mem_addr,
	    output [31:0] mem_wdata,
	    output	  mem_valid,
	    output	  mem_wrq,
	    output [3:0]  mem_wbe,
	    input	  mem_ready,
	    input [31:0]  mem_rdata,
	    input	  mem_cpu,
	    input	  mem_wr,
	    input [ram_size_bits-1:0]  mem_addr_i
	    );

   wire		   prst_n;
   wire		   pclk;

   // Run the clock through a PLL to clean it up
   pll pll (.rst_n_i(rst_n), .clk_i(clk), .rst_n_o(prst_n), .clk_o(pclk));

   // Register irq inputs
   reg [NUM_IRQS:1]   irq;

   always @(negedge prst_n or posedge pclk)
     if (~prst_n)
       irq <= 'b0;
     else
       irq <= irq_in;

   bus_if #(.writeable(1'b1)) io();
   bus_if #(.address_bits(ram_size_bits), .writeable(1'b1),
	    .snoop(1'b1), .dma(1'b1)) mem();

   assign io_addr = io.a[30:2];
   assign io_wdata = io.wdata;
   assign io_valid = io.valid;
   assign io_wrq = io.wrq;
   assign io_wbe = io.wbe;
   assign io.ready = io_ready;
   assign io.rdata = io_rdata;

   assign mem_addr = mem.a;
   assign mem_wdata = mem.wdata;
   assign mem_valid = mem.valid;
   assign mem_wrq = mem.wrq;
   assign mem_wbe = mem.wbe;
   assign mem.ready = mem_ready;
   assign mem.rdata = mem_rdata;
   assign mem.cpu = mem_cpu;
   assign mem.inval = mem_wr;
   assign mem.a_in = mem_addr_i;

   myriscv #(`CFG) cpu (
	     .rst_n		(prst_n),
	     .clk		(pclk),
	     .clken		(1'b1),
	     .ctr_time		( ),
	     .ctr_cycle		( ),
	     .ctr_instret	( ),
	     .io		(io),
	     .mem		(mem),

     .irq		({irq, 1'b0}),
     .irq_intable	({{31{1'b1}}, 1'b0}),
     .irq_waitable	({{31{1'b1}}, 1'b0}),
     .irq_edge		(32'b0),
     .irq_intack	(irq_intack),
     .buserr		( )
     );
endmodule
