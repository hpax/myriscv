//
// List of parameters with their defaults.
// This list is preprocessed to generate the top-level
// parameter list and a forwarding macro.
//

int		CONTEXTS		    = 1;
int		context_bits		    = $clog2(CONTEXTS);
int		register_bits		    = context_bits + 5;

bit		WITH_Zba		    = 1'b1;
bit		WITH_Zcf		    = 1'b1;
bit		WITH_Zcd		    = 1'b1;
bit		WITH_Zbb		    = 1'b1;
bit		WITH_Zmmul		    = 1'b1;
bit		WITH_Zicond		    = 1'b1;
bit		WITH_minmax		    = 1'b1;
bit		WITH_extensions		    = 1'b1;
bit		STRICT_INVALID		    = 1'b0;

bit		TRAP_BADINSN		    = 1'b1;
bit		TRAP_BADALU		    = 1'b1;
int		IRQ_VECTORS		    = 31;
int		IRQ_VECTOR_BITS		    = $clog2(IRQ_VECTORS+1);

int		CTR_TIME_WIDTH		    = 40;
int		CTR_CYCLE_WIDTH		    = 40;
int		CTR_INSTRET_WIDTH	    = 40;

logic [31:0]	tcm_base		    = 32'h0;
logic [31:0]	tcm_mask		    = 32'h0000_1fff;
logic [31:0]	ram_base		    = 32'h4000_0000;
logic [31:0]	ram_mask		    = 32'h01ff_ffff;

logic [31:0]	PC_MASK			    = tcm_base|tcm_mask|ram_base|ram_mask;
logic [31:0]	RESET_PC		    = tcm_base | 32'h10;

logic [31:0]	MTVEC_RESET		    = (RESET_PC + (~32'b11 << IRQ_VECTOR_BITS)) & (~32'b11 << IRQ_VECTOR_BITS);
logic [31:0]	MTVEC_WMASK		    = 32'h0;
