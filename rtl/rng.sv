//
// Zkr random number generator, accepting a serial bit stream.
//
// The option SECURE_Zkr controls if the entropy bits are forced to 0
// if the state is not ES16.
//
// The inputs are:
//
// rng.data	- one-bit data input
// rng.stb	- rng.data should be shifted
// rng.incr	- increment the entropy counter
// rng.bist	- assert the BIST status
// rng.dead	- assert the DEAD status
//
// For a pre-whitened bit stream, set rng.stb = rng.incr.
// Otherwise, rng.stb can be strobed more often than rng.incr.
//
// rng_full is asserted if the entropy counter is full; this can be used
// to power-manage the entropy source if needed.
//
`include "myriscv.vh"

module rng_zkr #(
  `CONFIG,
  parameter		 acc_bits = 16,
  parameter [acc_bits:0] acc_poly = 17'h1a011  // x^16+x^15+x^13+x^4+1
) (
  input		rst_n,
  input		clk,
  input		clken,
  input		rng_bus_t rng,
  output	rng_full,
  output [31:0]	rdata,
  input		rstb
  );

   localparam logic [1:0] RNG_BIST = 2'b00;
   localparam logic [1:0] RNG_WAIT = 2'b01;
   localparam logic [1:0] RNG_ES16 = 2'b10;
   localparam logic [1:0] RNG_DEAD = 2'b11;

   reg [acc_bits-1:0]  acc    = 'b0;		// Randomness accumulator
   reg [4:0]	       ectr   = 5'd0;		// Entropy counter
   reg [1:0]	       status = RNG_BIST;

   assign rng_full = !WITH_Zkr | ectr[4];

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ectr   <= 5'd0;
	status <= RNG_BIST;
     end else if (WITH_Zkr & clken) begin
	if (rng.stb)
	  acc <= { rng.data, acc[acc_bits-1:1] } ^
		 { {acc_bits{acc[0]}} & acc_poly[acc_bits:1] };

	if (rng.incr)
	  ectr <= ectr + ~rng_full; // Saturating counter
	if (rng.dead | rng.bist | (rstb & (status == RNG_ES16)))
	  ectr <= 5'd0;

	if (rng.dead)
	  status <= RNG_DEAD;
	else if (rng.bist)
	  status <= RNG_BIST;
	else if (rng_full)
	  status <= RNG_ES16;
	else
	  status <= RNG_WAIT;
     end

   always @(*) begin
      rdata = 32'b0;

      if (WITH_Zkr) begin
	 rdata[31:30]  = status;
	 if (!Zkr_secure || status == RNG_ES16)
	   rdata[15:0] = acc[15:0];
      end
   end
endmodule
