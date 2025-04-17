MAKEFLAGS = -R -r

prefix   := $(CURDIR)/gnu
bindir   := $(prefix)/bin
acprefix := $(prefix)/autoconf
acbindir := $(acprefix)/bin

tooldir   = gnusrc
binutils  = $(tooldir)/binutils

ac_config  = --prefix=$(acprefix)
all_config = --prefix=$(prefix)

all: gnu

include riscv-opts.mk
export riscv_target_flags

riscv_config = $(all_config) \
	   --target=$(riscv_tuple) \
	   --enable-languages=c,c++ \
	   --with-arch=$(riscv_arch) --with-abi=ilp32 \
	   --with-newlib \
	   --with-sysroot=$(prefix)/$(riscv_tuple) \
	   --disable-shared --disable-threads \
	   --disable-libmudflap --disable-libssp \
	   --disable-libquadmath --disable-libgomp --disable-nls \
	   --disable-tm-clone-registry \
	   --enable-multilib --with-multilib-generator=$(riscv_multilib)
export riscv_config

riscv_binutils_configargs := \
	--disable-gold --disable-gprof --disable-sim
export riscv_binutils_configargs

pathify       = PATH='$(bindir):$(acbindir):$(PATH)'
# -R -r fails, and one can't disable it, so strip all of MAKEFLAGS
# except any job-related options. Sigh.
gnu_makeflags = MAKEFLAGS=' $(filter -j% --job%,$(MAKEFLAGS))'
rsetup        = $(pathify) $(gnu_makeflags)
RMAKE	      = $(rsetup) $(MAKE)

riscv_newlib_configargs := \
	--disable-newlib-fseek-optimization \
	--disable-newlib-fvwrite-in-streamio \
	--disable-newlib-mb \
	--disable-newlib-multithread \
	--disable-newlib-reent-check-verify \
	--disable-newlib-register-fini \
	--disable-newlib-supplied-syscalls \
	--disable-newlib-unbuf-stream-opt \
	--disable-newlib-wide-orient \
	--enable-lite-exit \
	--enable-newlib-global-atexit \
	--enable-newlib-nano-formatted-io \
	--enable-newlib-io-c99-formats \
	--enable-newlib-nano-malloc \
	--enable-newlib-reent-small
export riscv_newlib_configargs

clean:
	rm -rf *.build *~ *.bak \#* .\#* *.deps *.stamp

spotless: clean
	rm -rf gnu

.PHONY: gnu.src
gnu.src:
	if [ -f ../.gitmodules ] && \
	   git submodule status --recursive | grep -q '^[+-]'; then \
		git submodule update --init --recursive ; \
		rm -rf gnu gnu.*.stamp ; \
	fi

.PHONY: gnu
gnu:
	$(MAKE) gnu.src
	$(MAKE) autotools
	$(MAKE) gnu.bin

.PHONY: gnu.bin
gnu.bin: gnu.riscv.build

# At least binutils is really picky about which version of autoconf
# and aclocal (automake) it uses, so build it explicitly
autoconf-ver := 2.69
automake-ver := 1.15.1

autoconf = autoconf-$(autoconf-ver)
automake = automake-$(automake-ver)

# Don't require these tools for autotools
autotools-disable = EMACS=no GIT=no MAKEINFO=:

.PHONY: autotools
autotools: gnu.autotools.build.stamp

.PHONY: gnu.autotools.build
gnu.autotools.build:
	mkdir -p $@
	cd $@ && tar xvvf ../gnusrc/$(autoconf).tar.xz
	cd $@/$(autoconf) && \
		$(rsetup) $(autotools-disable) ./configure $(ac_config)
	$(RMAKE) -C $@/$(autoconf)
	$(RMAKE) -C $@/$(autoconf) install
	cd $@ && tar xvvf ../gnusrc/$(automake).tar.xz
	cd $@/$(automake) && \
		$(rsetup) $(autotools-disable) ./configure $(ac_config)
	$(RMAKE) -C $@/$(automake)
	$(RMAKE) -C $@/$(automake) install
	: >$@.stamp

# Note: the riscv-gnu-toolchain repo has bugs when building in
# parallel, so spoon feed it a sequence to avoid dependency problems.
%.build.stamp:
	$(MAKE) $*.build

.PHONY: gnu.riscv.build
gnu.riscv.build: autotools
	$(rsetup) MAKE='$(MAKE)' ./riscvbuild.sh

# Helper to dump some configuration variables
config:
	@printenv | grep '^riscv_' | sort
