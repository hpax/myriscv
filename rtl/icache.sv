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
  parameter row_bits  = 10,	// = 2^12 bytes = 4K
	    )
   (
    input		  rst_n,
    input		  clk,
    input		  clken,

    input [31:0]	  ibus_a,
    input		  ibus_valid,
    output [31:0]	  ibus_rdata,
    output		  ibus_ready,

    // Important: imem_a_i must equal imem_a when imem_ready is high!
    // This is done by simply having imem_a_i trace the address bus on
    // the actual RAM interface and strobe imem_rdata or imem_inval
    // accordingly.
    input [imem_bits-1:0] imem_a_i,
    input		  imem_inval,

    output [imem_bits-1:0] imem_a,
    output		  imem_valid,
    input		  imem_ready,
    input [31:0]	  imem_rdata);

   localparam		  tag_bits = imem_bits - row_bits - line_bits;
   localparam		  rows = 1 << row_bits;

   reg [tag_bits:0]	  tag_mem [0:rows-1];
   reg [line_bits-1:0]	  data_mem[0:rows-1];
   reg			  valid_mem[0:rows-1];

   wire [row_bits-1:0]	  ibus_row = ibus_a[row_bits+line_bits-1:line_bits];
   wire [tag_bits:0]	  ibus_tag; // Tag contains the valid bit, too
   wire [tag_bits:0]	  imem_tag;

   wire [row_bits-1:0]	  tag_wrow = imem_a[row_bits+line_bits-1:line_bits];
   wire			  tag_we   = imem_valid & imem_ready;
   wire [tag_bits:0]	  tag_wtag = imem_a[imem_bits-1:imem_bits-tag_bits];

   always @(posedge clk) begin
      ibus_tag <= tag_mem[ibus_row];
      imem_tag <= tag_mem[tag_wrow];
      if (tag_we)
	tag_mem[tag_wrow] <= tag_wtag;
   end

   wire data_we = imem_valid & imem_ready;
   wire [31:0] data_wdata = imem_rdata;

   always @(posedge clk) begin
      ibus_rdata <= data_mem[ibus_row];
      if (data_we)
	data_mem[tag_waddr] <= imem_rdata;
   end

   reg [row_bits-1:0] cvalid_wrow;
   reg		      cvalid_we;
   reg		      cvalid_set;
   reg [tag_bits-1:0] imem_tag_match;

   logic	      cvalid_ibus;

   always @(posedge clk) begin
      imem_tag_match <= imem_a[imem_bits-1:imem_bits-tag_bits];
      cvalid_wrow     <= tag_wrow;
      cvalid_we       <= tag_we | (imem_imem & (imem_tag == imem_tag_match));
      cvalid_set      <= tag_we;
   end

   always @(posedge clk) begin
      cvalid_ibus <= valid_mem[ibus_row];
      if (cvalid_we)
	valid_mem[cvalid_wrow] <= cvalid_set;
   end

   reg ibus_valid_q;

   assign ibus_match = cvalid_ibus &
		       (ibus_tag == ibus_a[imem_bits-1:imem_bits-tag_bits]);
   assign ibus_ready = ibus_valid_q & ibus_match;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ibus_valid_q <= 1'b0;
	imem_valid   <= 1'b0;
	imem_a	     <= 'bx;
     end else if (clken) begin
	ibus_valid_q <= ibus_valid;

	if (imem_valid) begin
	   imem_valid <= ~imem_ready;
	end else if (ibus_valid_q & ~ibus_match) begin
	   imem_valid <= 1'b1;
	   imem_a     <= ibus_a[imem_bits-1:0];
	end
     end
endmodule
