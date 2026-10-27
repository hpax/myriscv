MAKEFLAGS = -R -r

all: llvm

include riscv-opts.mk

llvm_config = \
	-DCMAKE_BUILD_TYPE='RelWithDebInfo' \
	-DCMAKE_INSTALL_PREFIX='$(shell pwd)' \
	-DLLVM_DEFAULT_TARGET_TRIPLE="$(riscv_tuple)" \
	-DLLVM_ENABLE_ASSERTIONS=ON \
	-DLLVM_ENABLE_PROJECTS='clang;lld' \
	-DLLVM_ENABLE_RUNTIMES='compiler-rt' \
	-DLLVM_TARGETS_TO_BUILD=RISCV \
	-DLLVM_BUILD_TOOLS=ON \
	-DLLVM_BUILD_TESTS=ON \
	-DCOMPILER_RT_BUILD_BUILTINS=ON \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
	-DCOMPILER_RT_BAREMETAL_BUILD=ON \
	-DRUNTIMES_builtin_COMPILER_FLAGS='$(riscv_flags)'

clean:
	rm -rf *.build *~ *.bak \#* .\#* *.deps *.stamp

spotless: clean
	rm -rf llvm

.PHONY: sources
sources:
	if [ -f ../.gitmodules ] && \
	   git submodule status --recursive | grep -q '^[+-]'; then \
		git submodule update --init --recursive ; \
		$(MAKE) spotless ; \
	fi

%.src: sources
	rm -f $*.build.stamp

.PHONY: llvm
llvm: llvm.build.stamp

llvm.build: llvm.src
	cmake -S llvm.src/llvm -B llvm $(llvm_config)
	cmake --build llvm
	: > llvm.stamp

# Note: the riscv-gnu-toolchain repo has bugs when building in
# parallel, so spoon feed it a sequence to avoid dependency problems.
%.build.stamp: | sources
	$(MAKE) $*.build

# Helper to dump some configuration variables
config:
	@printenv | grep '^riscv_' | sort
