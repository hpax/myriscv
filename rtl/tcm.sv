//
// tcm.sv
//
// Dual-ported tightly coupled memory
//

`define RAW

`ifdef RAW
module tcm
  #(
    parameter	     sizebits = 14, // log2(bytes)
    parameter string init_file = ""
    )
   (
    input		 rst_n,
    input		 clk,
    input		 clken,

    input [sizebits-1:0] ibus_a,
    input		 ibus_valid,
    output reg [31:0]	 ibus_rdata,
    output reg		 ibus_ready,

    input [sizebits-1:0] dbus_a,
    input [31:0]	 dbus_wdata,
    input		 dbus_valid,
    input		 dbus_wrq,
    input [3:0]		 dbus_wbe,
    output reg [31:0]	 dbus_rdata,
    output reg		 dbus_ready
    );

   // Convert from byte address to word address and strip unused bits
   wire [sizebits-1:2]	 ia = ibus_a[sizebits-1:2];
   wire [sizebits-1:2]	 da = dbus_a[sizebits-1:2];

   wire			 wren = rst_n & dbus_valid & dbus_wrq;

   localparam		 nwords = 1 << (sizebits-2);
   reg [3:0][7:0]	 mem[0:nwords-1];

   initial begin
     if (init_file != "")
       $readmemh({init_file}, mem);
   end

   // XXX: clken on the reads breaks something; figure that out
   // later...
   always @(posedge clk) begin
      ibus_rdata <= mem[ia];
      dbus_rdata <= mem[da];

      if (clken & wren) begin
	 if (dbus_wbe[0]) mem[da][0] <= dbus_wdata[7:0];
	 if (dbus_wbe[1]) mem[da][1] <= dbus_wdata[15:8];
	 if (dbus_wbe[2]) mem[da][2] <= dbus_wdata[23:16];
	 if (dbus_wbe[3]) mem[da][3] <= dbus_wdata[31:24];
      end
   end // always @ (posedge clk)

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ibus_ready <= 1'b0;
	dbus_ready <= 1'b0;
     end else if (clken) begin
	ibus_ready <= ibus_valid;
	dbus_ready <= dbus_valid;
     end
endmodule

`else
module tcm
  #(
    parameter	     sizebits = 14	// log2(bytes)
    )
   (
    input		 rst_n,
    input		 clk,
    input		 clken,

    input [sizebits-1:0] ibus_a,
    input		 ibus_valid,
    output reg [31:0]	 ibus_rdata,
    output reg		 ibus_ready,

    input [sizebits-1:0] dbus_a,
    input [31:0]	 dbus_wdata,
    input		 dbus_valid,
    input		 dbus_wrq,
    input [3:0]		 dbus_wbe,
    output reg [31:0]	 dbus_rdata,
    output reg		 dbus_ready
    );

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ibus_ready <= 1'b0;
	dbus_ready <= 1'b0;
     end else if (clken) begin
	ibus_ready <= ibus_valid;
	dbus_ready <= dbus_valid;
     end

   tcm_alt tcm_alt (
     .address_a	( dbus_a[sizebits-1:2] ),
     .address_b ( ibus_a[sizebits-1:2] ),
     .byteena_a ( dbus_wbe ),
     .clock     ( clk ),
     .data_a    ( dbus_wdata ),
     .data_b    ( 32'bx ),
     .wren_a    ( dbus_valid & dbus_wrq ),
     .wren_b    ( 1'b0 ),
     .q_a       ( dbus_rdata ),
     .q_b	( ibus_rdata )
     );
endmodule
`endif
