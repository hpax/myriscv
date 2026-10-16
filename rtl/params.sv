//
// Global parameters and their default values
//
// This is processed by params.pl to generate params.vh
//

parameter bit WITH_RVC			   = 1'b1; // A.k.a C/Zca
parameter bit WITH_Zba			   = 1'b1;
parameter bit WITH_Zbb			   = 1'b1;
parameter bit WITH_Zbs			   = 1'b1;
parameter bit WITH_Zcf			   = 1'b1;
parameter bit WITH_Zcb			   = 1'b1;
parameter bit WITH_Zcd			   = 1'b1;
parameter bit WITH_bitcnt		   = 1'b1; // clz, ctz, cpop
parameter bit WITH_bitcntinv		   = 1'b0; // bit-inverted bitcnt ops
parameter bit WITH_extr         	   = 1'b1; // bitfield extraction
parameter bit WITH_shiftone     	   = 1'b1; // shift left/right one
parameter bit WITH_extn			   = 1'b1; // arbitrary sign/zero extend
parameter bit WITH_Zmmul		   = 1'b1;
parameter bit WITH_Zicond		   = 1'b1;
parameter bit WITH_minmax		   = 1'b1;
parameter bit WITH_cmpand       	   = 1'b1; // baeqz, banez
parameter bit WITH_setext		   = 1'b0; // addtional SET operations
parameter bit WITH_Zbasub		   = 1'b1; // shXsub
parameter bit WITH_Zkr			   = 1'b1; // seed CSR (needs external bit source)
parameter bit WITH_Zalrsc		   = 1'b1; // LR/SC instructions
parameter bit WITH_Ziccrse		   = 1'b1; // LR/SC guarantee forward progress
parameter bit WITH_indcsr		   = 1'b0; // Indirect CSR access
parameter bit WITH_regcsr       	   = 1'b1; // Register file CSR access
parameter bit WITH_waitfor      	   = 1'b1; // waitfor CSR
parameter bit WITH_mstatus		   = 1'b0; // mstatus CSR as a window into CIE
parameter bit WITH_sys_context  	   = 1'b1; // sys_context CSR
parameter bit WITH_ncontexts		   = 1'b0; // ncontexts CSR

parameter bit STRICT_UNDEFINED		   = 1'b0; // Strict opcode checking
parameter bit TRAP_BADINSN		   = 1'b1;
parameter bit TRAP_BADALU		   = 1'b1;
parameter bit TRAP_BADPC		   = 1'b1;

// If Zkr_secure is set, the entropy register is not visible unless
// the status field in the SEED CSR is set to ES16. If this is set to 0,
// this masking is not performed (reduces area cost.)
parameter bit Zkr_secure        	   = 1'b1;

// Width of the random number pool (architecturally compliant value 16)
parameter int Zkr_bits          	   = 16;

// For the Ziccrse instruction, this sets the size as a power of 2 of the
// maximum constrained instruction sequence. Interrupts are locked out
// until this number of instructions have retired. If this is 0, interrupts
// are locked out indefinely until the reservation is released.
parameter int Ziccrse_bits      	   = 4;	   // Standard architectural value

parameter logic [31:0] RESET_PC		   = 32'h0000_0010;

// Interrupts
parameter int	       NUM_IRQS		   = 31;
parameter int	       IRQ_BITS		   = $clog2(NUM_IRQS+1);

// Set this to 0 for non-vectored interrupts (interrupts and
// exceptions all share a single vector.) Set to 2 for architectually
// vectored interrupts (4 byte spacing.)
parameter int	       IRQ_VECTOR_BITS 	   = 2;

