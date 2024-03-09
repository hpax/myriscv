//
// tcm.sv
//
// Dual-ported tightly coupled memory
//

module tcm
  #(
    parameter	     sizebits = 14	// log2(bytes)
    )
   (
    input		 rst_n,
    input		 clk,

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

   reg [31:0]		 mem[0:(1 << (sizebits-2))-1];

`ifdef INITFILE
   initial
     $readmemh(`INITFILE, mem);
`endif

   wire [sizebits-1:2]	 ia = ibus_a[sizebits-1:2];
   wire [sizebits-1:2]	 da = dbus_a[sizebits-1:2];

   always @(posedge clk)
     begin
	ibus_rdata <= mem[ia];
	dbus_rdata <= mem[da];

	ibus_ready <= ibus_valid;
	dbus_ready <= dbus_valid;

	if (dbus_valid & dbus_wrq)
	  begin
	     if (dbus_wbe[0]) mem[da][7:0]   <= dbus_wdata[7:0];
	     if (dbus_wbe[1]) mem[da][15:8]  <= dbus_wdata[15:8];
	     if (dbus_wbe[2]) mem[da][23:16] <= dbus_wdata[23:16];
	     if (dbus_wbe[3]) mem[da][31:24] <= dbus_wdata[31:24];
	  end
     end // always @ (posedge clk)
endmodule
