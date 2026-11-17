//
// dcache.sv
//
// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// Direct-mapped, write-back data cache. Cache lines are one memory word.
//
`include "myriscv.vh"

// Single-clock, one-read/one-write RAM. The caller supplies forwarding for
// a simultaneous same-address read and write, so the M9K mixed-port mode is
// deliberately don't-care.
module dcache_ram
  #(
    parameter int width,
    parameter int address_bits
    )
   (
    input                         clk,
    input [address_bits-1:0]      raddr,
    output wire [width-1:0]       rdata,
    input [address_bits-1:0]      waddr,
    input [width-1:0]             wdata,
    input                         wren
    );

`ifdef SYNTHESIS
   altsyncram ram (
      .address_a     (waddr),
      .address_b     (raddr),
      .byteena_a     (1'b1),
      .clock0        (clk),
      .clock1        (1'b1),
      .data_a        (wdata),
      .data_b        ('x),
      .wren_a        (wren),
      .wren_b        (1'b0),
      .q_a           (),
      .q_b           (rdata),
      .aclr0         (1'b0),
      .aclr1         (1'b0),
      .addressstall_a(1'b0),
      .addressstall_b(1'b0),
      .byteena_b     (1'b1),
      .clocken0      (1'b1),
      .clocken1      (1'b1),
      .clocken2      (1'b1),
      .clocken3      (1'b1),
      .eccstatus     (),
      .rden_a        (1'b1),
      .rden_b        (1'b1)
      );
   defparam
     ram.address_reg_b                     = "CLOCK0",
     ram.clock_enable_input_a              = "BYPASS",
     ram.clock_enable_input_b              = "BYPASS",
     ram.clock_enable_output_a             = "BYPASS",
     ram.clock_enable_output_b             = "BYPASS",
     ram.indata_reg_b                      = "CLOCK0",
     ram.intended_device_family            = "Cyclone IV E",
     ram.lpm_type                          = "altsyncram",
     ram.numwords_a                        = 1 << address_bits,
     ram.numwords_b                        = 1 << address_bits,
     ram.operation_mode                    = "DUAL_PORT",
     ram.outdata_aclr_b                    = "NONE",
     ram.outdata_reg_b                     = "UNREGISTERED",
     ram.power_up_uninitialized            = "FALSE",
     ram.ram_block_type                    = "M9K",
     ram.read_during_write_mode_mixed_ports = "DONT_CARE",
     ram.width_a                           = width,
     ram.width_b                           = width,
     ram.widthad_a                         = address_bits,
     ram.widthad_b                         = address_bits,
     ram.width_byteena_a                   = 1,
     ram.width_byteena_b                   = 1,
     ram.wrcontrol_wraddress_reg_b         = "CLOCK0";
`else
   logic [width-1:0] mem[0:(1 << address_bits)-1];
   logic [width-1:0] rdata_q;

   initial
     for (int i = 0; i < (1 << address_bits); i++)
       mem[i] = '0;

   always @(posedge clk) begin
      rdata_q <= mem[raddr];
      if (wren)
        mem[waddr] <= wdata;
   end

   assign rdata = rdata_q;
`endif
endmodule

module dcache_real
  #(`CONFIG,
    parameter int size_bits = 12)
   (
    input                         rst_n,
    input                         clk,
    input                         clken,

    bus_if.target                 dbus,

    // D-to-M cache lookup bypass. This is issued by the D stage for an
    // operation advancing to E; its result is consumed when that operation
    // reaches the dbus in E.
    input [31:0]                  lookup_a_i,
    input                         lookup_valid_i,
    input                         lookup_hold_i,
    input cbo_t                   lookup_cbo_i,
    input                         lookup_wrq_i,

    bus_if.initiator              dmem
    );

   logic                         dbus_busy;
   logic [31:0]                  dmem_wdata;
   logic                         dmem_wrq;
   logic [3:0]                   dmem_wbe;
   assign dbus.busy = dbus_busy;
   assign dmem.wdata = dmem_wdata;
   assign dmem.wrq = dmem_wrq;
   assign dmem.wbe = dmem_wbe;

   localparam int row_bits = size_bits - 2;
   localparam int tag_bits = ram_size_bits - size_bits;
   localparam int rows = 1 << row_bits;

   typedef enum logic [1:0] {
      S_IDLE,
      S_WRITEBACK,
      S_FILL,
      S_DONE
   } state_t;

   typedef enum logic [1:0] {
      P_MISS,
      P_CBO_CLEAN,
      P_CBO_FLUSH,
      P_CAR_WRITE
   } pending_t;

   // A 36-bit block maps directly to the maximum-width byte-enabled RAM
   // primitive. Bits [35:34] hold {valid, dirty}; [31:0] hold cache data.
   // The D-stage lookup is available while its operation is in E.
   logic [31:0]         lookup_a;
   logic                lookup_valid;
   cbo_t                lookup_cbo;
   logic                lookup_wrq;
   logic [row_bits-1:0] ram_read_row;
   wire [tag_bits-1:0]  tag_read;
   wire [35:0]          data_read;
   logic                read_bypass;
   logic [tag_bits-1:0] read_bypass_tag;
   logic [35:0]         read_bypass_data;

   // Writes are scheduled after accepting a dbus transaction and applied by
   // the cache arrays' write port on the following rising edge.
   logic                cache_write;
   logic [row_bits-1:0] cache_write_row;
   logic [tag_bits-1:0] cache_write_tag;
   logic [35:0]         cache_write_data;

   state_t              state;
   pending_t            pending;
   logic [row_bits-1:0] pending_row;
   logic [tag_bits-1:0] pending_tag;
   logic [31:0]         pending_wdata;
   logic [3:0]          pending_wbe;
   logic                pending_wrq;
   logic [tag_bits-1:0] pending_evict_tag;
   logic [31:0]         pending_evict_data;
   logic [31:0]         done_rdata;

   wire [row_bits-1:0]  dbus_row = dbus.a[size_bits-1:2];
   wire [tag_bits-1:0]  dbus_tag =
                         dbus.a[ram_size_bits-1:size_bits];
   wire                 dbus_cacheable = dbus.a >= ram_base &&
                         dbus.a < io_base;
   wire [row_bits-1:0]  lookup_row =
                         lookup_a[size_bits-1:2];
   wire                 lookup_car = lookup_a[car_bit];
   wire [tag_bits-1:0]  lookup_addr_tag =
                         lookup_a[ram_size_bits-1:size_bits];
   wire [tag_bits-1:0]  lookup_tag =
                         (read_bypass ||
                          (cache_write && cache_write_row == lookup_row)) ?
                         cache_write_tag : tag_read;
   wire [35:0]          lookup_data =
                         (read_bypass ||
                          (cache_write && cache_write_row == lookup_row)) ?
                         cache_write_data : data_read;
   wire                 lookup_cbo_valid = cbo_valid(lookup_cbo);
   wire                 lookup_write = lookup_wrq && !lookup_cbo_valid;
   wire                 lookup_match = lookup_car ||
                         (lookup_data[35] &&
                          lookup_tag == lookup_addr_tag);
   wire                 cbo_match = lookup_car ? lookup_data[35] :
                         lookup_match;
   // A live request without a D-stage lookup holds dbus stable while the
   // synchronous RAM read below prepares a replacement lookup record.
   wire                 replay_lookup = state == S_IDLE && dbus.valid &&
                                        dbus_cacheable && !lookup_valid;
   logic                replay_valid;
   logic [31:0]         replay_wdata;
   logic [3:0]          replay_wbe;
   wire                 request_valid = dbus.valid || replay_valid;
   wire [31:0]          request_wdata = replay_valid ?
                                         replay_wdata : dbus.wdata;
   wire [3:0]           request_wbe = replay_valid ?
                                       replay_wbe : dbus.wbe;

   // A replay owns the request even if ready withdraws the live valid.
   always @(negedge rst_n or posedge clk)
     if (!rst_n) begin
        replay_valid <= 1'b0;
        replay_wdata <= 'x;
        replay_wbe <= 'x;
     end else if (clken) begin
        replay_valid <= replay_lookup;
        if (replay_lookup) begin
           replay_wdata <= dbus.wdata;
           replay_wbe <= dbus.wbe;
        end
     end

   logic                start_writeback;
   logic                start_fill;

   function automatic logic [31:0] merge_bytes
     (input logic [31:0] old_data, input logic [31:0] new_data,
      input logic [3:0] wbe);
      logic [31:0] result;
      begin
         result = old_data;
         for (int i = 0; i < 4; i++)
           if (wbe[i])
             result[i*8 +: 8] = new_data[i*8 +: 8];
         return result;
      end
   endfunction

   always @(*) begin
      start_writeback = 1'b0;
      start_fill = 1'b0;

      if (lookup_valid && state == S_IDLE) begin
         if (lookup_cbo_valid) begin
            start_writeback = cbo_match && lookup_data[34] &&
                              (lookup_cbo == CBO_CLEAN ||
                               lookup_cbo == CBO_FLUSH);
         end else if (lookup_car && lookup_write) begin
            start_writeback = lookup_data[34];
         end else if (!lookup_match) begin
            start_writeback = lookup_data[35] && lookup_data[34];
            start_fill = !start_writeback;
         end
      end
   end

   always @(*) begin
      dbus.rdata = state == S_DONE ? done_rdata :
                   state == S_FILL ? dmem.rdata : lookup_data[31:0];

      if (state == S_DONE)
        dbus.ready = 1'b1;
      else if (state == S_FILL)
        dbus.ready = pending_wrq && dmem.ready;
      else if (state == S_IDLE)
        dbus.ready = lookup_valid &&
                     (lookup_cbo_valid ||
                      (!start_writeback && !start_fill && lookup_match));
      else
        dbus.ready = 1'b0;

      dmem.valid = state == S_WRITEBACK || state == S_FILL;
      dmem_wrq = state == S_WRITEBACK;
      dmem_wbe = state == S_WRITEBACK ? 4'b1111 : 4'b0000;
      dmem_wdata = pending_evict_data;
      dmem.a = state == S_WRITEBACK ?
               { pending_evict_tag, pending_row, 2'b00 } :
               { pending_tag, pending_row, 2'b00 };

      dbus_busy = state == S_WRITEBACK || state == S_FILL || dmem.busy;
   end

   initial begin
      if (size_bits < 2 || size_bits >= ram_size_bits)
        $error("dcache size_bits must be between 2 and ram_size_bits - 1");
   end

   always @(*) begin
      ram_read_row = lookup_row;
      if (replay_lookup) begin
         ram_read_row = dbus_row;
      end else if (!lookup_hold_i) begin
         if (lookup_valid_i)
           ram_read_row = lookup_a_i[size_bits-1:2];
         else if (dbus.valid && dbus_cacheable && state == S_IDLE)
           ram_read_row = dbus_row;
      end
   end

   // The cache arrays are true synchronous memories. The D-stage lookup
   // avoids a half-cycle path from the RAM outputs to dbus.ready.
   dcache_ram #(.width(tag_bits), .address_bits(row_bits)) tag_mem (
      .clk   (clk),
      .raddr (ram_read_row),
      .rdata (tag_read),
      .waddr (cache_write_row),
      .wdata (cache_write_tag),
      .wren  (cache_write)
      );

   dcache_ram #(.width(36), .address_bits(row_bits)) data_mem (
      .clk   (clk),
      .raddr (ram_read_row),
      .rdata (data_read),
      .waddr (cache_write_row),
      .wdata (cache_write_data),
      .wren  (cache_write)
      );

   always @(posedge clk) begin
      if (replay_lookup) begin
         lookup_a <= dbus.a;
         lookup_valid <= rst_n;
         lookup_cbo <= dbus.cbo;
         lookup_wrq <= dbus.wrq;
         read_bypass <= cache_write && cache_write_row == dbus_row;
      end else if (lookup_valid_i) begin
         lookup_a <= lookup_a_i;
         lookup_valid <= rst_n;
         lookup_cbo <= lookup_cbo_i;
         lookup_wrq <= lookup_wrq_i;
         read_bypass <= cache_write &&
                        cache_write_row == lookup_a_i[size_bits-1:2];
      end else if (request_valid && state == S_IDLE &&
                   lookup_valid) begin
         lookup_valid <= 1'b0;
         lookup_cbo <= CBO_NONE;
         lookup_wrq <= 1'b0;
         read_bypass <= 1'b0;
      end else if (lookup_hold_i) begin
         lookup_valid <= lookup_valid;
         lookup_cbo <= lookup_cbo;
         lookup_wrq <= lookup_wrq;
         read_bypass <= read_bypass;
      end else begin
         lookup_valid <= 1'b0;
         lookup_cbo <= CBO_NONE;
         lookup_wrq <= 1'b0;
         read_bypass <= 1'b0;
      end
      read_bypass_tag <= cache_write_tag;
      read_bypass_data <= cache_write_data;
   end

   always @(negedge rst_n or posedge clk)
     if (!rst_n) begin
        state <= S_IDLE;
        pending <= P_MISS;
        pending_row <= 'x;
        pending_tag <= 'x;
        pending_wdata <= 'x;
        pending_wbe <= 'x;
        pending_wrq <= 1'b0;
        pending_evict_tag <= 'x;
        pending_evict_data <= 'x;
        done_rdata <= 'x;
        cache_write <= 1'b0;
        cache_write_row <= 'x;
        cache_write_tag <= 'x;
        cache_write_data <= 'x;
     end else if (clken) begin
        cache_write <= 1'b0;

        case (state)
          S_IDLE:
            if (request_valid && lookup_valid) begin
               if (lookup_cbo_valid) begin
                  if (start_writeback) begin
                     pending <= lookup_cbo == CBO_CLEAN ?
                                P_CBO_CLEAN : P_CBO_FLUSH;
                     pending_row <= lookup_row;
                     pending_evict_tag <= lookup_tag;
                     pending_evict_data <= lookup_data[31:0];
                     state <= S_WRITEBACK;
                  end else if (cbo_match &&
                               (lookup_cbo == CBO_INVAL ||
                                lookup_cbo == CBO_FLUSH)) begin
                     cache_write <= 1'b1;
                     cache_write_row <= lookup_row;
                     cache_write_tag <= lookup_tag;
                     cache_write_data <= { 2'b00, 2'b00,
                                           lookup_data[31:0] };
                  end
               end else if (lookup_car && lookup_write) begin
                  if (start_writeback) begin
                     pending <= P_CAR_WRITE;
                     pending_row <= lookup_row;
                     pending_wdata <= request_wdata;
                     pending_wbe <= request_wbe;
                     pending_evict_tag <= lookup_tag;
                     pending_evict_data <= lookup_data[31:0];
                     state <= S_WRITEBACK;
                  end else begin
                     cache_write <= 1'b1;
                     cache_write_row <= lookup_row;
                     cache_write_tag <= lookup_tag;
                     cache_write_data <=
                       { 2'b00, 2'b00,
                         merge_bytes(lookup_data[31:0], request_wdata,
                                     request_wbe) };
                  end
               end else if (!lookup_match) begin
                  pending <= P_MISS;
                  pending_row <= lookup_row;
                  pending_tag <= lookup_addr_tag;
                  pending_wdata <= request_wdata;
                  pending_wbe <= request_wbe;
                  pending_wrq <= lookup_write;
                  pending_evict_tag <= lookup_tag;
                  pending_evict_data <= lookup_data[31:0];
                  state <= start_writeback ? S_WRITEBACK : S_FILL;
               end else if (lookup_write) begin
                  cache_write <= 1'b1;
                  cache_write_row <= lookup_row;
                  cache_write_tag <= lookup_tag;
                  cache_write_data <=
                    { 2'b11, 2'b00,
                      merge_bytes(lookup_data[31:0], request_wdata,
                                  request_wbe) };
               end
            end

          S_WRITEBACK:
            if (dmem.ready) begin
               case (pending)
                 P_MISS:
                   state <= S_FILL;
                 P_CBO_CLEAN: begin
                    cache_write <= 1'b1;
                    cache_write_row <= pending_row;
                    cache_write_tag <= pending_evict_tag;
                    cache_write_data <= { 2'b10, 2'b00,
                                          pending_evict_data };
                    state <= S_IDLE;
                 end
                 P_CBO_FLUSH: begin
                    cache_write <= 1'b1;
                    cache_write_row <= pending_row;
                    cache_write_tag <= pending_evict_tag;
                    cache_write_data <= { 2'b00, 2'b00,
                                          pending_evict_data };
                    state <= S_IDLE;
                 end
                 P_CAR_WRITE: begin
                    cache_write <= 1'b1;
                    cache_write_row <= pending_row;
                    cache_write_tag <= pending_evict_tag;
                    cache_write_data <=
                      { 2'b00, 2'b00,
                        merge_bytes(pending_evict_data, pending_wdata,
                                    pending_wbe) };
                    state <= S_DONE;
                 end
               endcase
            end

          S_FILL:
            if (dmem.ready) begin
               cache_write <= 1'b1;
               cache_write_row <= pending_row;
               cache_write_tag <= pending_tag;
               cache_write_data <=
                 { 1'b1, pending_wrq, 2'b00,
                   pending_wrq ?
                   merge_bytes(dmem.rdata, pending_wdata, pending_wbe) :
                   dmem.rdata };
               done_rdata <= dmem.rdata;
               state <= pending_wrq ? S_IDLE : S_DONE;
            end

          S_DONE:
            state <= S_IDLE;
        endcase
     end
endmodule

module dcache #(`CONFIG)
   (
   input		      rst_n,
   input		      clk,
   input		      clken,

   bus_if.target	      dbus,

   input [31:0]		      lookup_a_i,
   input		      lookup_valid_i,
   input		      lookup_hold_i,
   input cbo_t		      lookup_cbo_i,
   input		      lookup_wrq_i,

   bus_if.initiator	      dmem
);

   generate
      if (dcache_size_bits) begin : dc_real
	 dcache_real #(`CFG) dc(.*);
      end else begin : dc_stub
	 // Null dcache stub (simply passes the dbus through to the dmem bus)
	 // CBO operations are dropped simply ignored

	 assign dmem.a     = dbus.a[ram_size_bits-1:0];
	 assign dmem.wdata = dbus.wdata;
	 assign dmem.valid = dbus.valid & ~cbo_valid(dbus.cbo);
	 assign dmem.wrq   = dbus.wrq;
	 assign dmem.wbe   = dbus.wbe;
	 assign dbus.rdata = dmem.rdata;
	 assign dbus.ready = dmem.ready | cbo_valid(dbus.cbo);
	 assign dbus.busy  = dmem.busy;
      end
   endgenerate
endmodule
