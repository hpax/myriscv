// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// External memory simulator model
//

module extmem
  #(parameter ram_bits,
   parameter  size_bits = ram_bits)
(
  input			    rst_n,
  input			    clk,

  bus_if.memory_target	    mem
  );

   logic [ram_bits-1:0]	    transaction_a;
   logic		    write_strobe;
   assign mem.a_in = transaction_a;
   assign mem.inval = write_strobe;

   localparam		    size = 1 << (size_bits-2);

   reg [3:0][7:0]	data_mem[0:size-1];
   reg [31:0]		mem_wdata_q;
   reg [3:0]		mem_wbe_q;

   reg			busy;
   reg [2:0]		wait_ctr; // Simulate dram delay

   wire [ram_bits-1:2]	mword = transaction_a[ram_bits-1:2];

   reg			mem_valid_q;
   assign mem.ready = mem_valid_q & ~busy;

   // In case x causes logic errors
   parameter logic [31:0] deadbeef = 32'hdeadbeef;

   initial begin : init_mem
      string init_file;

      for (int i = 0; i < (1 << ram_bits); i++)
	data_mem[i] = deadbeef;

      if ($value$plusargs("mem_init=%s", init_file))
	$readmemh(init_file, data_mem);
   end

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	busy	  <= 1'b0;
	wait_ctr  <= 2'b0;
	transaction_a   <= 'bx;
	write_strobe  <= 1'b0;
	mem_wbe_q   <= 4'bx;
	mem_wdata_q <= 32'bx;
	mem_valid_q <= 1'b0;
     end else begin
	mem_valid_q <= mem.valid;
	write_strobe <= 1'b0;	// This should be a single cycle strobe

	wait_ctr    <= wait_ctr + busy;
	if (busy) begin
	   if (|wait_ctr) begin
	      if (mem_wbe_q[0]) data_mem[mword][0] <= mem_wdata_q[7:0];
	      if (mem_wbe_q[1]) data_mem[mword][1] <= mem_wdata_q[15:8];
	      if (mem_wbe_q[2]) data_mem[mword][2] <= mem_wdata_q[23:16];
	      if (mem_wbe_q[3]) data_mem[mword][3] <= mem_wdata_q[31:24];

	      write_strobe	<= |mem_wbe_q;
	      mem.rdata <= data_mem[mword];
	      busy	<= 1'b0;
	   end
	end else begin
	   transaction_a     <= 'bx;
	   mem_wbe_q   <= 4'bx;
	   mem_wdata_q <= 32'bx;
	   write_strobe    <= 1'b0;

	   if (mem.valid & ~mem.ready) begin
	      busy		<= 1'b1;
	      transaction_a		<= mem.a;
	      transaction_a[1:0]      <= 2'b00;
	      mem_wbe_q		<= mem.wrq ? mem.wbe : 4'b0;
	      mem_wdata_q	<= mem.wdata;
	   end
	end
     end
endmodule
