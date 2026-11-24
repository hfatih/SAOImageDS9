"""Measure actual shared libraries; retain unresolved application symbols."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys

work = Path(sys.argv[1])
variant, ref = sys.argv[2:]
packages = ("vector", "fitsy", "tkblt", "tclfitsy", "tkmpeg", "tksao")
libs = {}
for package in packages:
    files = list((work / "source" / package).glob("lib*.so"))
    assert len(files) == 1, (package, files)
    libs[package] = files[0]
runtime = subprocess.check_output(["g++", "-print-file-name=libstdc++.so"], text=True).strip()
exports = subprocess.check_output(["nm", "-D", "--defined-only", runtime], text=True)
runtime_symbols = {line.split()[-1].split("@")[0] for line in exports.splitlines() if line.split()}
env = dict(os.environ)
env["LD_LIBRARY_PATH"] = os.pathsep.join([str(work / "install/lib")] +
                                       [str(path.parent) for path in libs.values()])
results = []
for package, library in libs.items():
    needed = subprocess.check_output(["readelf", "-d", str(library)], text=True)
    undefined = subprocess.check_output(["nm", "-D", "--undefined-only", str(library)], text=True)
    referenced_runtime = sorted({line.split()[-1].split("@")[0]
                                 for line in undefined.splitlines() if line.split()} & runtime_symbols)
    relocations = subprocess.run(["ldd", "-r", str(library)], capture_output=True, text=True, env=env)
    unresolved = re.findall(r"undefined symbol: (\S+)", relocations.stdout + relocations.stderr)
    unresolved_runtime = sorted({name.split("@")[0] for name in unresolved} & runtime_symbols)
    direct_runtime = bool(re.search(r"Shared library: \[libstdc\+\+\.so", needed))
    log = work / "logs" / (package + "-symbols.log")
    log.write_text(needed + "\n" + undefined + "\n" + relocations.stdout + relocations.stderr)
    # A fresh C-only Python process tests real dlopen, without hiding errors.
    load = subprocess.run([sys.executable, "-c",
                           "import ctypes,os,sys; ctypes.CDLL(sys.argv[1], mode=os.RTLD_NOW|os.RTLD_GLOBAL)",
                           str(library)], capture_output=True, text=True, env=env)
    row = {"package": package, "library": library.name,
           "direct_libstdcxx_needed": direct_runtime,
           "referenced_cpp_runtime_symbols": len(referenced_runtime),
           "runtime_resolved_transitively": (not direct_runtime and bool(referenced_runtime) and
                                             not unresolved_runtime and "libstdc++" in relocations.stdout),
           "unresolved_cpp_runtime_symbols": len(unresolved_runtime),
           "unresolved_cpp_runtime_names": unresolved_runtime,
           "remaining_unresolved_symbols": [x for x in unresolved if x not in unresolved_runtime],
           "real_dlopen_succeeded": load.returncode == 0,
           "real_dlopen_error": load.stderr.strip(),
           "compiled_object_count": len(list(library.parent.rglob("*.o"))),
           "warning_count": (work / "logs" / (package + "-build.log")).read_text().count("warning:")}
    results.append(row)
    if variant == "after":
        assert direct_runtime and not unresolved_runtime, row
    elif package in ("tclfitsy", "tksao"):
        assert not direct_runtime, row
        if package == "tclfitsy":
            assert unresolved_runtime, row
    print(json.dumps(row, indent=2))
manifest = {"variant": variant, "source_commit": ref,
            "compiler": subprocess.check_output(["g++", "--version"], text=True).splitlines()[0],
            "results": results}
(work / "logs/results.json").write_text(json.dumps(manifest, indent=2))
