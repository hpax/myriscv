// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// Synchronous transaction buses; see doc/busif.md.

interface bus_if #(
   parameter int address_bits = 32,
   parameter bit writeable = 1'b0,
   parameter bit cache_ops = 1'b0,
   parameter bit posted = 1'b0,
   parameter bit snoop = 1'b0,
   parameter bit geographical = 1'b0,
   parameter bit dma = 1'b0
);
   import myriscv_types::*;

   logic [address_bits-1:0] a;
   logic		   valid;
   logic [31:0]		   rdata;
   logic		   ready;

   tri0			   wrq;
   tri [31:0]		   wdata;
   tri0 [3:0]		   wbe;
   tri0 [$bits(cbo_t)-1:0]  cbo;
   tri0			   busy;

   // Memory transaction snoop information, independent of CPU requests.
   tri [address_bits-1:0]   a_in;
   tri0			   inval;
   tri0			   inval_geo;
   tri1			   cpu;

   // Quartus drops interface pull defaults; give absent capabilities
   // explicit sources rather than leaving undriven alias loops.
   generate
      if (!writeable) begin : no_write
	 assign wrq = 1'b0;
	 assign wdata = '0;
	 assign wbe = '0;
      end
      if (!cache_ops) begin : no_cbo
	 assign cbo = '0;
      end
      if (!posted) begin : no_post
	 assign busy = 1'b0;
      end
      if (!snoop) begin : no_snoop
	 assign a_in = '0;
	 assign inval = 1'b0;
      end
      if (!geographical) begin : no_geo
	 assign inval_geo = 1'b0;
      end
      if (!dma) begin : cpu_only
	 assign cpu = 1'b1;
      end
   endgenerate

   modport initiator (
      output a, valid, wrq, wdata, wbe, cbo,
      input rdata, ready, busy
   );
   modport target (
      input a, valid, wrq, wdata, wbe, cbo,
      output rdata, ready, busy
   );
   modport read_initiator (
      output a, valid,
      input rdata, ready
   );
   modport read_target (
      input a, valid,
      output rdata, ready
   );
   modport cache_initiator (
      output a, valid,
      input rdata, ready, a_in, inval, inval_geo
   );
   modport memory_initiator (
      output a, valid, wrq, wdata, wbe,
      input rdata, ready, busy, a_in, inval, cpu
   );
   modport memory_target (
      input a, valid, wrq, wdata, wbe,
      output rdata, ready, busy, a_in, inval, cpu
   );
   modport monitor (
      input a, valid, wrq, wdata, wbe, cbo, rdata, ready, busy,
	    a_in, inval, inval_geo, cpu
   );
endinterface
