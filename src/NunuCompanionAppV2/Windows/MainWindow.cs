using System.Numerics;
using Dalamud.Interface.Windowing;
using Dalamud.Bindings.ImGui;

namespace NunuCompanionAppV2.Windows;

public sealed class MainWindow : Window
{
    public MainWindow() : base("Nunu Companion App V2.0")
    {
        Size = new Vector2(480, 360);
        SizeCondition = ImGuiCond.FirstUseEver;
        RespectCloseHotkey = true;
    }

    public override void Draw()
    {
        ImGui.TextWrapped("WAH! Main UI callback is alive.");
        ImGui.Separator();
        if (ImGui.Button("Close")) IsOpen = false;
        ImGui.SameLine();
        ImGui.TextDisabled("Open via /nunu or /xlplugins → Open.");
    }
}
