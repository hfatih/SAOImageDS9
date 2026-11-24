"""Compare real DS9 GIF frames from generated ranges and explicit lists."""

import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time

from PIL import Image, ImageSequence


repo = Path.cwd()
out = Path(os.environ["RUNNER_TEMP"]) / "ds9-258-live"
out.mkdir(exist_ok=True)
target = "DS9Range258"
os.environ["PATH"] = str(repo / "bin") + os.pathsep + os.environ["PATH"]


def command(*args):
    result = subprocess.run(["xpaset", "-p", target, *args], text=True,
                            capture_output=True, timeout=45)
    if result.returncode or result.stderr or "XPA$ERROR" in result.stdout:
        raise RuntimeError((args, result.returncode, result.stdout, result.stderr))


def gif_frames(name, contents):
    script = out / (name + ".cmd")
    output = out / (name + ".gif")
    script.write_text(contents, encoding="utf-8")
    command("movie", "script", "gif", "5", "blink", str(script), str(output))
    with Image.open(output) as image:
        frames = [hashlib.sha256(frame.convert("RGB").tobytes()).hexdigest()
                  for frame in ImageSequence.Iterator(image)]
    assert len(set(frames)) > 1, (name, "all frames identical")
    return frames


# A small asymmetric FITS image, independent of external fixtures/libraries.
cards = ["SIMPLE  =                    T", "BITPIX  =                   16",
         "NAXIS   =                    2", "NAXIS1  =                   64",
         "NAXIS2  =                   64", "END"]
header = "".join(card.ljust(80) for card in cards).encode("ascii").ljust(2880, b" ")
pixels = [((x * 3 + y * 11) % 1200) + (6000 if x < 13 and 5 < y < 53 else 0)
          for y in range(64) for x in range(64)]
data = struct.pack(">4096h", *pixels)
data += b"\0" * (-len(data) % 2880)
fixture = out / "asymmetric.fits"
fixture.write_bytes(header + data)

with (out / "ds9.log").open("w") as log:
    ds9 = subprocess.Popen([str(repo / "bin/ds9"), "-prefs", "no", "-title", target,
                            "-geometry", "400x400"], stdout=log, stderr=log)
    try:
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if ds9.poll() is not None:
                raise RuntimeError("DS9 exited before registering with XPA")
            check = subprocess.run(["xpaaccess", target], capture_output=True,
                                   text=True, timeout=5)
            if check.stdout.strip() == "yes":
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("DS9 did not register with XPA")

        command("file", str(fixture))
        command("scale", "linear")
        results = []
        cases = (
            ("linear", "zoom to 3 &&\nrotate to 0 &&\n", "linear 0 180 5",
             "0 45 90 135 180", "rotate to @", 5),
            ("descending", "zoom to 3 &&\nrotate to 0 &&\n", "linear 180 0 5",
             "180 135 90 45 0", "rotate to @", 5),
            ("log", "rotate to 0 &&\nzoom to 1 &&\n", "log 1 4 3",
             "1 2 4", "zoom to @", 3),
            ("log-descending", "rotate to 0 &&\nzoom to 1 &&\n", "log 4 1 3",
             "4 2 1", "zoom to @", 3),
        )
        for name, setup, specification, values, template, count in cases:
            generated = gif_frames(name + "-range", setup +
                                   f"foreach {specification} {{{template}}}\n")
            explicit = gif_frames(name + "-list", setup +
                                  f"foreach {{{values}}} {{{template}}}\n")
            assert len(generated) == count, (name, len(generated), count)
            assert generated == explicit, (name, "pixel mismatch", generated, explicit)
            results.append({"case": name, "frames": count,
                            "all_decoded_frames_match_explicit_list": True,
                            "frame_hashes": generated})
        (out / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(json.dumps(results, indent=2))
    finally:
        try:
            command("exit")
        finally:
            ds9.wait(timeout=15)
