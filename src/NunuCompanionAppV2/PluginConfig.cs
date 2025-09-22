using Dalamud.Configuration;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2;

public sealed class PluginConfig : IPluginConfiguration
{
    public int Version { get; set; } = 1;

    public bool   EnableMemory { get; set; } = true;
    public string Greeting     { get; set; } = "Every note is a tether… every soul, a string.";

    private IDalamudPluginInterface? pi;

    public void Initialize(IDalamudPluginInterface pi) => this.pi = pi;
    public void Save() => pi?.SavePluginConfig(this);
}
