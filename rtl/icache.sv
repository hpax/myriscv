//
// icache.sv
//
// A dedicated address bit is used for "geographical
// addressing"/cache-as-RAM (CAR), accessing each cache line directly
// without the tag.
//
// Accessing the CAR address space will load whatever data sits in the
// cache, regardless of validity, and will never cause an eviction.
//
// This may be useful on FPGAs, where the cache data array can be
// preloaded with boot code.
//
module icache
  #(
   parameter addr_bits = 25, // RAM address size
   parameter car_bit = addr_bits,
   parameter line_bits = 2,  // Only one supported right now
   parameter row_bits = 10   // = 2^12 bytes = 4K
)
   (
   input		     rst_n,
   input		     clk,
   input		     clken,

   input [31:0]		     ibus_a,
   input		     ibus_valid,
   output reg [31:0]	     ibus_rdata,
   output		     ibus_ready,

   //
   // imem_a_i reflects the address on the actual memory bus.
   //
   // If imem_inval is high, this address will be invalidated if
   // present in the icache (tag match). If imem_ready is high, this
   // data is loaded from imem_rdata and the tag is updated.
   //
   // This is intended to allow the icache to be coherent with memory,
   // by invalidating any address written to DRAM, either after
   // flushing from the dcache or via DMA.
   //
   // If imem_inval_geo is high, the invalidation is geographical: the
   // line part of the imem_a_i address represents a line in the
   // cache; the tag bits are architecturally reserved to indicate a
   // cache way if multiple ways are ever implemented. This can be
   // used to invalidate the entire icache by looping over the size
   // of the icache one line at a time. This can be used on hardware
   // where the validity array cannot be statically initialized to be
   // zero on reset, or if the underlying address space has changed in
   // some fundamental way.
   //
   // Important: imem_a_i must equal imem_a when imem_ready is high!
   // This is done by simply having imem_a_i trace the address bus on
   // the actual RAM interface and strobe imem_rdata or imem_inval
   // accordingly. (XXX: Is this actually necessary?)
   //
   input [ram_bits-1:0]	     imem_a_i,
   input		     imem_inval,
   input		     imem_inval_geo,

   output reg [ram_bits-1:0] imem_a,
   output reg		     imem_valid,
   input		     imem_ready,
   input [31:0]		     imem_rdata);

   localparam		  tag_bits = ram_bits - row_bits - line_bits;
   localparam		  rows = 1 << row_bits;
   localparam		  linesize = 8 << line_bits;

   reg [tag_bits-1:0]	  tag_mem  [0:rows-1];
   reg [linesize-1:0]	  data_mem [0:rows-1];
   reg			  valid_mem[0:rows-1];

   wire [row_bits-1:0]	  ibus_row = ibus_a[row_bits+line_bits-1:line_bits];
   wire [tag_bits-1:0]	  ibus_tag = ibus_a[ram_bits-1:ram_bits-tag_bits];
   logic [tag_bits-1:0]	  ibus_tag_cmp;

   wire [row_bits-1:0]	  imem_row = imem_a_i[row_bits+line_bits-1:line_bits];
   wire [tag_bits-1:0]	  imem_tag = imem_a_i[ram_bits-1:ram_bits-tag_bits];
   logic [tag_bits-1:0]	  imem_tag_cmp;

   wire			  have_data = imem_valid & imem_ready;

   // If this is not inherently true then the icache will need to be
   // explicitly flushed through write operations before leaving
   // TCM memory, or anything can happen...
   initial begin
      for (int i = 0; i < rows; i++)
	valid_mem[i] = 1'b0;
   end

   // Tag memory array
   always @(posedge clk) begin
      ibus_tag_cmp <= tag_mem[ibus_row];
      imem_tag_cmp <= tag_mem[imem_row];
      if (have_data)
	tag_mem[imem_row] <= imem_tag;
   end

   // Data memory array
   always @(posedge clk) begin
      ibus_rdata <= data_mem[ibus_row];
      if (have_data)
	data_mem[imem_row] <= imem_rdata;
   end

   reg [tag_bits-1:0] cvalid_tag;
   reg [row_bits-1:0] cvalid_row;
   reg		      imem_inval_q;
   reg		      have_data_q;
   reg		      cvalid_we;
   reg		      cvalid_set;

   logic	      cvalid_ibus;

   always @(posedge clk) begin
      cvalid_tag   <= imem_tag;
      cvalid_row   <= imem_row;
      imem_invt_q  <= imem_inval;	// Invalidate on tag match
      imem_igeo_q  <= imem_inval_geo;	// Invalidate geographically
      have_data_q  <= have_data;
   end

   always @(*) begin
      cvalid_we  = have_data_q | imem_igeo_q |
		   (imem_inval_q & (cvalid_tag == imem_tag_cmp));
      cvalid_set = have_data_q;
   end

   // Validity array
   always @(posedge clk) begin
      cvalid_ibus <= valid_mem[ibus_row];
      if (cvalid_we)
	valid_mem[cvalid_row] <= cvalid_set;
   end

   reg [tag_bits-1:0] ibus_tag_q;
   reg		      ibus_valid_q;

   // CAR addressing always matches
   wire		      ibus_match = ibus_a[car_bit] |
		      (cvalid_ibus & (ibus_tag_q == ibus_tag_cmp));
   assign ibus_ready = ibus_valid_q & ibus_match;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ibus_valid_q <= 1'b0;
	ibus_tag_q   <= 'bx;
	imem_valid   <= 1'b0;
	imem_a	     <= 'bx;
     end else if (clken) begin
	ibus_valid_q <= ibus_valid;
	ibus_tag_q   <= ibus_tag;

	if (imem_valid) begin
	   imem_valid <= ~imem_ready;
	end else if (ibus_valid_q & ~ibus_match) begin
	   imem_valid <= 1'b1;
	   imem_a     <= { ibus_tag, ibus_row, {line_bits{1'b0}} };
	end
     end
endmodule
