//
// tcm.sv
//
// Dual-ported tightly coupled memory
//

module tcm
  #(
    parameter	     sizebits = 12, // log2(words)
    parameter string initfile = ""
    )
   (
    input		 rst_n,
    input		 clk,

    input [sizebits+1:0] ibus_a,
    input		 ibus_valid,
    output reg [31:0]	 ibus_rdata,
    output reg		 ibus_ready,

    input [sizebits+1:0] dbus_a,
    input [31:0]	 dbus_wdata,
    input		 dbus_valid,
    input		 dbus_wrq,
    input [3:0]		 dbus_wbe,
    output reg [31:0]	 dbus_rdata,
    output reg		 dbus_ready
    );

   reg [31:0]		 mem[0:(1 << sizebits)-1];

   initial
     if (initfile != "")
       $readmemh(initfile, mem);

   always @(posedge clk)
     begin
	ibus_rdata <= mem[ibus_a];
	dbus_rdata <= mem[dbus_a];

	ibus_ready <= ibus_valid;
	dbus_ready <= dbus_valid;

	if (dbus_valid & dbus_wrq)
	  begin
	     if (dbus_wbe[0]) mem[dbus_a][7:0]   <= dbus_wdata[7:0];
	     if (dbus_wbe[1]) mem[dbus_a][15:8]  <= dbus_wdata[15:8];
	     if (dbus_wbe[2]) mem[dbus_a][23:16] <= dbus_wdata[23:16];
	     if (dbus_wbe[3]) mem[dbus_a][31:24] <= dbus_wdata[31:24];
	  end
     end // always @ (posedge clk)
endmodule
