# nunu_build_venv.py — build & deploy using your venv’s Python (Py 3.7+ safe)
# Use --mode net8 for API 12 (your current files), or --mode net9 for API 13.

import argparse, shutil, subprocess, sys
from pathlib import Path
from typing import Optional

ROOT       = r"C:\NunuCompanionApp V2.0"
INTERNAL   = "NunuCompanionAppV2"
DEPLOY_DIR = r"C:\NunuCompanionApp V2.0\Drop"

def note(msg: str) -> None:
    print(f"[Nunu] {msg}")

def run(cmd, cwd: Optional[Path] = None, log: Optional[Path] = None) -> str:
    note("Run: " + " ".join(cmd))
    cp = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    out = cp.stdout or ""
    if log:
        try:
            log.write_text(out, encoding="utf-8", errors="ignore")
        except Exception:
            pass
    if cp.returncode != 0:
        tail = "\n".join(out.splitlines()[-160:])
        if tail:
            print(tail)
        raise SystemExit(cp.returncode)
    return out

def detect_dotnet(required_major: str) -> None:
    out = run(["dotnet", "--list-sdks"])
    if not any(line.strip().startswith(required_major + ".") for line in out.splitlines()):
        print(out)
        raise SystemExit(f".NET {required_major}.x SDK not found.")

def find_csproj(root: Path, internal: str) -> Path:
    cands = [p for p in root.rglob("*.csproj") if "\\bin\\" not in str(p) and "\\obj\\" not in str(p)]
    if not cands:
        raise SystemExit(f"No .csproj found under {root}")
    for p in cands:
        if p.stem.lower() == internal.lower():
            return p
    return sorted(cands, key=lambda p: str(p).lower())[0]

def ensure_nuget_config(projdir: Path) -> None:
    cfg = projdir / "nuget.config"
    if cfg.exists():
        return
    xml = """<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
"""
    cfg.write_text(xml, encoding="utf-8")
    note("Created nuget.config with nuget.org")

def deploy(outdir: Path, projdir: Path, internal: str, drop: Path) -> None:
    drop.mkdir(parents=True, exist_ok=True)
    dll = outdir / f"{internal}.dll"
    if not dll.exists():
        raise SystemExit(f"{dll.name} not found in {outdir}")
    items = [dll]
    pdb = outdir / f"{internal}.pdb"
    if pdb.exists():
        items.append(pdb)
    yaml_out = outdir / f"{internal}.yaml"
    items.append(yaml_out if yaml_out.exists() else projdir / f"{internal}.yaml")
    for extra in ("manifest.json", "latest.zip", "icon.png"):
        p = outdir / extra
        if p.exists():
            items.append(p)
    for f in items:
        shutil.copy2(f, drop / f.name)
        note(f"Deployed: {f.name}")

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["net8", "net9"], default="net8",
                    help="Build target (net8 for API 12, net9 for API 13)")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--internal", default=INTERNAL)
    ap.add_argument("--deploy", default=DEPLOY_DIR)
    args = ap.parse_args()

    root = Path(args.root)
    internal = args.internal
    drop = Path(args.deploy)
    required_major = "9" if args.mode == "net9" else "8"

    # Env info
    note(f"Python: {sys.executable}")
    dot = shutil.which("dotnet")
    note(f"dotnet: {dot or 'NOT FOUND'}")
    detect_dotnet(required_major)

    # Project setup
    csproj = find_csproj(root, internal)
    projdir = csproj.parent
    note(f"Project: {csproj}")

    ensure_nuget_config(projdir)

    # Clean NuGet caches for a stable restore
    try:
        run(["dotnet", "nuget", "locals", "all", "--clear"], cwd=projdir)
        note("NuGet caches cleared.")
    except SystemExit:
        raise
    except Exception as e:
        note(f"NuGet cache clear skipped: {e}")

    restore_log = projdir / "nunu-restore.log"
    build_log = projdir / "nunu-build.log"

    # Restore & build
    note("dotnet restore…")
    run(["dotnet", "restore", str(csproj), "--no-cache", "--verbosity", "minimal"], cwd=projdir, log=restore_log)

    note(f"dotnet build (Release, {args.mode})…")
    run(["dotnet", "build", str(csproj), "-c", "Release", "/p:MakeZip=true", "-v", "m", "/clp:Summary;ErrorsOnly"], cwd=projdir, log=build_log)

    # Locate output
    tfm = "net9.0" if args.mode == "net9" else "net8.0"
    outdir = projdir / "bin" / "Release" / tfm
    if not outdir.exists():
        dlls = sorted(
            (p for p in (projdir / "bin" / "Release").rglob(f"{internal}.dll")),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if not dlls:
            try:
                print(build_log.read_text(encoding="utf-8")[-4000:])
            except Exception:
                pass
            raise SystemExit(f"Build output not found for {internal}.dll in bin\\Release.")
        outdir = dlls[0].parent

    # Packager may create a subfolder named after the assembly
    sub = outdir / internal
    if sub.exists():
        outdir = sub
    note(f"Output Root: {outdir}")

    # Deploy
    deploy(outdir, projdir, internal, drop)

    print("\n=== Build + Deploy complete ===")
    print(f"Logs: {restore_log} ; {build_log}")
    print(f"Drop Folder: {drop}")

if __name__ == "__main__":
    main()
