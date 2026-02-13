//
// dcache.sv
//
// Simple direct-mapped data cache
//
// A dedicated address bit is used for "geographical
// addressing"/cache-as-RAM (CAR), accessing each cache line directly
// without the tag.
//
// Geographical addressing has the following properties:
// 1. Reads are always satisfied by the cache;
// 2. Writes invalidates the cache line unconditionally; any dirty data
//    is lost.
// 3. CBO commands (inval, clean, flush) operate on the relevant
//    cache line, with the address taken from the tag in question.
//
module dcache #(
   parameter	 cache_bits	= 13, // Non-TCM size in 2^bytes
   parameter	 addr_bits	= 25, // RAM address size
   parameter	 car_bit	= addr_bits,
   parameter	 way_bits	= 1,  // Only one supported right now
   parameter	 linewidth_bits = 2,  // Only one supported right now

   // Don't modify these
   parameter int tag_bits	= addr_bits - cache_bits,
   parameter int line_bits	= cache_bits - linewidth_bits,
   parameter int lines		= 1 << line_bits,
   parameter int linebytes	= 1 << linewidth_bits,
   parameter int linewidth      = 8 << linewidth_bits
)
   (
    input		       rst_n,
    input		       clk,

    input [31:0]	       dbus_a,
    input [31:0]	       dbus_wdata,
    input [3:0]		       dbus_be, // Used for both reads and writes!
    output [31:0]	       dbus_rdata,
    input	       cbo_t   dbus_cbo,
    input		       dbus_rrq,
    input		       dbus_wrq,
    output		       dbus_ready,
    input		       dbus_fence,
    output		       dbus_ready,

    output reg [addr_bits-1:0] ram_a,
    output reg [linewidth-1:0] ram_wdata,
    output reg		       ram_rrq,
    output reg		       ram_wrq,
    output reg [linebytes-1:0] ram_wbe,
    input [linewidth-1:0]      ram_rdata,
    input		       ram_ready
);

   localparm int tag_bits	  = addr_bits - cache_bits;
   localparm int line_bits	  = cache_bits - linewidth_bits;
   localparm int lines		  = 1 << line_bits;
   localparm int linebytes	  = 1 << linewidth_bits;

   wire car_addr		  = dbus_a[car_bit];
   wire [line_bits-1:0]	line_addr = dbus_a[cache_bits-1:linewidth_bits];
   wire [tag_bits-1:0]	tag_addr  = dbus_a[addr_bits-1:cache_bits];

   reg [linebytes-1:0][7:0] data_ram[0:lines-1];
   reg [tag_bits-1:0]	    tag_ram[0:lines-1];

   // From the memory access state machine
   logic		    ram_rdack;
   logic		    ram_wrack;

   // Data RAM array
   logic [linebytes-1:0][7:0] data_ram_q;
   always @(posedge clk)
     begin
	for (int b = 0; b < linewidth; b += 8)
	  if (dbus_wrq & dbus_be[b >> 3])
	    data_ram[line_addr][b+7:b] <= dbus_wdata[b+7:b];

	if (ram_rdack)
	  data_ram[line_addr] <= ram_rdata;

	if (dbus_rrq | dbus_wrq)
	  data_ram_q <= data_ram[line_addr];
       end

   assign dbus_rdata = data_ram_q;

   // Tag RAM array
    logic [tag_bits-1:0] tag_ram_q;
   always @(posedge clk)
     if (dbus_rrq | dbus_wrq)
       begin
	  tag_ram[line_addr] <= tag_addr;
	  tag_ram_q	     <= tag_ram[line_addr];
       end
     end

   reg [tag_bits-1:0] tag_addr_q;
   always @(posedge clk)
     tag_addr_q <= tag_addr;

   wire tag_match = tag_ram_q == tag_addr_q;

   // Eviction/busy logic (one cycle after CPU request)
   wire [line_bytes-1:0] vram_dirty;
   wire	[line_bytes-1:0] vram_valid;
   logic vram_evict;
   logic need_write;
   logic need_read;
   reg   pend_write;
   reg   pend_read;
   reg   in_write;
   reg   in_read;
   reg	 memory_busy;
   logic [line_width-1:0] mem_wdata;
   reg			  rrq_q;
   reg	 wrq_q;
   reg	 wb_q;
   reg	 invd_q;
   reg [linebytes-1:0] be_q;
   reg	 car_addr_q;
   reg	 fence_q;
   always @(negedge rst_n or posedge clk)
     begin
	rrq_q	   <= 1'b0;
	wrq_q	   <= 1'b0;
	invd_q	   <= 1'b0;
	wb_q	   <= 1'b0;
	be_q	   <= {linebytes{1'b0}};
	car_addr_q <= 1'b0;
	fence_q    <= 1'b0;
     end
     begin
	rrq_q	   <= dbus_rrq;
	wrq_q	   <= dbus_wrq;
	invd_q     <= dbus_cbo.invd;
	wb_q       <= dbus_cbo.wb;
	be_q	   <= dbus_be;
	car_addr_q <= car_addr;
     end

   always_comb
     begin
	vram_evict = (rrq_q & ~car_addr_q & ~tag_match) |
		     (wrq_q & (car_addr_q | ~tag_match)) |
		     (invd_q & (tag_match | car_addr_q));
	need_read  = rrq_q & ~car_addr_q &
		     ~(tag_match & (&(vram_valid | ~be_q) | ram_rdack));
	need_write = (|vram_dirty) &
		     (((wrq_q | rrq_q) & ~car_addr_q & ~tag_match) |
		      (wb_q & (tag_match | car_addr_q)));
	dbus_ready = ~need_read &
		    ~(need_write & pend_write) &
		    ~(fence_q & (pend_write | in_write));
     end

   // Validity RAM array
   cache_validram #(.line_bits(line_bits), .line_bytes(line_bytes))
   vram ( .clk(clk), .line_addr(line_addr),
      .valid(vram_valid), .dirty(vram_dirty),
      .evict(vram_evict), .rdack(ram_rdack), .wrack(ram_wrack),
      .dbus_be(dbus_be), .dbus_wrq(dbus_wrq) );

   // Memory bus state machine

   always_comb
     begin
	assign ram_rdack = in_read  & ram_ready;
	assign ram_wrack = in_write & ram_ready;
	assign ram_rrq   = pend_read;
	assign ram_wrq   = pend_write;
     end

   reg	ram_ready_q;

   always @(negedge rst_n or posedge clk)
     if (~rst_n)
       begin
	  ram_ready_q <= 1'b0;
	  pend_read   <= 1'b0;
	  pend_write  <= 1'b0;
	  in_read     <= 1'b0;
	  in_write    <= 1'b0;
	  ram_a       <= 'bx;
	  ram_wdata   <= 'bx;
	  ram_wbe     <= 'bx;
       end
     else
       begin
	  ram_ready_q <= ram_ready;

	  if (ram_ready)
	    begin
	       in_read	<= 1'b0;
	       in_write <= 1'b0;
	    end
	  else if (ram_ready_q)
	    begin
	       // First cycle with ram_ready low, this is an acknowledge
	       in_write   <= pend_write;
	       pend_write <= 1'b0;
	       in_read	  <= pend_read;
	       pend_read  <= 1'b0;
	       ram_a	  <= 'bx;
	       ram_wdata  <= 'bx;
	       ram_wbe    <= 'bx;
	    end

	  // Writes take priority over reads, to ensure no stale data
	  if (need_write)
	    if (~pend_write)
	      begin
		 pend_write			    <= 1'b1;
		 pend_read			    <= 1'b0;
		 ram_a[addr_bits-1:cache_bits]	    <= tag_ram_q;
		 ram_a[cache_bits-1:linewidth_bits] <= line_addr_q;
		 ram_a[linewidth_bits-1:0]          <= 'b0;
		 ram_wdata			    <= data_ram_q;
		 ram_wbe			    <= vram_valid.dirty;
	      end
	  else if (need_read)
	    if (~in_read & ~pend_write)
	      begin
		 pend_read			    <= 1'b1;
		 ram_a[addr_bits-1:cache_bits]	    <= tag_addr_q;
		 ram_a[cache_bits-1:linewidth_bits] <= line_addr_q;
		 ram_a[linewidth_bits-1:0]          <= 'b0;
	      end
       end
endmodule

// Valid RAM array
module cache_validram #(
   parameter int line_bits,
   parameter int line_bytes
   )
(
   input		   clk,
   input [line_bits-1:0]   line_addr,
   input [line_bytes-1:0]  dbus_be,
   input		   dbus_wrq,
   input		   evict,
   input		   write,
   input		   rdack,
   input                   wrack,

   output [line_bytes-1:0] valid,
   output [line_bytes-1:0] dirty
);

   typedef struct {
      reg valid;			// All bytes in line are valid
      reg [linebytes-1:0] dirty;	// Dirty bytes
   } valid_ram_t;

   valid_ram_t ram_valid[0:(1 << line_bits)-1];
   valid_ram_t oldval;
   valid_ram_t newval;
   valid_ram_t outval;

   assign dirty = outval.dirty;
   assign valid = {line_bytes{outval.valid}} | outval.dirty;

   reg [line_bits-1:0] line_addr_q;
   always @(posedge clk)
     line_addr_q <= line_addr;

   // Actual RAM array
   always @(posedge clk)
     begin
	oldval <= ram_valid[line_bits];
	ram_valid[line_addr_q] <= newval;
     end

   // New state computation
   reg [linebytes-1:0] wbe_q;
   always @(posedge clk)
     wbe_q <= {linebytes{dbus_wrq}} & dbus_be;

   always_comb
     begin
	for (int b = 0; b < line_bytes; b++)
	  newval.dirty[b] = ~wrack & (wbe_q[b] | (~evict & oldval.dirty[b]));
	newval.valid	  = rdack | (~evict & oldval_valid);
     end

   // Bypass logic
   always_comb
      outval = (line_addr == line_addr_q) ? newval : oldval;
endmodule
