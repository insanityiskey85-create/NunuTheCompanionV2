using Dalamud.Configuration;
using Dalamud.Plugin;
using NunuCompanionAppV2.Core;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace NunuCompanionAppV2;

public sealed class Configuration : IPluginConfiguration
{
    public int Version { get; set; } = 2;

    public string PersonaPath { get; set; } = @"Persona\Persona.json";

    public bool AutoReply { get; set; } = true;
    public string UserCallsign { get; set; } = "nunu";

    public List<ChatMemoryItem> Memory { get; set; } = new();

    [JsonIgnore] private IDalamudPluginInterface? _pi;

    public void Initialize(IDalamudPluginInterface pi) => _pi = pi;

    public void Save() => _pi?.SavePluginConfig(this);
}
