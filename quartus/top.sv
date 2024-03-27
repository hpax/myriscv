//
// Top level for benchmarking with Quartus
//

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

module benchmark (
	    input	  rst_n,
	    input	  clk,
	    output [30:2] io_addr,
	    output [31:0] io_wdata,
	    output	  io_valid,
	    output	  io_wrq,
	    output [3:0]  io_wbe,
	    input	  io_ready,
	    input [31:0]  io_rdata,
	    input [31:1]  irq_in,
	    output [4:0]  intack,

	    output [25:0] mem_addr,
	    output [31:0] mem_wdata,
	    output	  mem_valid,
	    output	  mem_wrq,
	    output [3:0]  mem_wbe,
	    input	  mem_ready,
	    input [31:0]  mem_rdata,
	    input	  mem_cpu,
	    input	  mem_wr,
	    input [25:0]  mem_addr_i
	    );

   wire		   prst_n;
   wire		   pclk;

   // Run the clock through a PLL to clean it up
   pll pll (.rst_n_i(rst_n), .clk_i(clk), .rst_n_o(prst_n), .clk_o(pclk));

   // Register irq inputs
   reg [31:1]	   irq;

   always @(negedge prst_n or posedge pclk)
     if (~prst_n)
       irq <= 31'b0;
     else
       irq <= irq_in;

   wire [31:0]	   cpu_io_addr;
   assign io_addr = cpu_io_addr[30:2];
   
   core cpu (
	     .rst_n		(prst_n),
	     .clk		(pclk),
	     .clken		(1'b1),
	     .ctr_time		( ),
	     .ctr_cycle		( ),
	     .ctr_instret	( ),
	     .io_addr		(cpu_io_addr),
	     .io_wdata		(io_wdata),
	     .io_valid		(io_valid),
	     .io_wrq		(io_wrq),
	     .io_wbe		(io_wbe),
	     .io_ready		(io_ready),
	     .io_rdata		(io_rdata),
     .mem_addr (mem_addr),
     .mem_wdata (mem_wdata),
     .mem_valid (mem_valid),
     .mem_wrq (mem_wrq),
     .mem_wbe (mem_wbe),
     .mem_ready (mem_ready),
     .mem_rdata (mem_rdata),
     .mem_wr (mem_wr),
     .mem_cpu (mem_cpu),
     .mem_addr_i (mem_addr_i),

	     .irq		(irq),
	     .irq_enable	(31'b1),
	     .irq_edge		(31'b0),
	     .intack		(intack),
	     .buserr		( )
	     );
endmodule
   
