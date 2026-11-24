import os
from pathlib import Path
import subprocess
import sys
import time

root = Path.cwd()
output = Path(os.environ['RUNNER_TEMP']) / 'ds9-377-app'
output.mkdir(exist_ok=True)
program = root / 'bin/SAOImageDS9.app/Contents/MacOS/ds9'
script = root / '.github/scripts/377-app-smoke.tcl'
env = os.environ.copy()
env['DS9_MENU_RESULT'] = str(output / 'results.txt')
env['DS9_MENU_CAPTURE'] = '1'
with (output / 'stdout.log').open('w') as stdout, (output / 'stderr.log').open('w') as stderr:
    app = subprocess.Popen([str(program), '-prefs', 'no', '-source', str(script)],
                           env=env, stdout=stdout, stderr=stderr)
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            result = output / 'results.txt'
            text = result.read_text() if result.exists() else ''
            if 'FAIL ' in text:
                raise RuntimeError(text)
            if 'READY_FOR_CAPTURE' in text:
                break
            if app.poll() is not None:
                raise RuntimeError(f'DS9 exited early: {app.returncode}; {text}')
            time.sleep(.25)
        else:
            raise TimeoutError('Actual DS9 did not complete menu checks within 120 seconds')
        time.sleep(2)
        assert app.poll() is None, 'DS9 exited before the menu screenshot'
        capture = subprocess.run(['/usr/sbin/screencapture', '-x', str(output / 'native-menu.png')],
                                 capture_output=True, text=True, timeout=15)
        (output / 'screenshot-status.txt').write_text(f'{capture.returncode}\n{capture.stderr}')
        print(text)
        print(f'Screenshot exit: {capture.returncode}; fixture terminated after completed checks')
    finally:
        if app.poll() is None:
            app.terminate()
        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
