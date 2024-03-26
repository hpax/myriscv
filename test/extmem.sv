//
// External memory simulator model
//

module extmem
  #(parameter ram_bits,
   parameter  size_bits = ram_bits)
(
  input			    rst_n,
  input			    clk,

  input [ram_bits-1:0]	    mem_a,
  input			    mem_valid,
  input			    mem_wrq,
  input [3:0]		    mem_wbe,
  input [31:0]		    mem_wdata,

  output reg		    mem_ready,
  output reg [31:0]	    mem_rdata,

  // Follows the hardware memory interface; useful for invalidation or
  // to have the memory address *immediately* associated with _ready
  // (only valid for one cycle, though!)
  output reg [ram_bits-1:0] mem_a_o,
  output reg		    mem_wr_o	// strobe on ANY memory write
  );

   localparam		    size = 1 << (size_bits-2);

   reg [3:0][7:0]	mem[0:size-1];
   reg [31:0]		mem_wdata_q;
   reg [3:0]		mem_wbe_q;

   reg			busy;
   reg [2:0]		wait_ctr; // Simulate dram delay

   wire [ram_bits-1:2]	mword = mem_a_o[ram_bits-1:2];

   reg			mem_valid_q;
   assign mem_ready = mem_valid_q & ~busy;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	busy	  <= 1'b0;
	wait_ctr  <= 2'b0;
	mem_a_o   <= 'bx;
	mem_wr_o  <= 1'b0;
	mem_wbe_q   <= 4'bx;
	mem_wdata_q <= 32'bx;
	mem_valid_q <= 1'b0;
     end else begin
	mem_valid_q <= mem_valid;
	mem_wr_o <= 1'b0;	// This should be a single cycle strobe

	wait_ctr    <= wait_ctr + busy;
	if (busy) begin
	   if (|wait_ctr) begin
	      if (mem_wbe_q[0]) mem[mword][0] <= mem_wdata_q[7:0];
	      if (mem_wbe_q[1]) mem[mword][1] <= mem_wdata_q[15:8];
	      if (mem_wbe_q[2]) mem[mword][2] <= mem_wdata_q[23:16];
	      if (mem_wbe_q[3]) mem[mword][3] <= mem_wdata_q[31:24];

	      mem_wr_o	<= |mem_wbe_q;
	      mem_rdata <= mem[mword];
	      busy	<= 1'b0;
	   end
	end else begin
	   mem_a_o     <= 'bx;
	   mem_wbe_q   <= 4'bx;
	   mem_wdata_q <= 32'bx;
	   mem_wr_o    <= 1'b0;

	   if (mem_valid & ~mem_ready) begin
	      busy		<= 1'b1;
	      mem_a_o		<= mem_a;
	      mem_a_o[1:0]      <= 2'b00;
	      mem_wbe_q		<= mem_wrq ? mem_wbe : 4'b0;
	      mem_wdata_q	<= mem_wdata;
	   end
	end
     end
endmodule
