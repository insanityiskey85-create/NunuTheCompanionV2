using System;
using System.Numerics;
using System.Threading;
using System.Threading.Tasks;
using Dalamud.Interface.Windowing;
using Dalamud.Bindings.ImGui;
using NunuCompanionAppV2.Models;
using NunuCompanionAppV2.Services;

namespace NunuCompanionAppV2.Windows;

public sealed class MainWindow : Window
{
    private readonly ChatService chat;
    private readonly PluginConfig cfg;

    private string input = string.Empty;
    private bool sending = false;
    private CancellationTokenSource? cts;

    public MainWindow(ChatService chat, PluginConfig cfg) : base("Nunu Companion — Chat")
    {
        this.chat = chat;
        this.cfg = cfg;

        Size = new Vector2(560, 480);
        SizeCondition = ImGuiCond.FirstUseEver;
        RespectCloseHotkey = true;

        chat.EnsureSystem(cfg.SystemPrompt);
    }

    public override void Draw()
    {
        if (ImGui.Button("Reset"))
            chat.Reset(cfg.SystemPrompt);
        ImGui.SameLine();
        ImGui.TextDisabled("Persona and settings apply live via Settings → Save & Apply.");

        ImGui.Separator();

        ImGui.BeginChild("chatlog", new Vector2(0, -80), true);
        foreach (var m in chat.History)
        {
            var prefix = m.Role switch { ChatRole.System => "[system] ", ChatRole.User => "> ", _ => "" };
            ImGui.TextWrapped(prefix + m.Content);
            ImGui.Spacing();
        }
        if (sending) ImGui.TextDisabled("…singing response…");
        ImGui.SetScrollHereY(1.0f);
        ImGui.EndChild();

        ImGui.PushItemWidth(-90);
        if (ImGui.InputTextMultiline("##nunu_input", ref input, 4000, new Vector2(0, 60),
            ImGuiInputTextFlags.EnterReturnsTrue))
        {
            _ = SendAsync();
        }
        ImGui.PopItemWidth();

        ImGui.SameLine();
        if (!sending)
        {
            if (ImGui.Button("Send") && !string.IsNullOrWhiteSpace(input))
                _ = SendAsync();
        }
        else
        {
            if (ImGui.Button("Stop"))
                cts?.Cancel();
        }
    }

    private async Task SendAsync()
    {
        var text = input.Trim();
        if (string.IsNullOrEmpty(text)) return;

        sending = true;
        cts = new CancellationTokenSource();
        input = string.Empty;

        try
        {
            await chat.SendAsync(text, cts.Token);
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            chat.AppendAssistant("[error] " + ex.Message);
        }
        finally
        {
            sending = false;
            cts.Dispose(); cts = null;
        }
    }
}
