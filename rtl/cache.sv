//
// Cache and memory bus implementation (shared code/data)
// using dual-ported FPGA memory.
//
// The total size and cache sizes are powers of 2; the balance is TCM.
//
// The TCM address space includes the cache proper; possibly useful for
// cache-as-ram operation.
//
// The basic operations supported are load (L), store (S), and
// prefetch/command (P).
//
// Additionally, the following flags (which can be derived from either
// opcode bits or address bits) are supported:
//
//	U	= uncached
//	W	= writeback
//	I	= invalidate
//
// See cacheops.odt for a detailed description.
//
// Only port 0 (dbus) supports writes, prefetches, and I/O bus access,
// and control flags.
//

module cache #(
	       parameter	size_bits = 15, // Total size
	       parameter	cache_bits = 13, // Non-TCM size
	       parameter	addr_bits = 25, // RAM address size
	       parameter	way_bits = 1, // Only one supported right now
	       parameter	line_bits = 2, // Only one supported right now
	       parameter	ports = 2, // Number of ports

	       // Address space decoding
	       // If these address spaces overlap, TCM takes precendence;
	       // note that that includes the geographical cacheop range.
	       parameter [31:0]	tcm_base = 32'h0000_0000,
	       parameter [31:0]	tcm_mask = 32'hc000_0000,
	       parameter [31:0]	ram_base = 32'h4000_0000,
	       parameter [31:0]	ram_mask = 32'hc000_0000
	       )
   (
    input			    rst_n,
    input			    clk,

    input  [31:0]		    cpu_a     [0:ports-1],
    output [31:0]		    cpu_rdata [0:ports-1],
    input  [0:ports-1]		    cpu_rrq,
    output [0:ports-1]		    cpu_ready,

    // Only applicable to port 0
    input [31:0]		    cpu_wdata,
    input			    cpu_wrq,
    input			    cpu_prefrq,
    input [3:0]			    cpu_wbe,
    input [2:0]			    cpu_cachectl,	// UWI

    output [31:0]		    io_a,
    output [31:0]		    io_wdata,
    input [31:0]		    io_rdata,
    output			    io_rrq,
    output			    io_wrq,
    output [3:0]		    io_wbe,
    input			    io_ready,

    output [addr_bits-1:0]	    ram_a,
    output [(1 << line_bits)-1:0]   ram_wdata,
    input [(1 << line_bits)-1:0]    ram_rdata,
    output			    ram_rrq,
    output			    ram_wrq,
    output [(1 << line_bits/8)-1:0] ram_wbe,
    input			    ram_ready
    );

   // TCM exists?
   localparam logic have_tcm = size_bits > ram_bits;

   // Total number of row bits including TCM
   localparam	  xrow_bits = size_bits - line_bits - way_bits;

   // Number of row bits used for the cache proper
   localparam	  crow_bits  = xrow_bits - tcm_bits;
   localparam	  ctag_bits  = addr_bits - crow_bits - line_bits;

   // Total number of ways
   localparam	  ways = 1 << way_bits;

   // Port identifier
   localparam	  port_bits = $clog2(ports);

   // Byte enables
   localparam	  line_be = 1 << line_bits/8;

   // Address decoding
   logic [ports-1:0]	  is_io;
   logic [ports-1:0]	  is_ram;
   logic [ports-1:0]	  is_tcm;

   logic [way_bits-1:0]	  way_addr [0:ports-1];
   logic [ctag_bits-1:0]  tag_addr [0:ports-1];
   logic [crow_bits-1:0]  crow_addr[0:ports-1];
   logic [xrow_bits-1:0]  xrow_addr = [0:ports-1];

   always_comb
     for (int i = 0; i < ports; i++)
       begin
	  is_tcm[i]      = have_tcm && ((cpu_a[i] & tcm_mask) == tcm_base);
	  is_ram[i]	 = ~is_tcm[i] && ((cpu_a[i] & ram_mask) == ram_base);
	  is_io[i]       = ~is_tcm[i] & ~is_ram[i];

	  way_addr[i]    = cpu_a[i][way_bits+row_bits+line_bits-1:row_bits+line_bits];
	  tag_addr[i]    = cpu_a[i][addr_bits-1:ctag_bits];
	  crow_addr[i]   = cpu_a[i][crow_bits+line_bits-1:line_bits];
	  xrow_addr[i]   = cpu_a[i][xrow_bits+line_bits-1:line_bits]
			   | {tcm_bits{~is_tcm[i]}};
       end

   typedef struct {
      logic [ctag_bits-1:0] tag,
      logic valid,
      logic dirty
   } tag_t;

   tag_t				tag_ram[0:(1 << crow_bits)-1][0:ways-1];
   reg [ways-1:0]			valid_ram[0:(1 << crow_bits)-1];
   reg [ways-1:0][line_bits-1:0]	array_ram[0:(1 << xrow_bits)-1];

   tag_t				tag_out   [0:ports-1][0:ways-1];
   logic [ways-1:0][line_bits-1:0]	array_out [0:ports-1];

   tag_t				tag_in    [0:ports-1];
   logic [way_bits-1:0]			tag_wway  [0:ports-1];
   logic				tag_wrq   [0:ports-1];
   logic [ways-1:0][line_bits-1:0]	array_in  [0:ports-1];
   logic [line_bytes-1:0]		array_wrq [0:ports-1];

   // Memories. One memory port per CPU port.
   always @(posedge clk)
     for (int i = 0; i < ports; i++)
       begin
	  for (int j = 0; j < ways; j++)
	    begin
	       tag_out[i][j] <= tag_ram[crow_addr[i]][j];
	       if (tag_wrq[i] && tag_wway[i] == j)
		 tag_ram[crow_addr[i]][j] <= tag_in[i];
	    end

	  array_out[i] <= array_ram[xrow_addr[i]];
	  for (int j = 0; j < line_bytes; j++)
	    if (array_wrq[i][j])
	      array_ram[xrow_addr[i]][j*8+7:j*8] <= array_in[j*8+7:j*8];
       end // for (int i = 0; i < ports; i++)


   //
   // I/O bus output
   //
   assign io_rrq   = is_io[0] & cpu_rrq[0];
   assign io_a     = cpu_a[0];
   assign io_wrq   = cpu_wrq;
   assign io_wbe   = cpu_wbe;

   //
   // Victim candidate, per port
   //

   // Simple PRNG for victim row selection
   reg [5:0]	      prng;
   logic	      prng_advance;
   always @(posedge clk)
     if (prng_advance)
       prng <= (prng << 1) | prng[5] | prng[4];

   // These are zero for all but port 0, makes things a little easier
   wire [ports-1:0] is_wrq    = cpu_wrq;
   wire [ports-1:0] is_prefrq = cpu_prefrq;
   wire [ports-1:0] u_flag    = cpu_cachectl[2];
   wire [ports-1:0] i_flag    = cpu_cachectl[1];
   wire [ports-1:0] w_flag    = cpu_cachectl[0];

   //
   // Tag match
   //
   logic		match [0:ports-1]; // Tag found
   logic		dirty [0:ports-1]; // Tag dirty
   logic [way_bits-1:0]	way   [0:ports-1]; // Tag selected

   always_comb
     for (int i = 0; i < ports; i++)
       begin
	  // If the way is derived from the address (TCM or geographical)
	  logic [way_bits-1:0] addr_way =
		  cpu_a[i][way_bits+line_bits-1:line_bits];

	  if (~is_ram[i] | (is_prefrq[i] & u_flag[i]))
	    begin
	       match[i] = 1'b1;
	       way[i]   = addr_way;
	    end
	  else
	    begin
	       match[i] = 1'b0;
	       way[i]   = prng[way_bits-1:0];

	       for (int j = 0; j < ways; i++)
		 begin
		    if (tag_out[i][j].valid &&
			tag_out[i][j].tag == tag_addr[i])
		      begin
			 way[i]   = j;
			 match[i] = 1'b1;
			 break;
		      end
		    else if (!tag_out[i][j].valid)
		      way[i] = j; // Prefer an invalid way as a victim
		 end // for (int j = 0; j < ways; i++)
	    end // else: !if(~is_ram[i] | (is_prefrq[i] & u_flag[i]))

	  dirty[i] = is_ram[i] & tag_out[i][way[i]].dirty;
       end

   //
   // CPU data output
   //
   reg		    uc_op_ready;

   always_comb
     begin
	for (int i = 0; i < ports; i++)
	  begin
	     cpu_rdata[i] = array_out[i][way[i]];
	     cpu_ready[i] = match[i];
	  end
	if (is_io[0])
	  begin
	     cpu_rdata[0] = io_rdata;
	     cpu_ready[0] = io_ready;
	  end
	else if (u_flag[0])
	  begin
	     cpu_rdata[0] = ram_rdata;
	     cpu_ready[0] = uc_op_ready;
	  end
     end

   //
   // DRAM interface state machine
   //
   typedef enum {
	ds_ready,
	ds_rrq
   } dstate_t;
   dstate_t dstate;

   assign prng_advance = dstate == ds_ready;

   // Port being serviced
   reg [port_bits-1:0] port_serviced;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  dstate        <= ds_ready;
	  ram_rrq       <= 1'b0;
	  ram_wrq       <= 1'b0;
	  ram_wbe       <= 'b0;
	  ram_a         <= 'bx;
	  ram_wdata     <= 'bx;
	  port_serviced <= 'bx;
	  uc_op_ready   <= 1'b0;

	  for (int i = 0; i < ports; i++)
	    begin
	       array_in[i]     = 'bx;
	       array_wrq[i]    = 'b0;
	       tag_in[i].tag   = 'bx;
	       tag_in[i].dirty = 1'bx;
	       tag_in[i].valid = 1'bx;
	       tag_wrq[i]      = 'b0;
	    end
       end
     else
       begin
	  // Defaults
	  ram_valid   <= ram_valid & ~ram_ready;
	  array_in[0]  = cpu_wdata;
	  array_wrq[0] = cpu_wbe & {line_bytes{cpu_valid[0] & cpu_wrq}};
	  for (int i = 1; i < ports; i++)
	    begin
	       array_in[i]  = ram_rdata;
	       array_wrq[i] = 'b0;
	    end

	  for (int i = 0; i < ports; i++)
	    begin
	       tag_in[i].tag   = match[i] ? tag_out[i].tag : tag_addr[i];
	       tag_in[i].valid = tag_out[i].valid;
	       tag_in[i].dirty = tag_out[i].dirty;
	       tag_wway[i]     = way[i];
	       tag_wrq[i]      = 1'b0;
	    end

	  if (is_ram[0] & cpu_wrq & ~u_flag[0])
	    if (match[0] || (~dirty[0] & (&array_wbe)))
	      begin
		 // Store to cache
		 tag_in[0].valid = 1'b1;
		 tag_in[0].dirty = 1'b1;
		 tag_wrq[0]      = 1'b1;
		 array_in[0]     = cpu_wdata;
		 array_wrq[0]    = cpu_wbe;
	      end

	  case ( dstate )
	    ds_ready: begin
	       for (int i = 0; i < ports; i++)
		 begin
		    uc_op_ready <= 1'b0;
		    if (ram_ready)
		      begin
			 ram_rrq <= 1'b0;
			 ram_wrq <= 1'b0;
		      end

		    if (~ram_rrq & ~ram_wrq & cpu_valid[i] & ~is_io[i])
		      begin
			 if (!match[i] | u_flag[i] | i_flag[i] |
			     (w_flag[i] & (dirty[i] | is_wrq[i])))
			   begin
			      port_serviced  <= i;
			      ram_a          <= cpu_a[i][addr_bits-1:0];
			      if (dirty[i] &
				  (w_flag[i] | (~i_flag[i] & ~u_flag[i])))
				begin
				   // Write out cache line
				   ram_a[addr_bits-1:crow_bits+line_bits]
				     <= tag_out[i].tag;
				   ram_wrq <= 1'b1;
				   ram_wbe <= {line_be{1'b1}};
				   ram_wdata <= array_out[i];
				   dstate <= ds_ready;
				   tag_in[i].valid = ~i_flag[i];
				   tag_in[i].dirty = 1'b0;
				   tag_wrq[i] = 1'b1;
				end
			      else if (u_flag[i])
				begin
				   // Uncached operation
				   if (is_prefrq[i])
				     begin
					// Done
					uc_op_ready <= 1'b1;
				     end
				   else
				     begin
					ram_wrq <= is_wrq[i];
					ram_rrq <= cpu_rrq[i];
					ram_wbe <= is_wrq[i] ? cpu_wrq : 'b0;
					ram_wdata <= cpu_wdata;
					dstate  <= ds_uc;
				     end
				begin
				   // Read in cache line unless invalidate
				   ram_wrq <= 1'b0;
				   ram_wbe <= {line_be{1'b0}};
				   ram_rrq <= i_flag[i];
				   tag_in[i].tag
				     = cpu_a[i][addr_bits-1:crow_bits+line_bits];
				   tag_in[i].valid = 1'b0;
				       cpu_ready[i] = is_prefrq[i];

				end // else: !if(dirty[i] & ~inval_only)
			      tag_wrq[i] = 1'b1;
			   end

			      t
			      tag_in[i].valid <= match[i] & ~inval_only;
			      ram_a[addr_bits-1:addr_bits-crow_bits]
				<= crow_addr[i];
			      ram_a[addr_bits-crow_bits-1:ctag_bits]
	[		      if (dirty[i])
				begin
				     <= tag_out[i].tag;
			      ram_a[
			      ram_valid      <= 1'b1;
			      ram_wrq        <= is_wrq[i] | dirty[i];
			      ram_wbe        <= is_wrq[i] | dirty[i]4'b1111;
				    raw_wdata <=
			      dstate        a<= is_wrq[i] ? ds_ready  : ds_rrq;
			      tag_in[i].valid = match[i] & ~cpu_a[i][inval_bit];
			      tag_in[i].dirty = 1'b0;
			      tag_wrq[i]      = 1'b1;
			      break;
			   end // if (!match[i] || (cpu_a[i][flush_bit] && dirty[i]))
			 else if (cpu_a[i][inval_bit])
			   begin
			      // Invalidate this cache line
			      tag_in[i].valid = 1'b0;
			      tag_in[i].dirty = 1'b0;
			      tag_wrq[i]      = 1'b1;
			   end
		      end
		 end
	    end // case: cs_ready

	    ds_rrq: begin
	       ram_valid <= ~ram_ready;
	       array_in[port_serviced]     = ram_rdata;
	       tag_in[port_serviced].valid = 1'b1;
	       tag_in[port_serviced].dirty = 1'b0;
	       if (ram_ready)
		 begin
		    array_wrq[port_serviced]    = 4'b1111;
		    tag_wrq[port_serviced]      = 1'b1;
		    dstate <= ds_ready;
		 end
	    end // case: ds_rrq


ds_uc:
	  endcase // case ( dstate )

endmodule // cache
