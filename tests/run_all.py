# Kører alle tests i alle varianter og giver én samlet status.
# Kør: pip install lupa && python tests/run_all.py [filter]
#   filter: kør kun testfiler, hvis navn indeholder teksten (fx "haan")
import os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(HERE), "WastedCoast")

# Varianter pr. testfil. Standard: TBC og WoW Forever. test_drilleri kender "native" i stedet.
VARIANTS = {"test_drilleri.py": [None, "native"]}
DEFAULT = [None, "forever"]


def check_file_list():
    """wowmock.FILES skal have samme filer i samme rækkefølge som .toc-filen."""
    sys.path.insert(0, HERE)
    from wowmock import FILES
    with open(os.path.join(ADDON, "WastedCoast.toc"), encoding="utf-8") as f:
        toc = [l.strip() for l in f if l.strip().endswith(".lua") and not l.startswith("#")]
    if toc != FILES:
        print("FAIL: tests/wowmock.py FILES passer ikke med WastedCoast.toc")
        print("  .toc:    ", toc)
        print("  wowmock: ", FILES)
        return False
    return True


def run(job):
    name, variant = job
    cmd = [sys.executable, os.path.join(HERE, name), ADDON] + ([variant] if variant else [])
    env = dict(os.environ, PYTHONIOENCODING="utf-8")   # Windows-konsollen er ellers cp1252
    p = subprocess.run(cmd, cwd=HERE, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return name, variant, p.returncode, (p.stdout + p.stderr).strip()


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    files = sorted(f for f in os.listdir(HERE) if f.startswith("test_") and f.endswith(".py") and flt in f)
    jobs = [(f, v) for f in files for v in VARIANTS.get(f, DEFAULT)]
    ok = check_file_list()
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        results = list(ex.map(run, jobs))
    failed = 0
    for name, variant, code, out in results:
        label = name + (" " + variant if variant else "")
        if code == 0:
            last = out.splitlines()[-1] if out else ""
            print(f"  ok    {label:32} {last}")
        else:
            failed += 1
            print(f"  FAIL  {label}")
            for line in out.splitlines()[-15:]:
                print("        " + line)
    total = len(results)
    print(f"\n{total - failed}/{total} testkørsler bestået" + ("" if ok else ", og fillisten passer ikke"))
    sys.exit(0 if failed == 0 and ok else 1)


if __name__ == "__main__":
    main()
