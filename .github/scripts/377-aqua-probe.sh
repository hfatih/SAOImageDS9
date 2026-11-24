#!/usr/bin/env bash
set -euo pipefail
repo=$(pwd)
work="$RUNNER_TEMP/ds9-377-aqua"
prefix="$work/install"
mkdir -p "$work/source" "$work/logs"
git archive HEAD tcl9.0 tk9.0 | tar -x -C "$work/source"
cd "$work/source/tcl9.0/unix"
bash configure --prefix="$prefix" --enable-shared > "$work/logs/tcl-configure.log" 2>&1
make -j4 binaries > "$work/logs/tcl-build.log" 2>&1
make install-binaries install-libraries install-headers > "$work/logs/tcl-install.log" 2>&1
export DYLD_LIBRARY_PATH="$prefix/lib:${DYLD_LIBRARY_PATH:-}"
cd "$work/source/tk9.0/unix"
bash configure --prefix="$prefix" --with-tcl="$work/source/tcl9.0/unix" \
    --enable-shared --enable-aqua > "$work/logs/tk-configure.log" 2>&1
make -j4 binaries > "$work/logs/tk-build.log" 2>&1
make install-binaries install-libraries install-headers > "$work/logs/tk-install.log" 2>&1
export AQUA_PROBE_RESULT="$work/logs/results.txt"
export AQUA_PROBE_SCREENSHOT="$work/logs/aqua.png"
export TCL_LIBRARY="$prefix/lib/tcl9.0"
export TK_LIBRARY="$prefix/lib/tk9.0"
python3 - "$prefix/bin/wish9.0" "$repo/.github/scripts/377-aqua-probe.tcl" <<'PY'
import subprocess
import sys
subprocess.run(sys.argv[1:], check=True, timeout=45)
PY
cat "$AQUA_PROBE_RESULT"
grep -Fx 'PASS native Aqua execution probe' "$AQUA_PROBE_RESULT"
sw_vers > "$work/logs/environment.txt"