// MTVEC initialization and writability. For convenience separate
// parameters are made available for the reset values of the mode and
// addr fields, but they can be overridden by setting MTVEC_RESET
// explicitly.
//
// If vectoring is enabled, to reduce logic, the address fields of
// MTVEC_RESET and MTVEC_WMASK should be a multiple of
// 1 << (IRQ_VECTOR_BITS+IRQ_BITS).
parameter logic [31:0] MTVEC_WMASK	   = 32'h0;
parameter logic [1:0]  MTVEC_MODE_RESET    = { 1'b0, IRQ_VECTOR_BITS && ~MTVEC_WMASK[0] };
parameter logic [31:0] MTVEC_ADDR_RESET    = 32'h0000_0080;
parameter logic [31:0] MTVEC_RESET         = MTVEC_ADDR_RESET | MTVEC_MODE_RESET;

// These can be set to any width from 0 (no counter) to 64 (full
// architectural counter width.) If CTR_TIME_WIDTH is zero, the
// ctr_time port becomes an input port. If CTR_CYCLE_WIDTH is zero,
// ctr_cycle is set to equal ctr_time.
parameter int	     CTR_TIME_WIDTH	   = 40;
parameter int	     CTR_CYCLE_WIDTH	   =  0;
parameter int	     CTR_INSTRET_WIDTH	   = 40;

// Enable (report nonzero) in the misa CSR
parameter bit             WITH_misa 	   = 1'b0;

// These values are reflected (readonly) into the corresponding CSRs;
// this does add some logic burden if nonzero.
parameter logic [31:0]    csrval_vendorid  = 32'h0;
parameter logic [31:0]    csrval_archid    = 32'h0;
parameter logic [31:0]    csrval_impid     = 32'h0;

// Parameterization for timing tweaks
parameter bit	     ALU_EARLY_DECODE      = 1'b0;
parameter bit	     EARLY_RVC		   = 1'b1;
parameter bit	     BITCNT_SEPARATE	   = 1'b1;
parameter bit	     EARLY_BYPASS_MUX	   = 1'b0;

// Allow prediction of AUIPC+J(AL)R, LUI+J(AL)R or J(AL)R imm(zero)
parameter bit	     PREDICT_JALR	   = 1'b0;

// Allow cached multiply forwarding for latency
parameter bit	     FORWARD_MUL	   = 1'b1;

// This allows a c.nop inserted for padding to be
// fused with a previous c.xxx instruction into a
// pseudo-32-bit instruction.
parameter bit	     FUSE_CNOP		   = 1'b0;

//
// The base addresses and the size bits do not need to agree,
// however, the address reported to the output bus is always
// the low bits of the CPU address; so if the base is not a
// multiple of the size the address window will be shifted.
//
// It is required that tcm_base 	  <= ram_base < io_base.
// Memory references below tcm_base will pulse the buserr output;
// this can be used to trap NULL pointer references.
//
// Note that non-power-of-2 bases or small base values may
// end up generating slower memory logic, which could
// negatively affect fMAX.
//
parameter logic [31:0] tcm_base		   = 32'h0000_0000;
parameter int	     tcm_size_bits	   = 14;
parameter logic [31:0] ram_base		   = 32'h4000_0000;
parameter int	     ram_size_bits	   = 25;
parameter logic [31:0] io_base		   = 32'h8000_0000;

// What reading from a nonexistent memory spaces returns
parameter logic [31:0] INVALID_DATA	   = 32'h0000_0000;

// Number of supported register contexts; min 2, max 32
// In the future, more than one system context may be supported,
// e.g. NMI and debug mode. That will increase CTX_MIN_USER,
// and thus the number of available context.
parameter int CONTEXTS		      	   = 8;
parameter logic [4:0] CTX_MASK        	   = (1'b1 << $clog2(CONTEXTS)) - 1'b1;
parameter logic [4:0] CTX_MACHINE     	   = 5'd0;
parameter logic [4:0] CTX_MIN_USER    	   = 5'd1;
parameter logic [4:0] CTX_X           	   = 5'bx & CTX_MASK;

// These are not currently implemented and must not be set
parameter bit WITH_div			   = 1'b0; // Divide instructions
parameter bit WITH_Zaamo        	   = 1'b0; // AMO instructions

// Valid PC values - should really be computed from tcm_base, tcm_size_bits
// ram_base and ram_base_bits... need to figure out how to do that correctly
// in all cases...
parameter logic [31:0] PC_MASK		   = (addr_mask(tcm_base,tcm_size_bits)|addr_mask(ram_base,ram_size_bits)) & ~(WITH_RVC ? 2'b01 : 2'b11);

// Set this bit if and only if the register file implementation guarantees
// that a read of register x0 (in any context) will return zero from reset.
// This register is guaranteed to never be written. See rtl/regfile.sv.
// It is not required that other registers be initialized.
parameter bit REGFILE_ZERO_INIT 	   = 1'b1;

// Set this bit to put the context in the LSB of the register file
// address (the default is to put the register number in the LSB.)
parameter bit REGFILE_CONTEXT_LSB	   = 1'b0;

// Filename for TCM initialization file, if applicable
parameter string TCM_INIT_FILE		   = "";
