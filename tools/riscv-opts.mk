# Tuple name
riscv_tuple	:= riscv32-myriscv-none-elf

# Extra flags during tools build
# -menable-experimental-extensions needed for the Zilx extension
riscv_target_flags :=	-target riscv32-myriscv-none-elf -mcpu=myriscv \
			-menable-experimental-extensions \
			-O2 -glldb \
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
