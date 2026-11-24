#!/usr/bin/env bash
# Compile the original source lists, without object or source substitutions.
set -euo pipefail
repo=$(pwd)
variant=${1:?before or after}
ref=5a56226230ed24fe75cca9806ac9526223aba7fc
[[ $variant == before ]] || ref=2d1eeee390f03aa2e104a3ff111c31c31a07561a
work="$RUNNER_TEMP/ds9-208-macos-$variant"
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
export DYLD_LIBRARY_PATH="$prefix/lib:${DYLD_LIBRARY_PATH:-}"
cd "$work/source/tk9.0/unix"
run_logged "$logs/tk.log" bash configure --prefix="$prefix" --with-tcl="$work/source/tcl9.0/unix" --enable-shared --enable-aqua
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
printf 'package\tconfigure_exit\tmake_exit\tobjects\n' > "$logs/results.tsv"
for package in vector fitsy tkblt tclfitsy tkmpeg tksao; do
    cd "$work/source/$package"
    configure_code=0
    env CC=clang CXX=clang++ bash configure --prefix="$prefix" \
        --with-tcl="$work/source/tcl9.0/unix" \
        --with-tk="$work/source/tk9.0/unix" --enable-shared --enable-stubs \
        > "$logs/$package-configure.log" 2>&1 || configure_code=$?
    code=99
    if [[ $configure_code == 0 ]]; then
        grep -E '^(CC|CXX|SHLIB_LD|MAKE_LIB|LIBS)[[:space:]]*=' Makefile > "$logs/$package-commands.log"
        code=0
        make -j4 binaries > "$logs/$package-build.log" 2>&1 || code=$?
        make install-libraries > "$logs/$package-install.log" 2>&1 || true
        for library in ./*.dylib; do
            [[ -f $library ]] || continue
            otool -L "$library" > "$logs/$package-dependencies.log"
            nm -u "$library" > "$logs/$package-undefined.log"
        done
    fi
    count=$(find . -name '*.o' | wc -l)
    printf '%s\t%s\t%s\t%s\n' "$package" "$configure_code" "$code" "$count" | tee -a "$logs/results.tsv"
done
sw_vers > "$logs/environment.txt"
clang++ --version >> "$logs/environment.txt"
echo 'Shared-source attempts recorded; results.tsv distinguishes successful builds from failures.'
