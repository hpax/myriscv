// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
//
// Exhaustive RV32C decoder test. Invalid encodings deliberately return
// INVALID_INSN, whose upper bits are don't-care.

`timescale 1 ns / 1 ps

`include "myriscv.vh"

module bench #(
  parameter string infile = "",
  parameter string outfile = "",
  `CONFIG
  );
   typedef struct packed {
      logic        valid;
      logic [31:0] insn;
   } expected_t;

   logic [31:0] d;
   logic [31:0] q_default;
   logic [31:0] q_disabled;
   logic [31:0] q_no_zcf;
   logic [31:0] q_no_zcd;
   logic [31:0] q_no_zcb;
   logic [31:0] q_no_zbb;
   logic [31:0] q_no_zmmul;
   logic [31:0] q_strict;
   logic [31:0] q_strict_binutils;

   rv32c_test #(`CFG) dut (
     .d                 ( d ),
     .q_default         ( q_default ),
     .q_disabled        ( q_disabled ),
     .q_no_zcf          ( q_no_zcf ),
     .q_no_zcd          ( q_no_zcd ),
     .q_no_zcb          ( q_no_zcb ),
     .q_no_zbb          ( q_no_zbb ),
     .q_no_zmmul        ( q_no_zmmul ),
     .q_strict          ( q_strict ),
     .q_strict_binutils ( q_strict_binutils )
     );

   function automatic logic [31:0] insn_i(
     input logic [4:0] rd, input logic [4:0] rs1,
     input logic [11:0] imm, input logic [2:0] funct3, input op_t op);
      insn_i = {imm, rs1, funct3, rd, op};
   endfunction

   function automatic logic [31:0] insn_r(
     input logic [4:0] rd, input logic [4:0] rs1, input logic [4:0] rs2,
     input logic [6:0] funct7, input logic [2:0] funct3, input op_t op);
      insn_r = {funct7, rs2, rs1, funct3, rd, op};
   endfunction

   function automatic logic [31:0] insn_s(
     input logic [4:0] rs1, input logic [4:0] rs2,
     input logic [11:0] imm, input logic [2:0] funct3, input op_t op);
      insn_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], op};
   endfunction

   function automatic logic [31:0] insn_b(
     input logic [4:0] rs1, input logic [4:0] rs2,
     input logic [12:0] imm, input logic [2:0] funct3);
      insn_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11],
		BRANCH};
   endfunction

   function automatic logic [31:0] insn_u(
     input logic [4:0] rd, input logic [19:0] imm, input op_t op);
      insn_u = {imm, rd, op};
   endfunction

   function automatic logic [31:0] insn_j(
     input logic [4:0] rd, input logic [20:0] imm);
      insn_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, JAL};
   endfunction

   function automatic expected_t expand(
     input logic [31:0] encoded,
     input bit enabled, input bit zcf, input bit zcd, input bit zcb,
     input bit zbb, input bit zmmul, input bit strict, input bit match_binutils
     );
      logic [31:0] i;
      logic [4:0] p1, p2, r1, r2;
      logic [5:0] ci_imm;
      expected_t result;

      i = encoded;
      p1 = {2'b01, i[9:7]};
      p2 = {2'b01, i[4:2]};
      r1 = i[11:7];
      r2 = i[6:2];
      ci_imm = {i[12], i[6:2]};
      result.valid = 1'b0;
      result.insn = 'x;

      if (!enabled || i[1:0] == 2'b11) begin
	 result.valid = 1'b1;
	 result.insn = i;
      end else begin
	 unique case (i[1:0])
	   2'b00: unique case (i[15:13])
	     3'b000:
	       if (i[12:5]) begin
		  result.valid = 1'b1;
		  result.insn = insn_i(p2, 5'd2,
		    {2'b00, i[10:7], i[12:11], i[5], i[6], 2'b00},
		    3'b000, OP_IMM);
	       end
	     3'b001:
	       if (zcd) begin
		  result.valid = 1'b1;
		  result.insn = insn_i(p2, p1, {i[6:5], i[12:10], 3'b0},
		    3'b011, LOAD_FP);
	       end
	     3'b010: begin
		result.valid = 1'b1;
		result.insn = insn_i(p2, p1, {i[5], i[12:10], i[6], 2'b0},
		  3'b010, LOAD);
	     end
	     3'b011:
	       if (zcf) begin
		  result.valid = 1'b1;
		  result.insn = insn_i(p2, p1, {i[5], i[12:10], i[6], 2'b0},
		    3'b010, LOAD_FP);
	       end
	     3'b100: begin
		unique casez ({i[12:10], i[6]})
		  4'b000_?:
		    if (zcb) begin
		       result.valid = 1'b1;
		       result.insn = insn_i(p2, p1, {i[5], i[6]}, 3'b100, LOAD);
		    end
		  4'b001_?:
		    if (zcb) begin
		       result.valid = 1'b1;
		       result.insn = insn_i(p2, p1, {i[5], 1'b0},
			 {~i[6], 2'b01}, LOAD);
		    end
		  4'b010_?:
		    if (zcb) begin
		       result.valid = 1'b1;
		       result.insn = insn_s(p1, p2, {i[5], i[6]}, 3'b000, STORE);
		    end
		  4'b011_0:
		    if (zcb) begin
		       result.valid = 1'b1;
		       result.insn = insn_s(p1, p2, {i[5], 1'b0}, 3'b001, STORE);
		    end
		  default: begin end
		endcase
	     end
	     3'b101:
	       if (zcd) begin
		  result.valid = 1'b1;
		  result.insn = insn_s(p1, p2, {i[6:5], i[12:10], 3'b0},
		    3'b011, STORE_FP);
	       end
	     3'b110: begin
		result.valid = 1'b1;
		result.insn = insn_s(p1, p2, {i[5], i[12:10], i[6], 2'b0},
		  3'b010, STORE);
	     end
	     3'b111:
	       if (zcf) begin
		  result.valid = 1'b1;
		  result.insn = insn_s(p1, p2, {i[5], i[12:10], i[6], 2'b0},
		    3'b010, STORE_FP);
	       end
	   endcase

	   2'b01: unique casez (i[15:13])
	     3'b000: begin
		result.valid = 1'b1;
		result.insn = insn_i(r1, r1, {{6{ci_imm[5]}}, ci_imm},
		  3'b000, OP_IMM);
	     end
	     3'b?01: begin
		logic [11:0] imm;
		imm = {i[12], i[8], i[10:9], i[6], i[7], i[2],
		       i[11], i[5:3], 1'b0};
		result.valid = 1'b1;
		result.insn = insn_j({4'b0, ~i[15]}, {{9{imm[11]}}, imm});
	     end
	     3'b010: begin
		result.valid = 1'b1;
		result.insn = insn_i(r1, 5'd0, {{6{ci_imm[5]}}, ci_imm},
		  3'b000, OP_IMM);
	     end
	     3'b011:
	       if (r1 == 5'd2) begin
		  logic [9:0] imm;
		  imm = {i[12], i[4:3], i[5], i[2], i[6], 4'b0};
		  if (!strict || match_binutils || ci_imm) begin
		     result.valid = 1'b1;
		     result.insn = insn_i(5'd2, 5'd2, {{2{imm[9]}}, imm},
		       3'b000, OP_IMM);
		  end
	       end else if (!strict || ci_imm) begin
		  result.valid = 1'b1;
		  result.insn = insn_u(r1, {{14{ci_imm[5]}}, ci_imm}, LUI);
	       end
	     3'b100: casez ({i[12:10], i[6:5]})
	       5'b?_0?_??: begin
		  result.valid = 1'b1;
		  result.insn = insn_i(p1, p1, {1'b0, i[10], 4'b0,
		    {i[12], i[6:2]}}, 3'b101, OP_IMM);
	       end
	       5'b?_10_??: begin
		  result.valid = 1'b1;
		  result.insn = insn_i(p1, p1, {{6{ci_imm[5]}}, ci_imm},
		    3'b111, OP_IMM);
	       end
	       5'b0_11_00: begin
		  result.valid = 1'b1;
		  result.insn = insn_r(p1, p1, p2, 7'b0100000, 3'b000, OP);
	       end
	       5'b0_11_01: begin
		  result.valid = 1'b1;
		  result.insn = insn_r(p1, p1, p2, 7'b0000000, 3'b100, OP);
	       end
	       5'b0_11_10: begin
		  result.valid = 1'b1;
		  result.insn = insn_r(p1, p1, p2, 7'b0000000, 3'b110, OP);
	       end
	       5'b0_11_11: begin
		  result.valid = 1'b1;
		  result.insn = insn_r(p1, p1, p2, 7'b0000000, 3'b111, OP);
	       end
	       5'b1_11_10:
		 if (zcb && zmmul) begin
		    result.valid = 1'b1;
		    result.insn = insn_r(p1, p1, p2, 7'b0000001, 3'b000, OP);
		 end
	       5'b1_11_11:
		 if (zcb) unique casez (i[4:2])
		   3'b000: begin
		      result.valid = 1'b1;
		      result.insn = insn_i(p1, p1, 12'h0ff, 3'b111, OP_IMM);
		   end
		   3'b001:
		     if (zbb) begin
			result.valid = 1'b1;
			result.insn = insn_i(p1, p1, 12'b0110000_00100,
			  3'b001, OP_IMM);
		     end
		   3'b010:
		     if (zbb) begin
			result.valid = 1'b1;
			result.insn = insn_r(p1, p1, 5'd0, 7'b0000100,
			  3'b100, OP);
		     end
		   3'b011:
		     if (zbb) begin
			result.valid = 1'b1;
			result.insn = insn_i(p1, p1, 12'b0110000_00101,
			  3'b001, OP_IMM);
		     end
		   3'b101: begin
		      result.valid = 1'b1;
		      result.insn = insn_i(p1, p1, 12'hfff, 3'b100, OP_IMM);
		   end
		   default: begin end
		 endcase
	     endcase
	     3'b11?: begin
		result.valid = 1'b1;
		result.insn = insn_b(p1, 5'd0,
		  {{4{i[12]}}, i[12], i[6:5], i[2], i[11:10], i[4:3], 1'b0},
		  {2'b00, i[13]});
	     end
	   endcase

	   2'b10: unique case (i[15:13])
	     3'b000: begin
		result.valid = 1'b1;
		result.insn = insn_i(r1, r1, {6'b0, ci_imm}, 3'b001, OP_IMM);
	     end
	     3'b001:
	       if (zcd) begin
		  result.valid = 1'b1;
		  result.insn = insn_i(r1, 5'd2, {i[4:2], i[12], i[6:5], 3'b0},
		    3'b011, LOAD_FP);
	       end
	     3'b010:
	       if (!strict || r1) begin
		  result.valid = 1'b1;
		  result.insn = insn_i(r1, 5'd2, {i[3:2], i[12], i[6:4], 2'b0},
		    3'b010, LOAD);
	       end
	     3'b011:
	       if (zcd) begin
		  result.valid = 1'b1;
		  result.insn = insn_i(r1, 5'd2, {i[3:2], i[12], i[6:4], 2'b0},
		    3'b010, LOAD_FP);
	       end
	     3'b100:
	       if (!r2) begin
		  if (!r1) begin
		     if (!strict || i[12]) begin
			result.valid = 1'b1;
			result.insn = insn_i(5'd0, 5'd0, {11'b0, i[12]},
			  3'b000, SYSTEM);
		     end
		  end else begin
		     result.valid = 1'b1;
		     result.insn = insn_i({4'b0, i[12]}, r1, 12'b0,
		       3'b000, JALR);
		  end
	       end else begin
		  result.valid = 1'b1;
		  result.insn = insn_r(r1, r1 & {5{i[12]}}, r2, 7'b0,
		    3'b000, OP);
	       end
	     3'b101:
	       if (zcd) begin
		  result.valid = 1'b1;
		  result.insn = insn_s(5'd2, r2, {i[9:7], i[12:10], 3'b0},
		    3'b011, STORE_FP);
	       end
	     3'b110: begin
		result.valid = 1'b1;
		result.insn = insn_s(5'd2, r2, {i[8:7], i[12:9], 2'b0},
		  3'b010, STORE);
	     end
	     3'b111:
	       if (zcd) begin
		  result.valid = 1'b1;
		  result.insn = insn_s(5'd2, r2, {i[8:7], i[12:9], 2'b0},
		    3'b010, STORE_FP);
	       end
	   endcase
	 endcase
      end

      expand = result;
   endfunction

   task automatic check(
     input logic [15:0] code, input string name, input logic [31:0] actual,
     input bit enabled, input bit zcf, input bit zcd, input bit zcb,
     input bit zbb, input bit zmmul, input bit strict, input bit match_binutils,
     inout int errors
     );
      expected_t expected;

      expected = expand(d, enabled, zcf, zcd, zcb, zbb, zmmul, strict,
			match_binutils);
      if (expected.valid) begin
	 if (actual !== expected.insn) begin
	    $error("%s: %04x expanded to %08x, expected %08x",
	      name, code, actual, expected.insn);
	    errors++;
	 end
      end else if (actual[4:0] !== 5'b11111) begin
	 $error("%s: %04x should be invalid, got %08x", name, code, actual);
	 errors++;
      end
   endtask

   initial begin
      int errors;

      errors = 0;
      for (int code = 0; code < 65536; code++) begin
	 d = {16'ha5a5, code[15:0]};
	 #1ps;
	 check(code, "default", q_default, 1'b1, WITH_Zcf, WITH_Zcd,
	   WITH_Zcb, WITH_Zbb, WITH_Zmmul, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "disabled", q_disabled, 1'b0, WITH_Zcf, WITH_Zcd,
	   WITH_Zcb, WITH_Zbb, WITH_Zmmul, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "no-zcf", q_no_zcf, 1'b1, 1'b0, WITH_Zcd,
	   WITH_Zcb, WITH_Zbb, WITH_Zmmul, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "no-zcd", q_no_zcd, 1'b1, WITH_Zcf, 1'b0,
	   WITH_Zcb, WITH_Zbb, WITH_Zmmul, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "no-zcb", q_no_zcb, 1'b1, WITH_Zcf, WITH_Zcd,
	   1'b0, WITH_Zbb, WITH_Zmmul, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "no-zbb", q_no_zbb, 1'b1, WITH_Zcf, WITH_Zcd,
	   WITH_Zcb, 1'b0, WITH_Zmmul, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "no-zmmul", q_no_zmmul, 1'b1, WITH_Zcf, WITH_Zcd,
	   WITH_Zcb, WITH_Zbb, 1'b0, STRICT_UNDEFINED, 1'b0, errors);
	 check(code, "strict", q_strict, 1'b1, WITH_Zcf, WITH_Zcd,
	   WITH_Zcb, WITH_Zbb, WITH_Zmmul, 1'b1, 1'b0, errors);
	 check(code, "strict-binutils", q_strict_binutils, 1'b1, WITH_Zcf,
	   WITH_Zcd, WITH_Zcb, WITH_Zbb, WITH_Zmmul, 1'b1, 1'b1, errors);
      end

      if (errors)
	 $fatal(1, "rv32c exhaustive test found %0d errors", errors);
      $display("rv32c: checked all 65536 encodings in nine configurations");
      $finish;
   end
endmodule
