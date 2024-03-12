//
// Generic parameterizable counter.
// Zero counter width (output always zero) is explicitly supported.
// If c_bits < o_bits then the high bits are either sign- or zero-extended.
//

module counter #(
		 parameter int		o_bits   = 64,	   // Bus width
		 parameter int		c_bits   = o_bits, // Counter width
		 parameter bit		sext     = 1'b0,   // Sign extend
		 parameter [o_bits-1:0]	resetval = 'b0
		 )
   (
    input tri1		    rst_n,	// Asynchronous reset
    input		    clk,
    input tri1		    clken,	// Enable for count and clear
    input tri1		    count,	// Count enable
    input tri0		    clear,	// Synchronous clear/load
    input tri0 [o_bits-1:0] clearval,	// Value on clear
    
    output [o_bits-1:0]	    ctr		// Counter output
    );

   generate
      if (c_bits) begin
	 reg [c_bits-1:0] ctr_q = resetval[c_bits-1:0];

	 always @(negedge rst_n or posedge clk)
	   if (~rst_n)
	     ctr_q <= resetval[c_bits-1:0];
	   else if (clken) begin
	     if (clear)
	       ctr_q <= clearval[c_bits-1:0];
	     else if (count)
	       ctr_q <= ctr_q + 1'b1;
	   end
      end
   endgenerate

   generate
      if (!c_bits)
	assign ctr = 'b0;
      else if (sext)
	 assign ctr = $signed(ctr_q);
      else
	 assign ctr = ctr_q;
   endgenerate
endmodule // ctr
