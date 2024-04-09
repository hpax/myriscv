#!/bin/bash -xe

srcdir=gnusrc
dstdir=gnu.riscv.build
prefix="$(pwd)/gnu"

MAKE="${MAKE:-make}"

make_flags="${gnu_makeflags}"
if [ -z "$make_flags" ]; then make_flags="$MAKEFLAGS"; fi
MAKEFLAGS="$make_flags"
export MAKEFLAGS

declare -A xconfig
xconfig['binutils']="$riscv_binutils_configargs"
xconfig['gcc0']="$riscv_gcc_configargs"
xconfig['gcc']="$riscv_gcc_configargs"
xconfig['newlib']="$riscv_newlib_configargs"

declare -A build
build['gcc']=all-gcc

declare -A install
install['gcc']=install-gcc

PATH="$prefix/bin:$PATH"
export PATH

built_something=false
for tool in binutils gcc newlib; do
    toolsrc="$srcdir"/"$tool"
    tooldst="$dstdir"/"$tool"
    mkdir -p "$tooldst"
    dsthead=$(cat "$tooldst"/HEAD 2>/dev/null || true)
    srchead=$(cd "$toolsrc" && git rev-parse HEAD)
    if [ x$dsthead != x$srchead ]; then
	cd "$tooldst"
	if [ ! -f ./config.status ] ||
	   [ ./config.status -ot ../../"$toolsrc"/configure ]; then
	    ../../"$toolsrc"/configure \
		 $riscv_config ${xconfig[$tool]} \
		 CFLAGS_FOR_TARGET="$riscv_target_flags" \
		 CXXFLAGS_FOR_TARGET="$riscv_target_flags"
	fi
	$MAKE ${build[$tool]}
	$MAKE ${install[$tool]:-install}
	echo "$srchead" > HEAD
	built_something=true
	cd ../..
    fi
done

# Additional gcc stuff after newlib build
if $built_something; then
    tool=gcc
    toolsrc="$srcdir"/"$tool"
    tooldst="$dstdir"/"$tool"

    cd "$tooldst"
    $MAKE
    $MAKE install
    cd ../..
fi
