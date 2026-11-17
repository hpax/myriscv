// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// tcm.sv
//
// Dual-ported tightly coupled memory
//

`include "myriscv.vh"

`define RAW

`ifdef RAW
module tcm #(`CONFIG)
   (
    input	      rst_n,
    input	      clk,
    input	      clken,

    bus_if.read_target ibus,
    bus_if.target      dbus
    );

   // Convert from byte address to word address and strip unused bits
   wire [tcm_size_bits-1:2]	 ia = ibus.a[tcm_size_bits-1:2];
   wire [tcm_size_bits-1:2]	 da = dbus.a[tcm_size_bits-1:2];

   wire			 wren = rst_n & dbus.valid & dbus.wrq;

   localparam		 nwords = 1 << (tcm_size_bits-2);
   reg [3:0][7:0]	 mem[0:nwords-1];

   // Quartus doesn't like init_file begin a parameter here...
`ifndef SYNTHESIS
   initial begin : init_tcm
      string init_file;
      if (!$value$plusargs("tcm_init=%s", init_file))
	init_file = TCM_INIT_FILE;
      if (init_file != "")
	$readmemh(init_file, mem);
   end
`else
   generate
      if (TCM_INIT_FILE != "") begin : init_tcm
	 initial begin
	    $readmemh(TCM_INIT_FILE, mem);
	 end
      end
   endgenerate
`endif

   // XXX: clken on the reads breaks something; figure that out
   // later...
   always @(posedge clk) begin
      ibus.rdata <= mem[ia];
      dbus.rdata <= mem[da];

      if (clken & wren) begin
	 if (dbus.wbe[0]) mem[da][0] <= dbus.wdata[7:0];
	 if (dbus.wbe[1]) mem[da][1] <= dbus.wdata[15:8];
	 if (dbus.wbe[2]) mem[da][2] <= dbus.wdata[23:16];
	 if (dbus.wbe[3]) mem[da][3] <= dbus.wdata[31:24];
      end
   end // always @ (posedge clk)

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ibus.ready <= 1'b0;
	dbus.ready <= 1'b0;
     end else if (clken) begin
	ibus.ready <= ibus.valid;
	dbus.ready <= dbus.valid;
     end
endmodule

`else
module tcm #(`CONFIG)
  #(
    parameter	     sizebits = 14	// log2(bytes)
    )
   (
    input		 rst_n,
    input		 clk,
    input		 clken,

    bus_if.read_target ibus,
    bus_if.target      dbus
    );

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ibus.ready <= 1'b0;
	dbus.ready <= 1'b0;
     end else if (clken) begin
	ibus.ready <= ibus.valid;
	dbus.ready <= dbus.valid;
     end

   tcm_alt tcm_alt (
     .address_a	( dbus.a[sizebits-1:2] ),
     .address_b ( ibus.a[sizebits-1:2] ),
     .byteena_a ( dbus.wbe ),
     .clock     ( clk ),
     .data_a    ( dbus.wdata ),
     .data_b    ( 32'bx ),
     .wren_a    ( dbus.valid & dbus.wrq ),
     .wren_b    ( 1'b0 ),
     .q_a       ( dbus.rdata ),
     .q_b	( ibus.rdata )
     );
endmodule
`endif
