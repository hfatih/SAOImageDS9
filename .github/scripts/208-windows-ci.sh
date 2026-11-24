#!/usr/bin/env bash
# Native Windows/MinGW attempt: keep real configure files and source lists.
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
repo=$(pwd)
work=$(cygpath -u "$RUNNER_TEMP")/ds9-208-windows
prefix="$work/install"
mkdir -p "$work/deps" "$prefix/include" "$work/logs"
logs="$work/logs"
run_logged() {
    local log=$1
    shift
    if "$@" >> "$log" 2>&1; then return 0; else
        local code=$?
        tail -n 60 "$log"
        return "$code"
    fi
}
git -C "$repo" archive 5a56226230ed24fe75cca9806ac9526223aba7fc tcl9.0 tk9.0 tclconfig ast funtools |
    tar -x -C "$work/deps"
cd "$work/deps/tcl9.0/win"
run_logged "$logs/tcl.log" bash configure --prefix="$prefix" --enable-64bit --enable-shared
run_logged "$logs/tcl.log" make -j4 binaries
run_logged "$logs/tcl.log" make install-binaries
run_logged "$logs/tcl.log" make install-libraries install-headers TCL_EXE="$prefix/bin/tclsh90.exe"
export PATH="$prefix/bin:/usr/x86_64-w64-mingw32/sys-root/mingw/bin:$PATH"
cd "$work/deps/tk9.0/win"
run_logged "$logs/tk.log" bash configure --prefix="$prefix" \
    --with-tcl="$work/deps/tcl9.0/win" --enable-64bit --enable-shared
run_logged "$logs/tk.log" make -j4 binaries
run_logged "$logs/tk.log" make install-binaries install-libraries
cd "$work/deps/ast"
run_logged "$logs/ast-headers.log" bash configure --prefix="$prefix" \
    --without-pthreads --enable-shared=no CPPFLAGS='-std=gnu99 -w' \
    star_cv_cnf_trail_type=long star_cv_cnf_f2c_compatible=no
run_logged "$logs/ast-headers.log" make -o configure -o aclocal.m4 -o Makefile.in ast.h
cp ast.h src/grf.h src/grf3d.h "$prefix/include/"
cd "$work/deps/funtools"
run_logged "$logs/funtools-headers.log" bash configure --prefix="$prefix" --host=x86_64-w64-mingw32 --disable-shared CC=x86_64-w64-mingw32-gcc CFLAGS='-g -O2 -std=gnu90 -w'
cp funtools.h "$prefix/include/"
for directory in wcs filter util fitsy; do
    cp "$directory"/*.h "$prefix/include/"
done
printf 'variant\tpackage\tmake_exit\texpected_objects\tbuilt_objects\n' > "$logs/results.tsv"
for variant in before after; do
    ref=5a56226230ed24fe75cca9806ac9526223aba7fc
    [[ $variant == before ]] || ref=2d1eeee390f03aa2e104a3ff111c31c31a07561a
    source_dir="$work/$variant"
    mkdir -p "$source_dir"
    git -C "$repo" archive "$ref" vector fitsy tkblt tclfitsy tkmpeg tksao tclconfig |
        tar -x -C "$source_dir"
    cp "$source_dir"/fitsy/*.h "$source_dir"/vector/*.h \
        "$source_dir/tkblt/generic/tkbltVector.h" "$source_dir/tkblt/generic/tkbltDecls.h" \
        "$prefix/include/"
    for package in vector fitsy tkblt tclfitsy tkmpeg tksao; do
        cd "$source_dir/$package"
        extra=()
        if [[ $package == tksao ]]; then
            extra=(--with-xml2-config=/usr/x86_64-w64-mingw32/sys-root/mingw/bin/xml2-config)
        fi
        run_logged "$logs/$variant-$package-configure.log" env TEA_PLATFORM=windows \
            bash configure --prefix="$prefix" --with-tcl="$work/deps/tcl9.0/win" \
            --with-tk="$work/deps/tk9.0/win" --enable-64bit --enable-shared --enable-stubs "${extra[@]}"
        grep -E '^(CC|CXX|SHLIB_LD|MAKE_LIB|LIBS)[[:space:]]*=' Makefile \
            > "$logs/$variant-$package-commands.log"
        # Source files are unchanged by the fix. Reuse the exact compiled objects
        # for the after-link, preserving identical compiler inputs and bytes.
        if [[ $variant == after ]]; then
            while IFS= read -r -d '' object; do
                relative=${object#"$work/before/$package/"}
                mkdir -p "$(dirname "$relative")"
                cp -p "$object" "$relative"
                cmp -s "$object" "$relative"
            done < <(find "$work/before/$package" -name '*.o' -print0)
        fi
        code=0
        make -j4 binaries > "$logs/$variant-$package-build.log" 2>&1 || code=$?
        expected=$(make -s --eval='print-objects: ; @echo $(PKG_OBJECTS)' print-objects | wc -w)
        built=$(find . -name '*.o' | wc -l)
        find . -name '*.o' -print0 | sort -z | xargs -0 -r sha256sum \
            > "$logs/$variant-$package-objects.sha256"
        printf '%s\t%s\t%s\t%s\t%s\n' "$variant" "$package" "$code" "$expected" "$built" |
            tee -a "$logs/results.tsv"
        while IFS= read -r -d '' dll; do
            x86_64-w64-mingw32-objdump -p "$dll" > "$logs/$variant-$package-dll.log"
        done < <(find . -maxdepth 1 -name '*.dll' -print0)
    done
done
uname -a > "$logs/environment.txt"
x86_64-w64-mingw32-gcc --version >> "$logs/environment.txt"
echo 'Windows source/link attempts recorded; nonzero link results are evidence, not successful shared-stack builds.'
