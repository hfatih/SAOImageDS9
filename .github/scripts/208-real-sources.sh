#!/usr/bin/env bash
# Compile the original source lists, without object or source substitutions.
set -euo pipefail
repo=$(pwd)
variant=${1:?before or after}
ref=5a56226230ed24fe75cca9806ac9526223aba7fc
[[ $variant == before ]] || ref=2d1eeee390f03aa2e104a3ff111c31c31a07561a
work="$RUNNER_TEMP/ds9-208-real-$variant"
prefix="$work/install"
mkdir -p "$work/source" "$prefix/include" "$work/logs"
logs="$work/logs"
run_logged() {
    local log=$1
    shift
    if "$@" >> "$log" 2>&1; then return 0; else
        local code=$?
        tail -n 80 "$log"
        return "$code"
    fi
}
git archive "$ref" tcl9.0 tk9.0 tclconfig ast funtools vector fitsy tkblt tclfitsy tkmpeg tksao |
    tar -x -C "$work/source"
cd "$work/source/tcl9.0/unix"
run_logged "$logs/tcl.log" bash configure --prefix="$prefix" --enable-shared
run_logged "$logs/tcl.log" make -j4 binaries
run_logged "$logs/tcl.log" make install-binaries install-libraries install-headers
export LD_LIBRARY_PATH="$prefix/lib:${LD_LIBRARY_PATH:-}"
cd "$work/source/tk9.0/unix"
run_logged "$logs/tk.log" bash configure --prefix="$prefix" --with-tcl="$work/source/tcl9.0/unix" --enable-shared
run_logged "$logs/tk.log" make -j4 binaries
run_logged "$logs/tk.log" make install-binaries install-libraries install-headers
cd "$work/source/ast"
run_logged "$logs/ast-headers.log" bash configure --prefix="$prefix" \
    --without-pthreads --enable-shared=no CPPFLAGS='-std=gnu99 -w' \
    star_cv_cnf_trail_type=long star_cv_cnf_f2c_compatible=no
run_logged "$logs/ast-headers.log" make -o configure -o aclocal.m4 -o Makefile.in ast.h
cp ast.h src/grf.h src/grf3d.h "$prefix/include/"
# fitsy/hist.C uses the actual configured Funtools public headers.
cd "$work/source/funtools"
run_logged "$logs/funtools-headers.log" bash configure --prefix="$prefix" --disable-shared CFLAGS='-g -O2 -std=gnu90 -w'
cp funtools.h "$prefix/include/"
for directory in wcs filter util fitsy; do
    cp "$directory"/*.h "$prefix/include/"
done
for package in vector fitsy tkblt tclfitsy tkmpeg tksao; do
    cd "$work/source/$package"
    run_logged "$logs/$package-configure.log" env CC=gcc CXX=g++ bash configure \
        --prefix="$prefix" --with-tcl="$work/source/tcl9.0/unix" \
        --with-tk="$work/source/tk9.0/unix" --enable-shared --enable-stubs
    run_logged "$logs/$package-build.log" make -j4 binaries
    run_logged "$logs/$package-headers.log" make install-libraries
done
cd "$repo"
python3 .github/scripts/analyze-shared-sources.py "$work" "$variant" "$ref"
