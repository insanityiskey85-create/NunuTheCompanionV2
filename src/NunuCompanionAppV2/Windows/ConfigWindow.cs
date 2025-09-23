using System.Numerics;
using Dalamud.Interface.Windowing;
using Dalamud.Bindings.ImGui;

namespace NunuCompanionAppV2.Windows;

public sealed class ConfigWindow : Window
{
    private readonly PluginConfig config;

    public ConfigWindow(PluginConfig config) : base("Nunu Companion App — Settings")
    {
        this.config = config;
        Size = new Vector2(420, 280);
        SizeCondition = ImGuiCond.FirstUseEver;
        RespectCloseHotkey = true;
    }

    public override void Draw()
    {
        bool changed = false;

        bool enable = config.EnableMemory;
        if (ImGui.Checkbox("Enable simple memory", ref enable))
        {
            config.EnableMemory = enable;
            changed = true;
        }

        string greet = config.Greeting ?? string.Empty;
        if (ImGui.InputText("Greeting", ref greet, 128))
        {
            config.Greeting = greet;
            changed = true;
        }

        if (changed) config.Save();

        ImGui.Spacing();
        if (ImGui.Button("Close")) IsOpen = false;
        ImGui.SameLine();
        ImGui.TextDisabled("Changes auto-save.");
    }
}
