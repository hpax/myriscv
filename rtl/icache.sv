//
// Instruction cache
//
// A fairly simple direct-mapped cache. The ibus interface is allowed
// to "change its mind" (e.g. due to a pipeline kill) while holding
// ibus_valid high.
//
// A second port is provided to invalidate icache entries when RAM is
// written to elsewhere. This eliminates the need for explicit cache
// operations via the ibus interface.
//
// XXX: make the memory interface burstable to support longer cache lines.
//
module icache
  #(
  parameter ram_bits,
  parameter line_bits = 2,	// Only one supported right now
  parameter row_bits  = 10	// = 2^12 bytes = 4K
	    )
   (
    input		  rst_n,
    input		  clk,
    input		  clken,

    input [31:0]	  ibus_a,
    input		  ibus_valid,
    output reg [31:0]	  ibus_rdata,
    output		  ibus_ready,

    // Important: imem_a_i must equal imem_a when imem_ready is high!
    // This is done by simply having imem_a_i trace the address bus on
    // the actual RAM interface and strobe imem_rdata or imem_inval
    // accordingly.
    input [ram_bits-1:0]  imem_a_i,
    input		  imem_inval,

    output reg [ram_bits-1:0] imem_a,
    output reg		  imem_valid,
    input		  imem_ready,
    input [31:0]	  imem_rdata);

   localparam		  tag_bits = ram_bits - row_bits - line_bits;
   localparam		  rows = 1 << row_bits;
   localparam		  linesize = 8 << line_bits;

   reg   [tag_bits-1:0]	  tag_mem  [0:rows-1];
   reg   [linesize-1:0]	  data_mem [0:rows-1];
   reg			  valid_mem[0:rows-1];

   wire  [row_bits-1:0]	  ibus_row = ibus_a[row_bits+line_bits-1:line_bits];
   wire  [tag_bits-1:0]	  ibus_tag = ibus_a[ram_bits-1:ram_bits-tag_bits];
   logic [tag_bits-1:0]	  ibus_tag_cmp;

   wire  [row_bits-1:0]	  imem_row = imem_a_i[row_bits+line_bits-1:line_bits];
   wire  [tag_bits-1:0]	  imem_tag = imem_a_i[ram_bits-1:ram_bits-tag_bits];
   logic [tag_bits-1:0]	  imem_tag_cmp;

   wire			  have_data = imem_valid & imem_ready;

   // If this is not inherently true then the icache will need to be
   // explicitly flushed through write operations before leaving
   // TCM memory, or anything can happen...
   initial begin
      for (int i = 0; i < rows; i++)
	valid_mem[i] = 1'b0;
   end

   always @(posedge clk) begin
      ibus_tag_cmp <= tag_mem[ibus_row];
      imem_tag_cmp <= tag_mem[imem_row];
      if (have_data)
	tag_mem[imem_row] <= imem_tag;
   end

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
      imem_inval_q <= imem_inval;
      have_data_q  <= have_data;
   end

   always @(*) begin
      cvalid_we  = have_data_q | (imem_inval_q & (cvalid_tag == imem_tag_cmp));
      cvalid_set = have_data_q;
   end

   always @(posedge clk) begin
      cvalid_ibus <= valid_mem[ibus_row];
      if (cvalid_we)
	valid_mem[cvalid_row] <= cvalid_set;
   end

   reg [tag_bits-1:0] ibus_tag_q;
   reg ibus_valid_q;

   wire   ibus_match = cvalid_ibus & (ibus_tag_q == ibus_tag_cmp);
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
	   imem_a     <= ibus_a[ram_bits-1:0];
	end
     end
endmodule
