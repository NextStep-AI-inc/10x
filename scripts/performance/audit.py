#!/usr/bin/env python3
"""Build and run the synthetic performance probes against this checkout.

Run from any directory: python3 scripts/performance/audit.py --output /tmp/10x-audit
Use a different output directory for each revision. This does not launch the app.
"""

import argparse
from pathlib import Path
import subprocess


def run(arguments, log, cwd):
    print(f"Running {arguments[0]} → {log}", flush=True)
    with log.open("w") as output:
        subprocess.run(arguments, cwd=cwd, stdout=output,
                       stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    derived = output / "DerivedData"
    products = derived / "Build/Products/Release"
    with (output / "revision.txt").open("w") as revision:
        subprocess.run(["git", "rev-parse", "HEAD"], cwd=root,
                       stdout=revision, check=True)
        subprocess.run(["git", "status", "--short"], cwd=root,
                       stdout=revision, check=True)
    run(["xcodebuild", "-project", "10x.xcodeproj", "-scheme", "10x",
         "-configuration", "Release", "-destination", "platform=macOS",
         "-derivedDataPath", str(derived), "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
         "CODE_SIGNING_ALLOWED=NO", "build"], output / "build.log", root)
    compiler = ["xcrun", "swiftc", "-O", "-whole-module-optimization",
                "-swift-version", "6", "-target", "arm64-apple-macos15.0",
                "-I", str(products)]
    app_sources = sorted(str(path) for path in (root / "App").rglob("*.swift")
                         if path.name != "TenXApp.swift")
    for name, source, extra in [
        ("app", "AppAudit.swift", ["-F", str(products), "-framework", "Sparkle",
                                  "-Xlinker", "-rpath", "-Xlinker", str(products)]
         + app_sources),
        ("transport", "TransportAudit.swift", ["-parse-as-library"]),
    ]:
        binary = output / name
        command = compiler + extra + [str(root / "scripts/performance" / source),
                                      str(products / "OmpKit.o"), "-o", str(binary)]
        run(command, output / f"{name}-compile.log", root)
        run([str(binary)], output / f"{name}.log", root)
        print((output / f"{name}.log").read_text(), end="")


if __name__ == "__main__":
    main()
