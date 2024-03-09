module icache
#(
  parameter PC_MASK = 32'hffff_fffe;
  )
   (
    input rst_n,
    input clk,
    input clken,

    input [31:0] ibus_a,
    input ibus_valid,
    output [31:0] ibus_rdata,
    output ibus_ready
    );
