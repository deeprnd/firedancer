"""
Silly tool that verifies whether C/C++ header include guards match
Firedancer code style.
"""

from pathlib import Path
import os


def check_file(path):
    guard_name = "HEADER_fd_" + str(path).replace(".", "_").replace("/", "_").replace("-", "_")
    with open(path, "r") as f:
        first_line = f.readline()
        if first_line.startswith("/* DO NOT INCLUDE DIRECTLY"):
            return
        # Skip whitespace and comment lines
        line0 = first_line
        while True:
            if not line0.startswith("/* ") and not line0.startswith("// ") and line0.strip():
                break
            line0 = f.readline()
        line1 = f.readline()
        if not line0.startswith("#ifndef ") and not line1.startswith("#define "):
            print(f"{path}: include guard missing")
        if line0[8:] != line1[8:]:
            return
        if line0[8:].strip() != guard_name:
            print(f"{path}: include guard name '{line0[8:].strip()}' does not match expected '{guard_name}'")


def main():
    import sys
    if len(sys.argv) > 1:
        paths = [Path(p) for p in sys.argv[1:] if p.endswith(".h")]
    else:
        os.chdir(Path(__file__).parents[2])
        paths = [p for p in Path("./src").rglob("*.h") if ".pb.h" not in p.name]
    for path in paths:
        try:
            check_file(path)
        except IOError:
            print(f"Error reading file: {path}")


if __name__ == "__main__":
    main()
