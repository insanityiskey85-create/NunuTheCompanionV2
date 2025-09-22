# nunu-scaffold.ps1 — create folder structure + write all source files (no build)

# ===== CONFIG =====
$Root              = 'C:\NunuCompanionApp V2.0'
$ProjectFolderName = 'Nunu Companion App V2.0'
$DisplayName       = 'Nunu Companion App V2.0'
$InternalName      = 'NunuCompanionAppV2'
$Author            = 'The Nunu'
$Punchline         = 'Persona + chat companion (V2).'
$Description       = 'Nunu Companion App (V2) — persona lives in plugin config; one-DLL drop.'
$DalamudApiLevel   = 9
$DalamudSdkVersion = '13.1.0'    # Dalamud.NET.Sdk version
$DotnetSdkVersion  = '8.0.4'     # Any 8.0.x is fine (host is .NET 8)
# ===================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Note([string]$m){ Write-Host "[*] $m" }
function Mk([string]$p){ if(!(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# 0) Directories
Mk $Root
$Proj = Join-Path $Root $ProjectFolderName
Mk $Proj; Mk (Join-Path $Proj 'Core'); Mk (Join-Path $Proj 'UI'); Mk (Join-Path $Proj 'Persona')
Note "Scaffold at: $Proj"

# 1) global.json + NuGet.config (root)
$globalJson = @{
  sdk = @{ version = $DotnetSdkVersion; rollForward = 'latestFeature' }
  'msbuild-sdks' = @{ 'Dalamud.NET.Sdk' = $DalamudSdkVersion }
} | ConvertTo-Json -Depth 5
Set-Content -LiteralPath (Join-Path $Root 'global.json') -Value $globalJson -Encoding UTF8

@'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
'@ | Set-Content -LiteralPath (Join-Path $Root 'NuGet.config') -Encoding UTF8

# 2) Project file (csproj)
$csproj = @"
<Project Sdk="Dalamud.NET.Sdk/$DalamudSdkVersion">
  <PropertyGroup>
    <TargetFramework>net8.0-windows</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>$InternalName</AssemblyName>
    <RootNamespace>$InternalName</RootNamespace>
    <DalamudManifest>$InternalName.yaml</DalamudManifest>
  </PropertyGroup>
  <ItemGroup Label="NunuAuto">
    <None Include="$InternalName.yaml" CopyToOutputDirectory="Always" />
    <EmbeddedResource Include="Persona\DefaultPersona.json" />
  </ItemGroup>
</Project>
"@
Set-Content -LiteralPath (Join-Path $Proj "$InternalName.csproj") -Value $csproj -Encoding UTF8

# 3) Manifest (snake_case)
$manifest = @"
# Dalamud manifest (YAML)
name: $DisplayName
author: $Author
punchline: $Punchline
description: |-
  $Description
internal_name: $InternalName
dalamud_api_level: $DalamudApiLevel
dll:
  - "$InternalName.dll"
repo_url:
tags: [utility, chat, nunu]
"@
Set-Content -LiteralPath (Join-Path $Proj "$InternalName.yaml") -Value $manifest -Encoding UTF8

# 4) Plugin.cs (entrypoint, /nunu toggle, window system)
$pluginCs = @"
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using Dalamud.Interface.Windowing;
using Dalamud.Game.Command;
using System.IO;
using $InternalName.Core;
using $InternalName.UI;

namespace $InternalName;

public sealed class Plugin : IDalamudPlugin
{
    public string Name => "$DisplayName";

    [PluginService] internal static IDalamudPluginInterface PluginInterface { get; set; } = null!;
    [PluginService] internal static IChatGui ChatGui { get; set; } = null!;
    [PluginService] internal static ICommandManager CommandManager { get; set; } = null!;
    [PluginService] internal static IPluginLog Log { get; set; } = null!;

    private readonly WindowSystem windows = new("$DisplayName");
    private readonly PluginConfig config;
    private readonly PersonaStore persona;
    private readonly IAiBrain brain;
    private readonly ChatRouter router;
    private readonly ChatWindow chatWindow;

    private const string Command = "/nunu";

    public Plugin()
    {
        // Config
        config = PluginInterface.GetPluginConfig() as PluginConfig ?? new PluginConfig { Version = 1 };

        // Persona file in plugin config dir (copy from embedded on first run)
        var cfgDir = PluginInterface.GetPluginConfigDirectory();
        var personaPath = Path.Combine(cfgDir, "persona.json");
        if (!File.Exists(personaPath))
        {
            using var s = typeof(Plugin).Assembly.GetManifestResourceStream("$InternalName.Persona.DefaultPersona.json");
            if (s != null)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(personaPath)!);
                using var fs = File.Create(personaPath);
                s.CopyTo(fs);
            }
        }
        persona = new PersonaStore(personaPath);

        // Brain + Router + UI
        brain = new MockBrain();
        router = new ChatRouter(persona, brain, SaveConfig);
        chatWindow = new ChatWindow(router, persona, SaveConfig) { IsOpen = true };
        windows.AddWindow(chatWindow);

        // Command + UI hooks
        CommandManager.AddHandler(Command, new CommandInfo(OnCommand) { HelpMessage = "Open/close Nunu chat." });
        PluginInterface.UiBuilder.Draw += () => windows.Draw();
        PluginInterface.UiBuilder.OpenMainUi += () => chatWindow.IsOpen = true;

        ChatGui.Print("[$InternalName] Loaded — WAH!");
    }

    private void OnCommand(string cmd, string args)
    {
        chatWindow.IsOpen = !chatWindow.IsOpen;
        config.ChatOpen = chatWindow.IsOpen;
        SaveConfig();
    }

    public void Dispose()
    {
        windows.RemoveAllWindows();
        CommandManager.RemoveHandler(Command);
        ChatGui.Print("[$InternalName] Unloaded.");
    }

    private void SaveConfig() => PluginInterface.SavePluginConfig(config);
}

public sealed class PluginConfig : IPluginConfiguration
{
    public int Version { get; set; } = 1;
    public bool ChatOpen { get; set; } = true;
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'Plugin.cs') -Value $pluginCs -Encoding UTF8

# 5) Core files
$models = @"
namespace $InternalName.Core;

public enum Role { System, User, Assistant }
public sealed record Message(Role Role, string Content);

public sealed record PersonaData(string Name, string Greeting, string Style)
{
    public static PersonaData Default => new(
        ""The Nunu"",
        ""Every note is a tether… every soul, a string."",
        ""Playful, void-touched bard who bargains in songs and memories.""
    );
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'Core\Models.cs') -Value $models -Encoding UTF8

$brainIface = @"
using System.Collections.Generic;

namespace $InternalName.Core;
public interface IAiBrain
{
    string GenerateResponse(List<Message> history, PersonaData persona);
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'Core\IAiBrain.cs') -Value $brainIface -Encoding UTF8

$brainMock = @"
using System;
using System.Collections.Generic;
using System.Linq;

namespace $InternalName.Core;

public sealed class MockBrain : IAiBrain
{
    public string GenerateResponse(List<Message> history, PersonaData persona)
    {
        var last = history.LastOrDefault(m => m.Role == Role.User);
        if (last is null) return persona.Greeting;

        var t = last.Content.Trim();

        if (t.Equals(""help"", StringComparison.OrdinalIgnoreCase))
            return ""Commands: /persona name X, /persona greet X, /persona style X, /clear."";

        if (t.Contains(""who are you"", StringComparison.OrdinalIgnoreCase))
            return $""I am {persona.Name}, {persona.Style.ToLowerInvariant()}."";

        if (t.Contains(""thank"", StringComparison.OrdinalIgnoreCase))
            return ""You're welcome. Walk the melody with me."";

        return $""{persona.Name} hums back: '{(t.Length<=120?t:t[..120]+""…"")}'"";
    }
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'Core\MockBrain.cs') -Value $brainMock -Encoding UTF8

$personaStore = @"
using System.IO;
using System.Text.Json;

namespace $InternalName.Core;

public sealed class PersonaStore
{
    private readonly string path;
    private PersonaData data;

    public PersonaStore(string path)
    {
        this.path = path;
        this.data = LoadOrDefault(path);
    }

    public PersonaData Current => data;

    public void SetName(string name)     => data = data with { Name = string.IsNullOrWhiteSpace(name) ? PersonaData.Default.Name : name.Trim() };
    public void SetGreeting(string greet)=> data = data with { Greeting = string.IsNullOrWhiteSpace(greet) ? PersonaData.Default.Greeting : greet.Trim() };
    public void SetStyle(string style)   => data = data with { Style = string.IsNullOrWhiteSpace(style) ? PersonaData.Default.Style : style.Trim() };

    public void Save()
    {
        var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json);
    }

    private static PersonaData LoadOrDefault(string p)
    {
        try
        {
            if (File.Exists(p))
            {
                var json = File.ReadAllText(p);
                var? loaded = JsonSerializer.Deserialize<PersonaData>(json);
                if (loaded != null) return loaded;
            }
        } catch { }
        return PersonaData.Default;
    }
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'Core\PersonaStore.cs') -Value $personaStore -Encoding UTF8

