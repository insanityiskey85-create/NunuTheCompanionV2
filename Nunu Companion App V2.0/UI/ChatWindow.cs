using Dalamud.Interface.Utility;
using Dalamud.Plugin.Services;
using ImGuiNET;
using NunuCompanionAppV2.Core;
using NunuCompanionAppV2.Core.Persona;
using System;
using System.Numerics;

namespace NunuCompanionAppV2.UI;

public sealed class ChatWindow
{
    private readonly NunuResponder responder;
    private readonly Brain brain;
    private readonly Configuration config;
    private readonly IPluginLog log;

    private PersonaProfile persona;

    private bool isOpen = true;
    private string input = string.Empty;
    private Vector2 size = new(520, 360);

    public ChatWindow(NunuResponder responder, Brain brain, Configuration config, PersonaProfile persona, IPluginLog log)
    {
        this.responder = responder;
        this.brain = brain;
        this.config = config;
        this.persona = persona;
        this.log = log;
    }

    public void Toggle() => isOpen = !isOpen;
    public void UpdatePersona(PersonaProfile p) => persona = p;

    public void Draw()
    {
        if (!isOpen) return;

        ImGui.SetNextWindowSize(size, ImGuiCond.FirstUseEver);
        if (!ImGui.Begin("Nunu Companion", ref isOpen, ImGuiWindowFlags.NoScrollbar))
        {
            ImGui.End();
            return;
        }

        // Header / toggles
        ImGui.Text($"Auto-reply: {(config.AutoReplyEnabled ? "ON" : "OFF")}");
        ImGui.SameLine();
        bool auto = config.AutoReplyEnabled;
        if (ImGui.Checkbox("##auto", ref auto))
        {
            config.AutoReplyEnabled = auto;
            config.Save();
        }
        ImGui.SameLine();
        ImGui.Text("Callsign:");
        ImGui.SameLine();
        var cs = config.Callsign ?? string.Empty;
        ImGui.SetNextItemWidth(120f);
        if (ImGui.InputText("##callsign", ref cs, 64))
        {
            config.Callsign = cs;
            config.Save();
        }

        // Transcript
        ImGui.Separator();
        if (ImGui.BeginChild("##scroll", new Vector2(0, -80)))
        {
            foreach (var m in brain.Recent(10))
                ImGui.TextUnformatted($"[{m.Timestamp:HH:mm}] {m.Sender}: {m.Text}");
        }
        ImGui.EndChild();

        // Ask row
        ImGui.SetNextItemWidth(-130f);
        bool submit = ImGui.InputTextWithHint("##ask", "Ask Nunu…", ref input, 500, ImGuiInputTextFlags.EnterReturnsTrue);
        ImGui.SameLine();
        submit |= ImGui.Button("Ask", new Vector2(120, 26));

        if (submit)
        {
            string q = input.Trim();
            if (q.Length > 0)
            {
                var reply = responder.Ask("You", q);
                brain.Remember("You", q);
                brain.Remember("Nunu", reply);
                input = string.Empty;
            }
        }

        if (ImGui.Button("Reload Persona"))
        {
            ImGui.OpenPopup("ReloadInfo");
        }
        if (ImGui.BeginPopup("ReloadInfo"))
        {
            ImGui.TextUnformatted("Use /nunu reload to re-read Persona.json from disk.");
            ImGui.EndPopup();
        }

        ImGui.End();
    }
}
