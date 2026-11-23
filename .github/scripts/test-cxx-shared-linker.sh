#!/usr/bin/env bash
# Build real TEA recipes and load their C++ output into a plain Tcl process.
set -euo pipefail

repo=$(cd "${1:-.}" && pwd)
base=${DS9_BASE_REF:-5a56226230ed24fe75cca9806ac9526223aba7fc}
fixed=${DS9_FIXED_REF:-HEAD}
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/ds9-208.XXXXXX")
logs="$work/logs"
prefix="$work/install"
mkdir -p "$logs" "$work/tcl" "$work/tk"
printf 'Work directory: %s\nBase: %s\nFixed: %s\n' "$work" "$base" "$fixed"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf 'work=%s\n' "$work" >> "$GITHUB_OUTPUT"
fi

run_logged() {
    local log=$1
    shift
    if "$@" >> "$log" 2>&1; then
        return 0
    else
        local status=$?
        tail -n 80 "$log"
        return "$status"
    fi
}

echo 'Building bundled Tcl/Tk 9 with their checked-in configure scripts'
cd "$work/tcl"
run_logged "$logs/tcl-configure.log" bash "$repo/tcl9.0/unix/configure" --prefix="$prefix" --enable-shared
run_logged "$logs/tcl-build.log" make -j2 binaries
run_logged "$logs/tcl-install.log" make install-binaries install-libraries install-headers
export LD_LIBRARY_PATH="$prefix/lib:${LD_LIBRARY_PATH:-}"
cd "$work/tk"
run_logged "$logs/tk-configure.log" bash "$repo/tk9.0/unix/configure" --prefix="$prefix" --with-tcl="$work/tcl" --enable-shared
run_logged "$logs/tk-build.log" make -j2 binaries
run_logged "$logs/tk-install.log" make install-binaries install-libraries install-headers
tclsh="$prefix/bin/tclsh9.0"
"$tclsh" <<'TCL'
puts "Bundled Tcl: [info patchlevel]"
TCL

cat > "$work/runtimeprobe.C" <<'CPP'
#include <tcl.h>
#include <sstream>
#include <string>

static int RuntimeCmd(ClientData, Tcl_Interp* interp, int, const char*[]) {
    std::ostringstream output;
    output << std::string("C++ runtime ready");
    const std::string value = output.str();
    Tcl_SetObjResult(interp, Tcl_NewStringObj(value.c_str(), -1));
    return TCL_OK;
}

extern "C" int Runtimeprobe_Init(Tcl_Interp* interp) {
    if (!Tcl_InitStubs(interp, TCL_PATCH_LEVEL, 0)) return TCL_ERROR;
    Tcl_CreateCommand(interp, "runtimeprobe", RuntimeCmd, nullptr, nullptr);
    return Tcl_PkgProvide(interp, "runtimeprobe", "1.0");
}
CPP
cat > "$work/load.tcl" <<'TCL'
load [lindex $argv 0] Runtimeprobe
if {[runtimeprobe] ne "C++ runtime ready"} { error "Wrong C++ result" }
if {[package require runtimeprobe] ne "1.0"} { error "Wrong package version" }
puts "C++ extension loaded and ran successfully"
TCL
cat > "$work/cprobe.c" <<'C'
/* The C++ compiler rejects this valid C identifier. */
int c_probe(void) { int class = 208; return class; }
C

packages=(fitsy vector tkblt tclfitsy tkmpeg tksao)
printf 'variant\tpackage\tload\n' > "$logs/results.tsv"
for variant in before after; do
    ref=$base
    [[ $variant == after ]] && ref=$fixed
    source_dir="$work/$variant/source"
    mkdir -p "$source_dir"
    git -C "$repo" archive "$ref" -- "${packages[@]}" tclconfig | tar -x -C "$source_dir"
    for package in "${packages[@]}"; do
        build="$work/$variant/$package"
        mkdir -p "$build"
        cd "$build"
        log="$logs/$variant-$package.log"
        run_logged "$log" env CC=gcc CXX=g++ bash "$source_dir/$package/configure" \
            --prefix="$prefix" --with-tcl="$work/tcl" --with-tk="$work/tk" --enable-shared
        grep -E '^(CC|CXX|SHLIB_LD|MAKE_LIB|LIBS)[[:space:]]*=' Makefile >> "$log"
        cp "$work/runtimeprobe.C" "$work/cprobe.c" .
        # Use the package's real compile and shared-library link targets.
        run_logged "$log" make cprobe.o
        run_logged "$log" make PKG_OBJECTS=runtimeprobe.o PKG_LIB_FILE=runtimeprobe.so RANLIB=: runtimeprobe.so
        readelf -d runtimeprobe.so >> "$log"
        if "$tclsh" "$work/load.tcl" "$build/runtimeprobe.so" > "$build/load.log" 2>&1; then
            outcome=pass
        else
            outcome=fail
        fi
        cat "$build/load.log" >> "$log"
        printf '%s\t%s\t%s\n' "$variant" "$package" "$outcome" | tee -a "$logs/results.tsv"
        if [[ $variant == before && $package == tclfitsy ]]; then
            [[ $outcome == fail ]]
            grep -Eq 'undefined symbol:.*(_Z|__gxx)' "$build/load.log"
        elif [[ $variant == after ]]; then
            [[ $outcome == pass ]]
            grep -Eq 'Shared library: \[libstdc\+\+\.so' "$log"
        fi
        if [[ $variant == after && $package == vector ]]; then
            # Also compile all original vector sources, without a probe override.
            run_logged "$log" make -j2 binaries
            python3 - "$build" <<'PY'
import ctypes
from pathlib import Path
import sys
libraries = list(Path(sys.argv[1]).glob("lib*vector*.so"))
assert len(libraries) == 1, libraries
ctypes.CDLL(str(libraries[0]))
print("Original vector library built and loaded:", libraries[0].name)
PY
        fi
    done
done

# Verify the real static recipe still builds an archive with the same object.
mkdir "$work/static"
cd "$work/static"
log="$logs/static-tclfitsy.log"
run_logged "$log" env CC=gcc CXX=g++ bash "$work/after/source/tclfitsy/configure" \
    --prefix="$prefix" --with-tcl="$work/tcl" --disable-shared
cp "$work/runtimeprobe.C" .
run_logged "$log" make PKG_OBJECTS=runtimeprobe.o PKG_LIB_FILE=runtimeprobe.a runtimeprobe.a
ar t runtimeprobe.a | tee -a "$log" | grep -Fx runtimeprobe.o
echo 'PASS: before-failure reproduced; all six fixed shared recipes, C compilation, full vector build/load and static archive passed.'
