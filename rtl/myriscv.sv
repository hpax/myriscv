module fetch #(
	       parameter [31:0]	pc_mask = 32'hffff_fffe,
	       parameter	buffer_hwords = 4
	       ) (
		  input		rst_n,
		  input		clk,

		  input [31:0]	reset_pc,
		  input [31:0]	new_pc,
		  input		load_pc,

		  output [31:0]	ibus_a,
		  output	ibus_valid,
		  input [31:0]	ibus_d,
		  input		ibus_rdy,

		  // Stall pipeline input
		  input		f_stall,

		  // Outputs to decode stage
		  output [31:0]	d_insn,
		  output [31:0]	d_pc,
		  output	d_kill,
		  output	d_valid
		  );

   localparam			max_hword = buffer_hwords - 1;
   localparam			bufidx_max = $clog2(buffer_hwords) - 1;

   reg [31:0]			f_pc = 'b0;
   reg [15:0]			ibuf[0:max_hword];	// Instruction buffer
   reg [max_hword:0]		ibuf_valid;		// Valid halfwords

   logic [bufidx_max:0]		ibuf_next;
   logic			ibuf_space;

   always_comb
     begin
	ibuf_space = 1'b0;
	for (int i = max_hword-2; i >= 0; i--)
	  if (!ibuf_valid[i])
	    begin
	       ibuf_next  = i;
	       ibuf_space = 1'b1;
	    end
     end

   assign d_insn  = ibuf[31:0];
   assign d_valid = ibuf_valid[0] & (ibuf_valid[1] || ibuf[0][1:0] != 2'b11);

   assign ibus_a     = { f_pc[31:2] + (ibus_valid_q & ibuf_rdy), 2'b00 };
   assign ibus_valid = ~(ibus_rdy & ibuf_space);

   reg ibus_valid_q;

   always @(posedge clk or negedge rst_n)
     if (~rst_n)
       begin
	  f_pc <= reset_pc & pc_mask;
	  d_pc <= reset_pc & pc_mask;
	  ibus_valid_q <= 'b0;
       end
     else
       begin
	  ibus_valid_q <= ibus_valid;

	  if (new_pc & (f_pc != load_pc))
	    begin
	       f_pc         <= new_pc;
	       ibus_valid_q <= 'b0;
	    end
	  else if (ibus_rdy & ibus_valid_q)
	    begin
	       ibuf[ibus_next] <= ibus_d[15:0];
	       ibuf[ibus_next+1'b1] <= ibus_d[31:16];
	       f_pc    <= ibus_a;
	       d_pc    <= f_pc - { ibus_next, 1'b0 };
	    end
       end // else: !if(~rst_n)
endmodule // fetch