$router = @"
using System.Collections.Generic;
using System.Text;

namespace $InternalName.Core;

/// Routes user input to commands or the brain.
public sealed class ChatRouter
{
    private readonly PersonaStore persona;
    private readonly IAiBrain brain;
    private readonly System.Action save;
    private readonly List<Message> history = new();

    public ChatRouter(PersonaStore persona, IAiBrain brain, System.Action saveConfig)
    {
        this.persona = persona;
        this.brain = brain;
        this.save = saveConfig;
        history.Add(new Message(Role.System, $""You are {persona.Current.Name}: {persona.Current.Style}. Greeting: {persona.Current.Greeting}""));
    }

    public IReadOnlyList<Message> History => history;

    public string Handle(string input, out bool wasCommand)
    {
        wasCommand = false;
        var text = (input ?? string.Empty).Trim();
        if (string.IsNullOrEmpty(text)) return string.Empty;

        if (text.StartsWith(""/""))
        {
            wasCommand = true;
            return HandleCommand(text);
        }

        history.Add(new Message(Role.User, text));
        var reply = brain.GenerateResponse(history, persona.Current);
        history.Add(new Message(Role.Assistant, reply));
        return reply;
    }

    private string HandleCommand(string cmd)
    {
        var parts = cmd.Split(' ', 3, System.StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return Help();

        var root = parts[0].ToLowerInvariant();
        if (root is ""/help"" or ""/nunuhelp"") return Help();
        if (root is ""/clear"")
        {
            history.Clear();
            history.Add(new Message(Role.System, $""You are {persona.Current.Name}: {persona.Current.Style}. Greeting: {persona.Current.Greeting}""));
            return ""Cleared chat history."";
        }

        if (root is ""/persona"" && parts.Length >= 2)
        {
            var sub = parts[1].ToLowerInvariant();
            var value = parts.Length == 3 ? parts[2] : string.Empty;

            if (sub is ""name"")  { persona.SetName(value);  save(); return $""Persona name set to '{persona.Current.Name}'.""; }
            if (sub is ""greet"" or ""greeting"") { persona.SetGreeting(value); persona.Save(); return ""Persona greeting updated.""; }
            if (sub is ""style"") { persona.SetStyle(value); persona.Save(); return ""Persona style updated.""; }

            return ""Usage: /persona name|greet|style <text>"";
        }

        return Help();
    }

    private static string Help()
    {
        var sb = new StringBuilder();
        sb.AppendLine(""Commands:"");
        sb.AppendLine(""  /nunu             -> open/close chat window"");
        sb.AppendLine(""  /help             -> this help"");
        sb.AppendLine(""  /clear            -> clear chat history"");
        sb.AppendLine(""  /persona name X   -> set persona name"");
        sb.AppendLine(""  /persona greet X  -> set greeting"");
        sb.AppendLine(""  /persona style X  -> set descriptive style"");
        return sb.ToString();
    }
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'Core\ChatRouter.cs') -Value $router -Encoding UTF8

# 6) UI/ChatWindow.cs (ImGui)
$ui = @"
using System.Collections.Generic;
using Dalamud.Interface.Windowing;
using ImGuiNET;
using $InternalName.Core;

namespace $InternalName.UI;

public sealed class ChatWindow : Window
{
    private readonly ChatRouter router;
    private readonly PersonaStore persona;
    private readonly System.Action saveConfig;

