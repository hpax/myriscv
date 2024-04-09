# Tuple name
riscv_tuple	:= riscv32-hpa-elf

# Canonical name for architecture
riscv_arch	:= rv32ic_zba_zbb_zbs_zicbom_zicond_zicsr_zifencei_zmmul
riscv_abi	:= ilp32

# Alternate architecture configurations (with divide, without multiply)
riscv_archlist	:= $(riscv_arch)-$(riscv-abi)-- \
	rv32imc_zba_zbb_zbs_zicbom_zicond_zicsr_zifencei-ilp32-- \
	rv32ic_zba_zbb_zbs_zicbom_zicond_zicsr_zifencei-ilp32--

riscv_multilib := $(patsubst \ ,;,$(strip $(riscv_archlist)))

# Extra flags during tools build
riscv_target_flags :=	-O2 -ggdb3 -fvisibility=hidden \
			-mno-strict-align -mbranch-cost=2 \
			-ftls-model=local-exec \
			-fno-pic -Wa,-fno-pic -fno-PIE \
			-frename-registers -fshort-enums -fshort-wchar \
			-ffunction-sections -fdata-sections \
			-mshorten-memrefs -fno-exceptions \
			-malign-data=natural -falign-functions=4 \

# Additional flags during application build
riscv_flags := $(riscv_target_flags) \
			 -march=$(riscv_arch) -fwrapv -fno-strict-aliasing
