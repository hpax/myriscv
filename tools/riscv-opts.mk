# Tuple name
riscv_tuple	:= riscv32-hpa-elf

# Canonical name for architecture
riscv_arch	:= rv32ibc_zalrsc_zicbom_ziccif_zicclsm_ziccrse_zicond_zicsr_zicntr_zifencei_zkr_zmmul_ztso
riscv_abi	:= ilp32

# Alternate architecture configurations (with divide, without multiply)
riscv_archlist	:= $(riscv_arch)-$(riscv_abi)-- \
	$(patsubst rv32%c,rv32%,$(riscv_arch))-$(riscv_abi)-- \
	rv32ibmc_zicsr_zicntr_ztso-ilp32-- \
	rv32ibm_zicsr_zicntr-ilp32-- \
	rv32imc_zicsr_zicntr-ilp32-- \
	rv32im_zicsr_zicntr-ilp32-- \
	rv32ic_zicsr_zicntr-ilp32-- \
	rv32i_zicsr_zicntr-ilp32--

riscv_multilib := $(shell echo '$(riscv_archlist)' | \
	sed -r -e 's/[[:space:]]+/;/g' -e 's/^;+//' -e 's/;+$$//')

# Extra flags during tools build
riscv_target_flags :=	-target riscv32-myriscv-none-elf -mcpu=myriscv \
			-O2 -glldb -mno-strict-align \
			-ftls-model=local-exec \
			-fno-pic -fno-pie \
			-fshort-enums -fshort-wchar \
			-ffunction-sections -fdata-sections \
			-fno-exceptions \
			-falign-functions=4 -falign-loops=4 \
			-fdirect-access-external-data

# Additional flags during application build
riscv_flags := $(riscv_target_flags) \
		-fwrapv -fno-strict-aliasing
