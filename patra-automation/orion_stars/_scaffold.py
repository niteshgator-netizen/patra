from __future__ import annotations

from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "panda_master" / "panda_master.py"
TARGET = HERE / "orion_stars.py"

EXPECTED_COUNTS = {
    "panda_master": 3,
    "Panda Master": 6,
    "PANDA_MASTER": 15,
    "pm_": 1,
    "[panda_master]": 1,
    "pandamaster.vip": 1,
    "https://pandamaster.vip/default.aspx": 1,
    "https://pandamaster.vip/Store.aspx": 0,
}

REPLACEMENTS = [
    ("https://pandamaster.vip/default.aspx", "https://orionstars.vip:8781/default.aspx"),
    ("https://pandamaster.vip/Store.aspx", "https://orionstars.vip:8781/Store.aspx"),
    ("pandamaster.vip", "orionstars.vip:8781"),
    ("[panda_master]", "[orion_stars]"),
    ("panda_master", "orion_stars"),
    ("Panda Master", "Orion Stars"),
    ("PANDA_MASTER", "ORION_STARS"),
    ("pm_", "os_"),
]


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    counts = {old: text.count(old) for old, _new in REPLACEMENTS}

    unexpected = {
        key: (counts[key], expected)
        for key, expected in EXPECTED_COUNTS.items()
        if counts[key] != expected
    }
    if unexpected:
        details = ", ".join(
            f"{key!r}: got {actual}, expected {expected}"
            for key, (actual, expected) in unexpected.items()
        )
        raise SystemExit(f"Unexpected substitution count(s): {details}")

    output = text
    for old, new in REPLACEMENTS:
        output = output.replace(old, new)

    TARGET.write_text(output, encoding="utf-8", newline="\n")

    print("Substitution counts:")
    for old, _new in REPLACEMENTS:
        print(f"  {old!r}: {counts[old]}")
    print(f"Final line count: {len(output.splitlines())}")


if __name__ == "__main__":
    main()
