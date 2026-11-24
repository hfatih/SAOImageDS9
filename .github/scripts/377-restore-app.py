import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path.cwd()
packages = list((root / 'compiled').rglob('SAOImageDS9.app'))
assert len(packages) == 1, packages
app = root / 'bin/SAOImageDS9.app'
app.parent.mkdir(exist_ok=True)
shutil.copytree(packages[0], app)

# Artifact transfer does not preserve executable bits.
for path in app.rglob('*'):
    if path.is_file():
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic in {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe'}:
            path.chmod(path.stat().st_mode | 0o111)

# This change only touches interpreted Tcl and HTML; the C++ executable is reused.
# macOS's normal ds9 target copies these same Tcl sources into this resources directory.
changed = subprocess.check_output([
    'git', 'diff', '--name-only', '8bf592edf01d85ff6d56999acfbe9e4f3aa71400', 'HEAD',
    '--', 'ds9/library'
], text=True).splitlines()
destination = app / 'Contents/Frameworks/Tksao.framework/Resources/library'
assert (destination / 'menu.tcl').is_file(), destination
evidence = []
for name in changed:
    source = root / name
    assert source.suffix == '.tcl', source
    target = destination / source.name
    shutil.copy2(source, target)
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    assert source_hash == hashlib.sha256(target.read_bytes()).hexdigest()
    evidence.append({'file': name, 'source_and_packaged_sha256': source_hash})
assert len(evidence) == 11, evidence
(root / '377-packaged-files.json').write_text(json.dumps(evidence, indent=2))
print('Reused full-build executable; packaged and verified all 11 final Tcl files.')
