# nunu_one.py — Clean, patch, restore, build, deploy (Python 3.7+ compatible)
# Run via your venv:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\NunuCompanionApp V2.0\nunu-go-venv.ps1" -Mode net9

import argparse, os, re, subprocess, sys, shutil, json
from pathlib import Path
from typing import Optional

def note(msg): print(f"[Nunu] {msg}")

def run(cmd, cwd=None, log=None):
    note(f"Run: {' '.join(cmd)}")
    cp = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log:
        Path(log).write_text(cp.stdout or "", encoding="utf-8", errors="ignore")
    if cp.returncode != 0:
        tail = "\n".join((cp.stdout or "").splitlines()[-120:])
        print(tail)
        raise RuntimeError("command failed ({})".format(cp.returncode))
    return cp.stdout or ""

def detect_sdks():
    try:
        out = subprocess.run(["dotnet", "--list-sdks"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout or ""
    except FileNotFoundError:
        raise RuntimeError(".NET SDK not found in PATH. Install .NET 8/9 SDK.")
    has8 = any(re.match(r"\s*8\.", line) for line in out.splitlines())
    has9 = any(re.match(r"\s*9\.", line) for line in out.splitlines())
    return has8, has9, out

def find_csproj(root: Path, internal: Optional[str]):
    cands = [p for p in root.rglob("*.csproj") if "\\bin\\" not in str(p) and "\\obj\\" not in str(p)]
    if not cands:
        raise RuntimeError("No .csproj found under {}".format(root))
    if internal:
        for p in cands:
            if p.stem.lower() == internal.lower():
                return p
    return sorted(cands, key=lambda p: str(p).lower())[0]

def sanitize_cs(root: Path):
    trans = {
        "\u2018":"'","\u2019":"'","\u201B":"'","\u201C":'"',"\u201D":'"',"\u201F":'"',
        "\u00AB":'"',"\u00BB":'"',"\u2013":"-","\u2014":"-","\u2026":"...",
        "\u00A0":" ","\u200B":"","\u200C":"","\u200D":"","\ufeff":""
    }
    count = 0
    for f in root.rglob("*.cs"):
        s = str(f)
        if "\\bin\\" in s or "\\obj\\" in s: 
            continue
        txt = f.read_text(encoding="utf-8", errors="ignore")
        orig = txt
        for k,v in trans.items():
            txt = txt.replace(k,v)
        lines = txt.splitlines()
        for i,L in enumerate(lines):
            lines[i] = L.lstrip("\ufeff\u200b\u200c\u200d")
        new = "\r\n".join(lines)
        if new != orig:
            f.write_text(new, encoding="utf-8")
            count += 1
    return count

def patch_sources_for_api(root: Path, target: str):
    """
    net8/api12:  Dalamud.Bindings.ImGui -> ImGuiNET, senderId int->uint
    net9/api13:  ImGuiNET -> Dalamud.Bindings.ImGui, senderId stays int
    """
    multi = re.MULTILINE
    patched = 0
    for f in root.rglob("*.cs"):
        s = str(f)
        if "\\bin\\" in s or "\\obj\\" in s:
            continue
        txt = f.read_text(encoding="utf-8", errors="ignore")
        orig = txt
        if target == "net8":
            txt = re.sub(r"^\s*using\s+Dalamud\.Bindings\.ImGui\s*;\s*$", "using ImGuiNET;", txt, flags=multi)
            txt = re.sub(r"^\s*using\s+Dalamud\.Bindings\.ImPlot\s*;\s*$", "using ImPlotNET;", txt, flags=multi)
            txt = re.sub(r"^\s*using\s+Dalamud\.Bindings\.ImGuizmo\s*;\s*$", "using ImGuizmoNET;", txt, flags=multi)
            if f.name.lower() == "chatrouter.cs":
                txt = re.sub(r"(\W)int\s+senderId(\W)", r"\1uint senderId\2", txt)
        else:  # net9
            txt = re.sub(r"^\s*using\s+ImGuiNET\s*;\s*$", "using Dalamud.Bindings.ImGui;", txt, flags=multi)
            txt = re.sub(r"^\s*using\s+ImPlotNET\s*;\s*$", "using Dalamud.Bindings.ImPlot;", txt, flags=multi)
            txt = re.sub(r"^\s*using\s+ImGuizmoNET\s*;\s*$", "using Dalamud.Bindings.ImGuizmo;", txt, flags=multi)
            if f.name.lower() == "chatrouter.cs":
                # ensure int senderId for API 13
                txt = re.sub(r"(\W)uint\s+senderId(\W)", r"\1int senderId\2", txt)
        if txt != orig:
            f.write_text(txt, encoding="utf-8")
            patched += 1
    return patched

def ensure_nuget(root_csproj_dir: Path):
    cfg = root_csproj_dir / "nuget.config"
    if not cfg.exists():
        cfg.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<configuration>\n'
            '  <packageSources>\n'
            '    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />\n'
            '  </packageSources>\n'
            '</configuration>\n', encoding="utf-8"
        )
        note("Created nuget.config with nuget.org")
    else:
        t = cfg.read_text(encoding="utf-8", errors="ignore")
        if "nuget.org" not in t:
            t = re.sub(r"</packageSources>", '    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />\n  </packageSources>', t)
            cfg.write_text(t, encoding="utf-8")
            note("Added nuget.org to existing nuget.config")

def patch_csproj(csproj: Path, internal: str, target: str, sdk12_ver="12.0.2", packager_ver="13.1.0"):
    import xml.etree.ElementTree as ET
    tree = ET.parse(csproj)
    root = tree.getroot()

    # Set Sdk
    root.set("Sdk", "Dalamud.NET.Sdk/{}".format(sdk12_ver) if target=="net8" else "Dalamud.NET.Sdk")

    def get_or_make(parent, tag):
        node = parent.find(tag)
        if node is None:
            node = ET.SubElement(parent, tag)
        return node

    pg = root.find("PropertyGroup")
    if pg is None:
        pg = ET.SubElement(root, "PropertyGroup")
    get_or_make(pg,"TargetFramework").text = "net8.0" if target=="net8" else "net9.0"
    get_or_make(pg,"Platforms").text = "x64"
    get_or_make(pg,"Nullable").text = "enable"
    get_or_make(pg,"ImplicitUsings").text = "enable"
    get_or_make(pg,"LangVersion").text = "latest"
    get_or_make(pg,"AllowUnsafeBlocks").text = "true"
    get_or_make(pg,"AssemblyName").text = internal
    get_or_make(pg,"RootNamespace").text = internal

    # Remove explicit Reference nodes to Dalamud*/ImGui*
    for ig in list(root.findall("ItemGroup")):
        for ref in list(ig.findall("Reference")):
            inc = ref.get("Include") or ""
            if inc.startswith("Dalamud") or inc.startswith("ImGui"):
                ig.remove(ref)
        if ig.get("Label") == "DalamudRefs":
            root.remove(ig)

    # PackageReference handling
    if target == "net8":
        for ig in list(root.findall("ItemGroup")):
            for pr in list(ig.findall("PackageReference")):
                if pr.get("Include") == "DalamudPackager":
                    ig.remove(pr)
    else:  # net9
        found = None
        for ig in root.findall("ItemGroup"):
            for pr in ig.findall("PackageReference"):
                if pr.get("Include")=="DalamudPackager":
                    found = pr; break
            if found: break
        if found is None:
            tgt_ig = None
            for ig in root.findall("ItemGroup"):
                if ig.find("PackageReference") is not None:
                    tgt_ig = ig; break
            if tgt_ig is None:
                tgt_ig = ET.SubElement(root,"ItemGroup")
            pr = ET.SubElement(tgt_ig,"PackageReference", Include="DalamudPackager", Version=packager_ver)
            pv = ET.SubElement(pr,"PrivateAssets"); pv.text="All"

    # Ensure manifest copy
    auto_ig = None
    for ig in root.findall("ItemGroup"):
        if ig.get("Label")=="NunuAuto":
            auto_ig = ig; break
    if auto_ig is None:
        auto_ig = ET.SubElement(root,"ItemGroup", Label="NunuAuto")
    found_none = None
    for n in auto_ig.findall("None"):
        if n.get("Include")==f"{internal}.yaml":
            found_none = n; break
    if found_none is None:
        found_none = ET.SubElement(auto_ig,"None", Include=f"{internal}.yaml")
    found_none.set("CopyToOutputDirectory","Always")

    tree.write(csproj, encoding="utf-8", xml_declaration=True)

def ensure_manifest(projdir: Path, internal: str, target: str):
    p = projdir / f"{internal}.yaml"
    if p.exists():
        return
    body = (
        "name: Nunu Companion App V2.0\n"
        "author: The Nunu\n"
        "punchline: Minimal chat capture window.\n"
        "description: |\n"
        "  Nunu Companion App (V2) — simple chat capture and viewer using Dalamud {}.\n"
        "tags: [utility, chat]\n"
    ).format("API 12" if target=="net8" else "v13")
    p.write_text(body, encoding="utf-8")
    note("Manifest created: {}".format(p))

def fix_global_json(root: Path, target: str, sdks_out: str):
    gj = root / "global.json"
    if not gj.exists(): 
        return
    try:
        data = json.loads(gj.read_text(encoding="utf-8"))
        ver = (data.get("sdk") or {}).get("version")
        if ver:
            want = "8." if target=="net8" else "9."
            if not ver.startswith(want):
                avail = [ln.split()[0] for ln in sdks_out.splitlines() if ln.strip().startswith(want)]
                if avail:
                    best = sorted(avail)[-1]
                    data.setdefault("sdk", {})["version"] = best
                    gj.write_text(json.dumps(data, indent=2), encoding="utf-8")
                    note("global.json pinned to {}; switched to {}".format(ver, best))
    except Exception as e:
        note("global.json parse skip: {}".format(e))

def deploy(outdir: Path, projdir: Path, internal: str, deploy_dir: Path):
    deploy_dir.mkdir(parents=True, exist_ok=True)
    items = []
    dll = outdir / f"{internal}.dll"
    if not dll.exists():
        raise RuntimeError("{} not found in {}".format(dll.name, outdir))
    items.append(dll)
    pdb = outdir / f"{internal}.pdb"
    if pdb.exists(): items.append(pdb)
    yaml_out = outdir / f"{internal}.yaml"
    if yaml_out.exists(): items.append(yaml_out)
    else: items.append(projdir / f"{internal}.yaml")
    for name in ("manifest.json","latest.zip","icon.png"):
        p = outdir / name
        if p.exists(): items.append(p)
    for f in items:
        shutil.copy2(f, deploy_dir / f.name)
        note("Deployed: {}".format(f.name))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\NunuCompanionApp V2.0")
    ap.add_argument("--internal", default="NunuCompanionAppV2")
    ap.add_argument("--deploy", default=r"C:\NunuCompanionApp V2.0\Drop")
    ap.add_argument("--mode", choices=["auto","net8","net9"], default="auto")
    ap.add_argument("--sdk12", default="12.0.2", help="Dalamud.NET.Sdk version to pin for API 12 build")
    ap.add_argument("--packager13", default="13.1.0", help="DalamudPackager version for API 13")
    args = ap.parse_args()

    root = Path(args.root)
    internal = args.internal
    deploy_dir = Path(args.deploy)

    has8, has9, sdks_out = detect_sdks()
    if args.mode == "auto":
        target = "net9" if has9 else ("net8" if has8 else "net8")
    else:
        target = args.mode
    note("Target selected: {}".format(target))

    csproj = find_csproj(root, internal)
    projdir = csproj.parent
    note("Project: {}".format(csproj))

    restore_log = projdir / "nunu-restore.log"
    build_log   = projdir / "nunu-build.log"

    ensure_nuget(projdir)

    count = sanitize_cs(root)
    note("Sanitized {} file(s).".format(count))

    patched = patch_sources_for_api(root, target)
    note("Patched {} file(s).".format(patched))

    patch_csproj(csproj, internal, target, sdk12_ver=args.sdk12, packager_ver=args.packager13)
    note("csproj patched.")

    fix_global_json(root, target, sdks_out)

    try:
        run(["dotnet","nuget","locals","all","--clear"], cwd=str(projdir))
        note("NuGet caches cleared.")
    except Exception as e:
        note("NuGet cache clear skipped: {}".format(e))

    note("dotnet restore…")
    run(["dotnet","restore",str(csproj), "--no-cache","--verbosity","minimal"], cwd=str(projdir), log=str(restore_log))

    note("dotnet build (Release)…")
    run(["dotnet","build",str(csproj), "-c","Release","/p:MakeZip=true","-v","m","/clp:Summary;ErrorsOnly"], cwd=str(projdir), log=str(build_log))

    tfm = "net8.0" if target=="net8" else "net9.0"
    outdir = projdir / "bin" / "Release" / tfm
    if not outdir.exists():
        dlls = sorted((p for p in (projdir/"bin"/"Release").rglob(f"{internal}.dll")), key=lambda p: p.stat().st_mtime, reverse=True)
        if not dlls:
            raise RuntimeError("Build output not found for {}.dll in bin\\Release.".format(internal))
        outdir = dlls[0].parent
    sub = outdir / internal
    if sub.exists(): outdir = sub
    note("Output Root: {}".format(outdir))

    deploy(outdir, projdir, internal, deploy_dir)

    print("\n=== Build + Deploy complete ===")
    print("Logs: {} ; {}".format(restore_log, build_log))
    print("Drop Folder: {}".format(deploy_dir))

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("[Nunu] ERROR: {}".format(e))
        sys.exit(1)
