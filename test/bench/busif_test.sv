// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>

`timescale 1 ns / 1 ps

module busif_test;
   bus_if read_bus();
   bus_if #(.address_bits(9), .writeable(1'b1), .cache_ops(1'b1),
	    .posted(1'b1), .snoop(1'b1), .geographical(1'b1),
	    .dma(1'b1)) full_bus();

   logic [31:0] drive;
   wire [38:0] read_controls, full_controls;

   busif_test_target read_target(read_bus, read_controls);
   busif_test_target full_target(full_bus, full_controls);

   assign read_bus.a = drive;
   assign read_bus.valid = 1'b1;
   assign full_bus.a = drive[8:0];
   assign full_bus.valid = 1'b1;
   assign full_bus.wrq = drive[0];
   assign full_bus.wbe = drive[4:1];
   assign full_bus.cbo = drive[6:5];
   assign full_bus.wdata = drive;
   assign full_bus.busy = drive[7];
   assign full_bus.inval = drive[8];
   assign full_bus.cpu = drive[9];
   assign full_bus.inval_geo = drive[10];
   assign full_bus.a_in = drive[17:9];

   task automatic fail(string message);
      $error("%s", message);
      $stop;
   endtask

   initial begin
      for (int i = 0; i < 4; i++) begin
	 case (i)
	   0: drive = 32'h00000000;
	   1: drive = 32'hffffffff;
	   2: drive = 32'h123456a5;
	   3: drive = 32'h0102055a;
	 endcase
	 #1;
	 if (read_controls !== '0 || read_bus.busy !== 1'b0 ||
	     read_bus.inval !== 1'b0 || read_bus.inval_geo !== 1'b0 ||
	     read_bus.a_in !== '0 || read_bus.cpu !== 1'b1)
	   fail("Omitted bus controls are not inactive");
	 if (read_bus.ready !== 1'b1 || read_bus.rdata !== ~drive)
	   fail("Read request with omitted controls failed");
	 if (full_controls !== {drive[0], drive[4:1], drive[6:5], drive} ||
	     full_bus.busy !== drive[7] || full_bus.inval !== drive[8] ||
	     full_bus.cpu !== drive[9] || full_bus.inval_geo !== drive[10] ||
	     full_bus.a_in !== drive[17:9])
	   fail("Enabled controls do not override the pull defaults");
	 if (full_bus.ready !== 1'b1 ||
	     full_bus.rdata !== ~{23'b0, drive[8:0]})
	   fail("Narrow-address request failed");
      end
      $display("PASS: bus interface defaults and driven controls");
      $finish;
   end
endmodule

module busif_test_target(bus_if.target bus, output [38:0] controls);
   assign controls = {bus.wrq, bus.wbe, bus.cbo, bus.wdata};
   assign bus.rdata = ~32'(bus.a);
   assign bus.ready = 1'b1;
endmodule