    private readonly List<(string role, string text)> log = new();
    private string input = string.Empty;
    private bool autoScroll = true;

    public ChatWindow(ChatRouter router, PersonaStore persona, System.Action saveConfig)
        : base(""Nunu Chat"", ImGuiWindowFlags.NoScrollbar | ImGuiWindowFlags.NoScrollWithMouse)
    {
        this.router = router;
        this.persona = persona;
        this.saveConfig = saveConfig;
        Size = new System.Numerics.Vector2(520, 420);
        SizeCondition = ImGuiCond.FirstUseEver;
        log.Add((""System"", $""Persona: {persona.Current.Name} — \""{persona.Current.Greeting}\""""));
    }

    public override void Draw()
    {
        ImGui.TextDisabled($""Persona: {persona.Current.Name}"");
        ImGui.SameLine();
        if (ImGui.Button(""Help"")) Push(""/help"");
        ImGui.SameLine();
        if (ImGui.Button(""Clear"")) Push(""/clear"");

        ImGui.Separator();

        if (ImGui.BeginChild(""scroll"", new System.Numerics.Vector2(0, -32), true))
        {
            foreach (var (role, text) in log)
            {
                ImGui.TextWrapped($""[{role}] {text}"");
            }
            if (autoScroll && ImGui.GetScrollY() >= ImGui.GetScrollMaxY())
                ImGui.SetScrollHereY(1.0f);
        }
        ImGui.EndChild();

        ImGui.PushItemWidth(-1);
        if (ImGui.InputText(""##nunu-input"", ref input, 1024, ImGuiInputTextFlags.EnterReturnsTrue))
        {
            Submit();
        }
        ImGui.PopItemWidth();
    }

    private void Submit()
    {
        var text = (input ?? string.Empty).Trim();
        input = string.Empty;
        if (string.IsNullOrEmpty(text)) return;

        log.Add(("User", text));
        var reply = router.Handle(text, out var wasCmd);
        if (!string.IsNullOrEmpty(reply))
        {
            foreach (var line in reply.ReplaceLineEndings("" \n"").Split('\n'))
                log.Add(("Nunu", line));
        }
    }

    private void Push(string cmd)
    {
        log.Add(("User", cmd));
        var reply = router.Handle(cmd, out _);
        if (!string.IsNullOrEmpty(reply)) log.Add(("Nunu", reply));
    }
}
"@
Set-Content -LiteralPath (Join-Path $Proj 'UI\ChatWindow.cs') -Value $ui -Encoding UTF8

# 7) Persona default JSON (embedded; copied to config on first run)
$personaJson = @'
{
  "Name": "The Nunu",
  "Greeting": "Every note is a tether… every soul, a string.",
  "Style": "Playful, void-touched bard who bargains in songs and memories."
}
'@
Set-Content -LiteralPath (Join-Path $Proj 'Persona\DefaultPersona.json') -Value $personaJson -Encoding UTF8

# 8) Optional: write a solution file that references the project (nice for IDEs)
Push-Location $Root
try {
  dotnet new sln -n NunuCompanionApp --force | Out-Null
  dotnet sln .\NunuCompanionApp.sln add (Join-Path $Proj "$InternalName.csproj") | Out-Null
} catch { } finally { Pop-Location }

Note "All files written. Next step: run 'dotnet build -c Release' from '$Proj'."
