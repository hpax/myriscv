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
// The output data (rdata) is valid ONLY in the cycle following rstb assertion;
// if it needs to be latched then that needs to happen in logic external to this
// module.
//
`include "myriscv.vh"

// Primitive polynomials of degrees 0-32.
// These aren't necessarily the only possible ones, nor are they the "simplest"
// (fewest XORs). The bits are set to the bit number matches the coefficient degree,
// e.g. 101001 = x^5+x^3+1.
function automatic logic [32:0] primitive_polynomial(input degree);
   logic [32:0] poly;
   unique case (degree)
      0: poly =  1'b1;
      1: poly =  2'b11;
      2: poly =  3'b111;
      3: poly =  4'b1011;
      4: poly =  5'b10011;
      5: poly =  6'b110111;
      6: poly =  7'b1100111;
      7: poly =  8'b10011101;
      8: poly =  9'b100101011;
      9: poly = 10'b1000101101;
     10: poly = 11'b10111100101;
     11: poly = 12'b100101110011;
     12: poly = 13'b1011101000101;
     13: poly = 14'b10011101001111;
     14: poly = 15'b100101001100101;
     15: poly = 16'b1000100011000111;
     16: poly = 17'b10100010100001011;
     17: poly = 18'b100001000001001111;
     18: poly = 19'b1000000001011110001;
     19: poly = 20'b10000000001110011111;
     20: poly = 21'b100000000100101001101;
     21: poly = 22'b1000000000010001011101;
     22: poly = 23'b10000100000001010000111;
     23: poly = 24'b100000100000101100110011;
     24: poly = 25'b1010101010100101110110001;
     25: poly = 26'b10000000100000010000001111;
     26: poly = 27'b100000010011110101111101101;
     27: poly = 28'b1000010000000010100001111001;
     28: poly = 29'b10000000000000010101000101001;
     29: poly = 30'b100000000001000100000001001101;
     30: poly = 31'b1000001000100010110100010000111;
     31: poly = 32'b10000000000100001000000000111001;
     32: poly = 33'b1100000000100000110100010111101001;
     default: poly = 33'bx;
   endcase
   primitive_polynomial = poly;
endfunction

module rng_zkr #(`CONFIG)
 (
  input		   rst_n,
  input		   clk,
  input		   clken,
  input		   rng_bus_t rng,
  output	   rng_full,
  output reg [31:0] rdata,
  input		   rstb
  );

   localparam logic [1:0] RNG_BIST = 2'b00;
   localparam logic [1:0] RNG_WAIT = 2'b01;
   localparam logic [1:0] RNG_ES16 = 2'b10;
   localparam logic [1:0] RNG_DEAD = 2'b11;

   wire [Zkr_bits:0]	  acc_poly = primitive_polynomial(Zkr_bits+1);

   reg [Zkr_bits-1:0]	  acc    = 'b0;		// Randomness accumulator
   reg [4:0]		  ectr   = Zkr_bits;	// Entropy needed counter
   reg [1:0]		  status = RNG_WAIT;

   reg			  rng_bist_q;		// rng_bist asserted since last read

   assign rng_full = !WITH_Zkr | !ectr;

   always @(negedge rst_n or posedge clk)
     if (~rst_n) begin
	ectr	   <= 5'd0;
	status	   <= RNG_WAIT;
	rng_bist_q <= 1'b0;
     end else if (WITH_Zkr & clken) begin
	rng_bist_q <= rng.bist | (rng_bist_q & ~rstb);

	if (rng.stb)
	  acc <= { rng.data, acc[Zkr_bits-1:1] } ^
		 { {Zkr_bits{acc[0]}} & acc_poly[Zkr_bits:1] };

	if (rng.incr)
	  ectr <= ectr - ~rng_full; // Saturating counter
	if (rng.dead | rng.bist | (rstb & (status == RNG_ES16)))
	  ectr <= Zkr_bits;

	if (rng.dead)
	  status <= RNG_DEAD;
	else if (rng.bist | rng_bist_q)
	  status <= RNG_BIST;
	else if (rng_full)
	  status <= RNG_ES16;
	else
	  status <= RNG_WAIT;
     end

   always @(*) begin
      rdata = 32'b0;

      if (WITH_Zkr) begin
	 rdata[31:30] = status;
	 if (!Zkr_secure || status == RNG_ES16)
	   rdata[Zkr_bits-1:0] = acc[Zkr_bits-1:0];
      end
   end
endmodule
