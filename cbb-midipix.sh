#!/bin/bash
TARGET=x86_64-nt64-midipix
ARCH=nt64
PREFIX=$HOME/midipix
WORKDIR=$HOME/temp
MAKEFLAGS="-j8"

BINUTILS=2.24.51
GCC=4.6.4
MUSL=1.1.7


try()
{
    "$@" || exit 1
}

fetch()
{
    try wget -N "$1"
}

fetch_git()
{
    if [[ -d "$1" ]]; then
        pushd "$1"
        try git pull
        popd
    else
        try git clone "$2" "$1"
    fi
}


# Start.

[[ ! -d "$WORKDIR" ]] && try mkdir -p "$WORKDIR"
pushd "$WORKDIR" || exit 1


# Set up environment.
export PATH="$PREFIX/bin:$PATH"


# Git clone what we need.
fetch_git portage      git://midipix.org/ports/portage
fetch_git cbb-gcc-$GCC git://midipix.org/cbb/cbb-gcc-$GCC
fetch_git mmglue       git://midipix.org/mmglue
fetch_git psxstub      git://midipix.org/psxstub
fetch_git lazy         git://midipix.org/lazy


# Binutils.
fetch ftp://sourceware.org/pub/binutils/snapshots/binutils-$BINUTILS.tar.bz2
[[ -d binutils-$BINUTILS ]] && try rm -rf binutils-$BINUTILS
try tar -xf binutils-$BINUTILS.tar.bz2

pushd binutils-$BINUTILS || exit 1
try patch -p1 < ../portage/binutils-$BINUTILS.midipix.patch
try ./configure --prefix="$PREFIX" --with-sysroot="$PREFIX/$TARGET" --target=$TARGET
try make $MAKEFLAGS
try make $MAKEFLAGS install
popd


# GCC, stage 1.
try mkdir -p "$PREFIX/$TARGET/include"
[[ ! -d "$PREFIX/$TARGET/usr" ]] && try ln -s . "$PREFIX/$TARGET/usr"
[[ -d cbb-gcc-$GCC-build ]] && try rm -rf cbb-gcc-$GCC-build
try mkdir cbb-gcc-$GCC-build

pushd cbb-gcc-$GCC-build || exit 1

GCCFLAGS="--include $(try readlink -f ../cbb-gcc-$GCC/libc/cbb-musl-pe.h)"
GCCTARGET_FLAGS="$FLAGS -DIN_TARGET_LIBRARY_BUILD --sysroot=$PREFIX/$TARGET"

export CFLAGS="$GCCFLAGS"
export CXXFLAGS="$GCCFLAGS"

export CFLAGS_FOR_BUILD="$GCCFLAGS"
export CPPFLAGS_FOR_BUILD="$GCCFLAGS"
export CXXFLAGS_FOR_BUILD="$GCCFLAGS"

export CFLAGS_FOR_TARGET="$GCCTARGET_FLAGS"
export XGCC_FLAGS_FOR_TARGET="$GCCTARGET_FLAGS"
export CPPFLAGS_FOR_TARGET="$GCCTARGET_FLAGS"
export CXXFLAGS_FOR_TARGET="$GCCTARGET_FLAGS"
export LIBCFLAGS_FOR_TARGET="$GCCTARGET_FLAGS"

cbb_target=$TARGET \
cbb_xgcc_for_specs=$(try readlink -f .)/gcc/xgcc \
cbb_ldflags_for_target="--sysroot=$PREFIX/$TARGET" \
cbb_sysroot_for_libgcc="$PREFIX/$TARGET" \
cbb_cflags_for_stage1="$CFLAGS_FOR_BUILD" \
cbb_cflags_for_stage2="$CFLAGS_FOR_BUILD" \
cbb_cflags_for_stage3="$CFLAGS_FOR_BUILD" \
cbb_cflags_for_stage4="$CFLAGS_FOR_BUILD" \
try ../cbb-gcc-$GCC/configure --prefix="$PREFIX" \
    --target=$TARGET \
    --disable-nls \
    --disable-multilib \
    --disable-libmudflap \
    --disable-obsolete \
    --disable-symvers \
    --disable-sjlj-exceptions \
    --with-fpmath=sse \
    --enable-multiarch \
    --enable-shared \
    --enable-initfini-array \
    --enable-threads=posix \
    --enable-lto \
    --enable-__cxa_atexit \
    --enable-gnu-indirect-function \
    --enable-gnu-unique-object \
    --enable-libstdcxx-debug \
    --enable-canonical-system-headers \
    --enable-languages=c,c++,objc,lto \
    --enable-secureplt \
    --with-sysroot="$PREFIX/$TARGET" \
    --enable-debug \
    --disable-bootstrap
try touch configure.skip

try make $MAKEFLAGS all-gcc
try make $MAKEFLAGS install-gcc

unset CFLAGS
unset CXXFLAGS
popd


# psxstub.
pushd psxstub || exit 1
DESTDIR="$PREFIX/$TARGET" try make $MAKEFLAGS install
unset DESTDIR
popd


# Musl.
fetch http://www.musl-libc.org/releases/musl-$MUSL.tar.gz
[[ -d musl-$MUSL ]] && try rm -rf musl-$MUSL
try tar -xf musl-$MUSL.tar.gz

pushd musl-$MUSL || exit 1
try cp -r ../mmglue/* .
popd

[[ -d musl-$MUSL-build ]] && try rm -r musl-$MUSL-build
try mkdir musl-$MUSL-build

pushd musl-$MUSL-build || exit 1
export lz_target=$TARGET
export lz_arch=$ARCH
export lz_cflags_debug="-O2"

try ../lazy/lazy \
    -x config \
    -t $lz_target \
    -c gcc \
    -n musl \
    -p ../musl-$MUSL \
    -f "$PREFIX/$TARGET"
try ./lazy \
    -x build \
    -e install_no_complex
popd


# GCC, compiler runtime.
pushd cbb-gcc-$GCC-build || exit 1
export CFLAGS="$GCCFLAGS"
export CXXFLAGS="$GCCFLAGS"

try make $MAKEFLAGS all-target-libgcc
try make $MAKEFLAGS install-target-libgcc

unset CFLAGS
unset CXXFLAGS
popd


# Musl, again.
pushd musl-$MUSL-build || exit 1
try ./lazy \
    -x build \
    -e install
popd


# GCC, everything else.
pushd cbb-gcc-$GCC-build || exit 1
export CFLAGS="$GCCFLAGS"
export CXXFLAGS="$GCCFLAGS"

try make $MAKEFLAGS all-target-libstdc++-v3
try make $MAKEFLAGS install-target-libstdc++-v3
try make $MAKEFLAGS
try make $MAKEFLAGS install

unset CFLAGS
unset CXXFLAGS
popd


echo "All done!"

