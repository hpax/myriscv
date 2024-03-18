//
// Top level for benchmarking with Quartus
//

module pll (
	    input  rst_n_i,
	    input  clk_i,
	    output rst_n_o,
	    output clk_o
	    );

   altpll #(.inclk0_input_frequency(10000), // Period in ps
	    .operation_mode ("NO_COMPENSATION"),
	    .clk0_divide_by ( 1 ),
	    .clk0_duty_cycle ( 1 ),
	    .clk0_multiply_by ( 1 ),
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
	    output [4:0]  intack
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
	     .irq		(irq),
	     .irq_enable	(~32'b1),
	     .irq_edge		(32'b0),
	     .intack		(intack),
	     .buserr		( )
	     );
endmodule
   
