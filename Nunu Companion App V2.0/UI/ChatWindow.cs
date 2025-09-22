using Dalamud.Plugin.Services;
using NunuCompanionAppV2.Core;

namespace NunuCompanionAppV2.UI;

public sealed class ChatWindow
{
    private readonly Brain _brain;
    private readonly PersonaStore _persona;
    private readonly Configuration _config;
    private readonly IPluginLog _log;

    public bool IsOpen { get; set; }

    public ChatWindow(Brain brain, PersonaStore persona, Configuration config, IPluginLog log)
    {
        _brain = brain;
        _persona = persona;
        _config = config;
        _log = log;
    }

    // No ImGui dependency; safe no-op to keep UI hook alive.
    public void Draw()
    {
        // Intentionally blank until ImGuiNET is available.
    }
}
