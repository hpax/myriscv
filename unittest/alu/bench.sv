// Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
`timescale 1 ns / 1 ps

`include "myriscv.vh"

//
// Test bench driver for the ALU test
//

module bench;
   parameter string infile  = "tests/add.in";
   parameter string outfile = "tests/add.out";

   reg rst_n;
   reg clk;

   decoded_insn_t e_op;
   reg [31:0] e_src1;
   reg [31:0] e_src2;
   reg	      starting;

   wire [31:0] m_dst;
   wire        m_cmp_out;
   wire	       m_valid;

   alutest dut (
     .rst_n    ( rst_n ),
     .clk      ( clk ),
     .e_op     ( e_op ),
     .e_src1   ( e_src1 ),
     .e_src2   ( e_src2 ),
     .m_dst    ( m_dst ),
     .m_cmp_out( m_cmp_out ),
     .m_valid  ( m_valid )
     );

   function logic [31:0] get_field(string s);
      logic [31:0] out;
      if (s == "") begin
	out = 32'b0;
      end else if ($sscanf(s, "0x%x", out)) begin
	 // OK
      end else if ($sscanf(s, "%b", out)) begin
	 // OK
      end else begin
	 out = 32'bx;
      end

      get_field = out;
   endfunction

   int fin;
   int fout;
   int line;
   
   initial begin
      clk 	  <= 1'b1;

      line         = 0;
      fin 	   = $fopen(infile, "r");
      if (!fin) $stop;
      fout         = $fopen(outfile, "w");
      if (!fout) $stop;

      rst_n 	  <= 1'b0;
      #10.5 rst_n <= 1'b1;
   end

   always #1 clk <= ~clk;

   always @(negedge clk) begin
      string itype;
      bit have_insn;

      if (!line || m_valid) begin
	 if (line) begin
	    #1ps;
	   $fdisplay(fout, " -> %x %b\n", m_dst, m_cmp_out);
	 end

	 have_insn = 1'b0;
	 while (!have_insn) begin
	    string txt, opfields, f7, f3, rs2;
	    int	   fields;
	    int    first_colon, second_colon;

	    if (!$fgets(txt, fin))
	      $finish;

	    line++;

	    e_op = 'bx;
	    fields = $sscanf(txt, "%s %s %x %x",
	      itype, opfields, e_src1, e_src2);

	    if (fields == 1 && itype == "q")
	      $finish;
	    
	    if (fields >= 1 && itype != "#" && itype != ";") begin
	       if (fields != 4)
		 $fatal(1, "Invalid test vector: %s", txt);

	       first_colon = -1;
	       second_colon = -1;
	       for (int i = 0; i < opfields.len(); i++) begin
		  if (opfields.getc(i) == ":") begin
		     if (first_colon < 0)
		       first_colon = i;
		     else
		       second_colon = i;
		  end
	       end

	       if (first_colon < 0 || second_colon < 0)
		 $fatal(1, "Invalid operation fields: %s", opfields);

	       f7 = opfields.substr(0, first_colon-1);
	       rs2 = opfields.substr(first_colon+1, second_colon-1);
	       f3 = opfields.substr(second_colon+1, opfields.len()-1);

	       e_op.funct7    = get_field(f7);
	       e_op.funct3    = get_field(f3);
	       e_op.rs2.r     = get_field(rs2);
	       e_op.rs2_valid = rs2 != "";	// Note rs2 == 0 is still valid
	       e_op.rs1.r     = 32'd31;		// Arbitrary
	       e_op.rs1_valid = 1'b1;
	       e_op.rd.r      = 32'd30;
	       e_op.rd_e      = 1'b1;
	       
	       if (itype.getc(1) == "i") begin
		  e_op.rs2_valid = 1'b0;
		  itype = {itype.getc(0)};
	       end

	       if (itype == "a" || itype == "x") begin
		  e_op.itype      = itype == "x" ? INSN_XALU : INSN_ALU;
		  if (!e_op.rs2_valid) begin
		     e_src2[4:0]  |= e_op.rs2.r;
		     e_op.rs2.r   = e_src2[4:0];
		     e_src2[11:5] |= e_op.funct7;
		     e_op.funct7  = e_src2[11:5];
		     e_src2 	  = $signed(e_src2[11:0]);
		     itype = {itype, "i"};
		  end
	       end else if (itype == "m") begin
		  e_op.itype 	  = INSN_MUL;
		  e_op.rs2_valid  = 1'b1;
	       end else if (itype == "j") begin
		  e_op.itype 	  = INSN_JAL;
		  e_op.rs1_valid  = 1'b0;
		  e_op.rs2_valid  = 1'b0;
		  e_src2 	  = $signed({e_src2[19:1], 1'b0});
	       end else if (itype == "jr") begin
		  e_op.itype 	  = INSN_JAL;
		  e_op.rs2_valid  = 1'b0;
	       end else if (itype == "b") begin
		  e_op.itype 	  = INSN_BR;
		  e_op.rs2_valid  = 1'b1;
		  e_op.rd_e       = 1'b0;
		  e_src2 	  = $signed({e_src2[12:1], 1'b0});
	       end else begin
		  $stop;
	       end

	       $fwrite("%8d: %-2s %b:%b:%b %x %x -> ",
		 line, itype, e_op.funct7, e_op.rs2.r, e_op.funct3,
		 e_src1, e_src2);

	       have_insn = 1'b1;
	    end
	 end
      end
   end
endmodule

      
	    
	       
