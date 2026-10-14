// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// Configuration matrix wrapper for the RV32C decoder unit test.

`include "myriscv.vh"

module rv32c_test #(`CONFIG)
  (
   input  logic [31:0] d,
   output logic [31:0] q_default,
   output logic [31:0] q_disabled,
   output logic [31:0] q_no_zcf,
   output logic [31:0] q_no_zcd,
   output logic [31:0] q_no_zcb,
   output logic [31:0] q_no_zbb,
   output logic [31:0] q_no_zmmul,
   output logic [31:0] q_strict,
   output logic [31:0] q_strict_binutils
   );

   rv32c_comb dut_default (
     .d ( d ), .q ( q_default )
     );

   rv32c_comb #(.enabled(1'b0)) dut_disabled (
     .d ( d ), .q ( q_disabled )
     );

   rv32c_comb #(.WITH_Zcf(1'b0)) dut_no_zcf (
     .d ( d ), .q ( q_no_zcf )
     );

   rv32c_comb #(.WITH_Zcd(1'b0)) dut_no_zcd (
     .d ( d ), .q ( q_no_zcd )
     );

   rv32c_comb #(.WITH_Zcb(1'b0)) dut_no_zcb (
     .d ( d ), .q ( q_no_zcb )
     );

   rv32c_comb #(.WITH_Zbb(1'b0)) dut_no_zbb (
     .d ( d ), .q ( q_no_zbb )
     );

   rv32c_comb #(.WITH_Zmmul(1'b0)) dut_no_zmmul (
     .d ( d ), .q ( q_no_zmmul )
     );

   rv32c_comb #(.STRICT_UNDEFINED(1'b1)) dut_strict (
     .d ( d ), .q ( q_strict )
     );

   rv32c_comb #(
     .STRICT_UNDEFINED ( 1'b1 ),
     .MATCH_BINUTILS  ( 1'b1 )
     ) dut_strict_binutils (
     .d ( d ), .q ( q_strict_binutils )
     );
endmodule
