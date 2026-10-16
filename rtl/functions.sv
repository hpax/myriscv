// Compute a mask of all bits that can be set to 1 for the values
// (base, base + 2^bits], even if base is not aligned

package myriscv_functions;

function automatic logic [31:0] addr_mask(input [31:0] base, input int bits);
   logic [31:0] mask;
   logic [31:0]	bmask;

   bmask = (1'b1 << bits)-1'b1;
   mask = base;
   if (base & bmask)		// Not aligned
     mask    |= base + bmask + 1'b1;
   mask      |= bmask;

   addr_mask = mask;
endfunction

endpackage
