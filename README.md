# NunuCompanionAppV2 — An AI Chat Companion for Dalamud

<p align="center">
  <img src="."https://github.com/insanityiskey85-create/NunuTheCompanionV2/blob/master/Nunu%20Companion%20App%20V2.0/Assests/icon.png" alt="Little FFXIV Nunu — AI Chat Companion" width="820"/>
  <br/>
  <em>Place a wide banner at <code></code> (recommended: 1640×560). Include your favorite Little Nunu art.</em>
</p>

<p align="center">
  <a href="https://github.com/your-org/NunuCompanionAppV2/actions/workflows/build.yml"><img alt="Build" src="https://img.shields.io/github/actions/workflow/status/your-org/NunuCompanionAppV2/build.yml?branch=main"></a>
  <img alt="Dalamud" src="https://img.shields.io/badge/Platform-Dalamud-9146FF">
  <img alt="FFXIV" src="https://img.shields.io/badge/Game-FFXIV-BA2C2C">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
</p>

> A sleek, privacy‑first AI companion that lives in your chat window and keeps you company across Eorzea. Streaming replies, persona presets, context rules, and thoughtful guardrails. No spam, no macros, no ToS shenanigans.

---

## ✨ What it does

* **In‑game AI chat** — A tidy ImGui chat panel docked or floating, with streaming responses and markdown‑lite rendering.
* **Personas & presets** — Swap between personalities (e.g. mentor, lore‑rat, haiku mode) with one click. Includes a sane default: **Little Nunu**.
* **Context rules** — You decide what goes in: current zone, time, party names (hashed), recent chat lines, or nothing at all.
* **Provider‑agnostic** — Works with **OpenAI‑compatible** endpoints. Bring your own API key (OpenAI, Azure OpenAI, local servers like **Ollama** with an OpenAI shim, etc.).
* **Safety & privacy** — Redact player names, FC tags, and links before requests. Local, opt‑in logs; no telemetry.
* **Slash commands** — `/nunu` to open, `/nunu ask <text>`, `/nunu persona <name>`, `/nunu off`.
* **Focus & Duty mode** — Auto‑mute during duties or combat; optionally resume afterward.
* **Clipboard & history** — Quick‑paste from clipboard; searchable local chat history.

> Performance note: all network calls run off the render thread. The UI never blocks the frame.

---

## 📦 Install

### From a Custom Plugin Repo (recommended)

1. In **XIVLauncher** → **Dalamud Settings** → **Experimental**, add your plugin repo URL.
2. Open **Plugin Installer**, search for **NunuCompanionAppV2**, click **Install**.

Example `manifest` entry:

```json
{
  "$schema": "https://raw.githubusercontent.com/goatcorp/DalamudPluginRepo/master/manifest.schema.json",
  "name": "NunuCompanionAppV2",
  "author": "Real Nunu",
  "Punchline": "AI chat companion for FFXIV.",
  "Description": "Streaming chat, personas, and privacy‑first context rules.",
  "InternalName": "NunuCompanionAppV2",
  "AssemblyVersion": "0.2.0.0",
  "ApplicableVersion": "any",
  "RepoUrl": "https://github.com/your-org/NunuCompanionAppV2",
  "DownloadLinkInstall": "https://example.com/releases/NunuCompanionAppV2/latest.zip",
  "DownloadLinkUpdate": "https://example.com/releases/NunuCompanionAppV2/latest.zip",
  "IconUrl": "https://example.com/media/nunu-icon.png",
  "Tags": ["ai", "chat", "qol", "ffxiv"],
  "DalamudApiLevel": X
}
```

> Replace links and `DalamudApiLevel` with real values.

### Local Dev Install

* Build **Release**.
* Package with **DalamudPackager** to produce the zip.
* Add the zip to your local dev repo folder in Dalamud settings.

---

## 🕹 Usage

* `/nunu` — open/close the companion window
* `/nunu ask <text>` — send a quick prompt from chat
* `/nunu persona` — list or switch personas
* `/nunu off` — temporarily disable network calls

**UI basics**

* **Top bar:** provider status, token meter, persona switcher.
* **Main pane:** chat stream with inline code blocks and copy buttons.
* **Footer:** text box, send, and toggle for context rules.

---

## ⚙️ Configuration

Open the config panel via `/nunu` → **Settings**.

**Providers**

* **Endpoint**: Any OpenAI‑compatible base URL.
* **Model**: Free text field.
* **API Key**: Stored encrypted in the standard Dalamud config directory.

**Context**

* **Include recent chat** (N lines)
* **Include location** (zone, world)
* **Redact names/FC tags** (hashing or placeholder)
* **Duty Mode**: auto‑mute during instances

**Personas**

* Built‑ins: **Little Nunu**, **Lore Sage**, **Tactician**, **Cheer Coach**.
* Add your own via JSON in `config/personas/` or the UI editor.

---

## 🔒 Privacy & ToS

* No telemetry. Requests go only to the endpoint you configure.
* Redaction happens **before** any network call.
* This plugin is a **roleplay/companion tool**. It does **not** automate gameplay or execute actions on your behalf.
* Always comply with **Square Enix ToS** and community guidelines.

---

## 🧩 Development

**Prereqs**

* .NET SDK (match current Dalamud template requirements)
* Visual Studio 2022 or JetBrains Rider
* Dalamud (via XIVLauncher) for runtime

**Project layout**

```
src/
  NunuCompanionAppV2/
    Plugin.cs
    Configuration/
    Providers/
    Personas/
    UI/
assets/
  nunucompanion-banner.png
  nunu-icon.png
docs/
  media/
    ui.png
    demo.gif
```

**Build & Package**

```yaml
name: build
on: [push, pull_request]
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: 'latest' }
      - name: Restore & Build
        run: dotnet build -c Release
      - name: Package
        run: dotnet tool run DalamudPackager
      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: plugin
          path: artifacts/**
```

**Coding notes**

* Keep UI on `UiBuilder.Draw`; push work to background tasks.
* Separate provider client behind an interface for easy mocking.
* Wrap HTTP with timeouts and cancellation; surface errors via toasts and status.

**Testing**

* Core chat/session logic in a provider‑agnostic library.
* Unit tests for redaction, persona merge, and context building.

---

## 📸 Media

Place screenshots or GIFs under `docs/media/` and reference them here.

```md
![UI](docs/media/ui.png)
![Streaming Demo](docs/media/demo.gif)
```

---

## 🗺 Roadmap

* [ ] Multi‑provider round‑robin and failover
* [ ] Per‑job presets (switch persona by JobID)
* [ ] Prompt snippets & macros (text only)
* [ ] Live token cost estimator
* [ ] Import/export personas from JSON and links

---

## 🙌 Contributing

PRs welcome! Please:

* Explain the “why” of your change.
* Keep style consistent with `.editorconfig`.
* Add/update tests for behavior changes.

---

## 📄 License

MIT. See [`LICENSE`](LICENSE).
