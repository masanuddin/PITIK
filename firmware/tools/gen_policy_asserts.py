"""Ubah event emulator terekam (JSON dari verify_stream_events.mjs) menjadi
static_assert C++ terhadap control_stream_policy.h ASLI (bukan tiruan).

Ekspektasi berasal dari KEBIJAKAN YANG DISETUJUI, bukan dari kode yang diuji:
  - event di path "/" bertipe put   → snapshot: fan/pump/auto_mode tidak diterapkan
  - event di path "/" bertipe patch → semua kunci di payload diterapkan
Event di path anak ("/fan") tidak lewat helper root → hanya dicatat.

Pemakaian:
  python firmware/tools/gen_policy_asserts.py events.json out.cpp
  xtensa-esp32s3-elf-g++ -std=gnu++2b -fsyntax-only -I firmware/pitik_v8_4 out.cpp
"""
import json
import sys

ACTUATOR = {"fan", "pump", "auto_mode"}
EXPECT_KIND = {"put": "Snapshot", "patch": "Patch"}


def cstr(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(src: str, dst: str) -> None:
    data = json.load(open(src, encoding="utf-8"))
    lines = [
        "// DIHASILKAN OTOMATIS dari event emulator terekam — jangan edit.",
        '#include "control_stream_policy.h"',
        "namespace recorded {",
        "using namespace pitik;",
    ]
    n = 0
    for step in data["steps"]:
        for i, ev in enumerate(step["events"]):
            et, path, payload = ev["eventType"], ev.get("path"), ev.get("data")
            tag = f'{step["id"]}#{i} {et} {path}'
            if path != "/":
                lines.append(f"// {tag}: path anak → parseControlKey langsung (tidak lewat helper root)")
                continue
            kind = EXPECT_KIND.get(et, "Ignore")
            lines.append(
                f"static_assert(classifyRootEvent({cstr(et)}) == RootEvent::{kind}, {cstr(tag + ' kind')});")
            n += 1
            if not isinstance(payload, dict):
                lines.append(f"// {tag}: data bukan objek ({type(payload).__name__}) → firmware return (dataType != json)")
                continue
            for key in payload:
                expect = kind == "Patch" or (kind == "Snapshot" and key not in ACTUATOR)
                neg = "" if expect else "!"
                lines.append(
                    f"static_assert({neg}rootKeyApplies(classifyRootEvent({cstr(et)}), {cstr(key)}), "
                    f"{cstr(tag + ' key ' + key)});")
                n += 1
    lines += ["}  // namespace recorded", f"// total static_assert: {n}", ""]
    open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"{n} static_assert ditulis ke {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
