using System;
using System.Linq;
using System.Numerics;
using Dalamud.Interface.Windowing;
using Dalamud.Bindings.ImGui;

namespace NunuCompanionAppV2.Windows;

public sealed class ConfigWindow : Window
{
    private readonly PluginConfig cfg;
    private readonly Action onSaveAndApply;
    private readonly Action onResetDefaults;

    // staged fields
    private string baseUrl = "", apiKey = "", model = "", systemPrompt = "";
    private float temp; private int maxTokens, maxHist;

    // persona
    private bool usePersonaFile, personaOnTop, autoReloadPersona;
    private string personaFilePath = "";

    // chat output
    private bool replyToChat, broadcast;
    private int broadcastChunkLen;
    private ReplyChannel replyChannel;
    private string tellTarget = "";

    // listen
    private bool enableListen, mentionOnly;
    private string mentionToken = "@nunu";
    private bool lSay, lParty, lAlliance, lFC, lTell;
    private int cooldownSec, maxReplyChars;

    private string whiteAdd = "", trigAdd = "";
    private bool dirty;

    public ConfigWindow(PluginConfig cfg, Action onSaveAndApply, Action onResetDefaults)
        : base("Nunu Companion — Settings")
    {
        this.cfg = cfg;
        this.onSaveAndApply = onSaveAndApply;
        this.onResetDefaults = onResetDefaults;

        Size = new Vector2(760, 720);
        SizeCondition = ImGuiCond.FirstUseEver;
        RespectCloseHotkey = true;

        LoadStage();
    }

    private void LoadStage()
    {
        baseUrl = cfg.BaseUrl; apiKey = cfg.ApiKey; model = cfg.Model;
        temp = cfg.Temperature; maxTokens = cfg.MaxTokens; maxHist = cfg.MaxHistory;
        systemPrompt = cfg.SystemPrompt;

        usePersonaFile = cfg.UsePersonaFile; personaFilePath = cfg.PersonaFilePath;
        personaOnTop = cfg.PersonaOnTop; autoReloadPersona = cfg.AutoReloadPersona;

        replyToChat = cfg.ReplyToChat; broadcast = cfg.Broadcast; broadcastChunkLen = cfg.BroadcastChunkLen;
        replyChannel = cfg.ReplyChannel; tellTarget = cfg.TellTarget;

        enableListen = cfg.EnableAutoListen; mentionOnly = cfg.MentionOnly; mentionToken = cfg.MentionToken;
        lSay = cfg.ListenSay; lParty = cfg.ListenParty; lAlliance = cfg.ListenAlliance; lFC = cfg.ListenFC; lTell = cfg.ListenTell;

        cooldownSec = cfg.PerSenderCooldownSec; maxReplyChars = cfg.MaxReplyChars;

        dirty = false;
    }

    private void Commit()
    {
        cfg.BaseUrl = baseUrl; cfg.ApiKey = apiKey; cfg.Model = model;
        cfg.Temperature = temp; cfg.MaxTokens = maxTokens; cfg.MaxHistory = maxHist;
        cfg.SystemPrompt = systemPrompt;

        cfg.UsePersonaFile = usePersonaFile; cfg.PersonaFilePath = personaFilePath;
        cfg.PersonaOnTop = personaOnTop; cfg.AutoReloadPersona = autoReloadPersona;

        cfg.ReplyToChat = replyToChat; cfg.Broadcast = broadcast; cfg.BroadcastChunkLen = broadcastChunkLen;
        cfg.ReplyChannel = replyChannel; cfg.TellTarget = tellTarget;

        cfg.EnableAutoListen = enableListen; cfg.MentionOnly = mentionOnly; cfg.MentionToken = mentionToken;
        cfg.ListenSay = lSay; cfg.ListenParty = lParty; cfg.ListenAlliance = lAlliance; cfg.ListenFC = lFC; cfg.ListenTell = lTell;

        cfg.PerSenderCooldownSec = cooldownSec; cfg.MaxReplyChars = maxReplyChars;
    }

    public override void Draw()
    {
        bool changed = false;

        // LLM
        if (ImGui.InputText("Base URL", ref baseUrl, 512)) changed = true;
        if (ImGui.InputText("API Key (plaintext!)", ref apiKey, 512, ImGuiInputTextFlags.Password)) changed = true;
        if (ImGui.InputText("Model", ref model, 128)) changed = true;
        if (ImGui.SliderFloat("Temperature", ref temp, 0.0f, 1.5f)) changed = true;
        if (ImGui.SliderInt("Max Tokens", ref maxTokens, 64, 4096)) changed = true;
        if (ImGui.SliderInt("Max History (pairs)", ref maxHist, 1, 16)) changed = true;
        ImGui.Text("System Prompt");
        if (ImGui.InputTextMultiline("##sys", ref systemPrompt, 8000, new Vector2(0, 100))) changed = true;

        ImGui.Separator();

        // Persona
        ImGui.Text("Persona");
        if (ImGui.Checkbox("Use persona file", ref usePersonaFile)) changed = true;
        ImGui.SameLine();
        if (ImGui.Checkbox("Auto-reload persona", ref autoReloadPersona)) changed = true;

        if (ImGui.InputText("Persona file path", ref personaFilePath, 512)) changed = true;
        ImGui.TextDisabled("Enter full path to .txt/.md persona file (UTF-8).");

        if (ImGui.Checkbox("Place persona before base prompt", ref personaOnTop)) changed = true;

        ImGui.Separator();

        // Chat output
        if (ImGui.Checkbox("Reply to game chat", ref replyToChat)) changed = true;
        if (ImGui.Checkbox("Broadcast (send via chat command)", ref broadcast)) changed = true;
        if (ImGui.SliderInt("Chunk Length", ref broadcastChunkLen, 120, 500)) changed = true;

        if (ImGui.BeginCombo("Reply Channel", replyChannel.ToString()))
        {
            foreach (ReplyChannel ch in Enum.GetValues(typeof(ReplyChannel)))
            {
                bool sel = replyChannel == ch;
                if (ImGui.Selectable(ch.ToString(), sel)) { replyChannel = ch; changed = true; }
                if (sel) ImGui.SetItemDefaultFocus();
            }
            ImGui.EndCombo();
        }
        if (replyChannel == ReplyChannel.Tell)
        {
            if (ImGui.InputText("Tell Target (Name@World)", ref tellTarget, 64)) changed = true;
        }

        ImGui.Separator();

        // Auto-listen & triggers
        if (ImGui.Checkbox("Enable Auto-Listen", ref enableListen)) changed = true;
        if (ImGui.Checkbox("Require mention token", ref mentionOnly)) changed = true;
        if (ImGui.InputText("Mention token", ref mentionToken, 64)) changed = true;

        ImGui.Text("Listen in channels:");
        ImGui.Columns(5, "chcols", false);
        changed |= ImGui.Checkbox("Say", ref lSay); ImGui.NextColumn();
        changed |= ImGui.Checkbox("Party", ref lParty); ImGui.NextColumn();
        changed |= ImGui.Checkbox("Alliance", ref lAlliance); ImGui.NextColumn();
        changed |= ImGui.Checkbox("FC", ref lFC); ImGui.NextColumn();
        changed |= ImGui.Checkbox("Tell", ref lTell);
        ImGui.Columns(1);

        ImGui.SliderInt("Per-sender cooldown (sec)", ref cooldownSec, 0, 60);
        ImGui.SliderInt("Max reply characters", ref maxReplyChars, 200, 4000);

        ImGui.Separator();
        ImGui.Text("Whitelist (exact player names)");
        ImGui.InputText("Add name", ref whiteAdd, 64); ImGui.SameLine();
        if (ImGui.Button("Add##wl") && !string.IsNullOrWhiteSpace(whiteAdd))
        {
            if (!cfg.Whitelist.Any(n => n.Equals(whiteAdd, StringComparison.OrdinalIgnoreCase)))
                cfg.Whitelist.Add(whiteAdd.Trim());
            whiteAdd = ""; changed = true;
        }
        for (int i = 0; i < cfg.Whitelist.Count; i++)
        {
            var name = cfg.Whitelist[i];
            ImGui.BulletText(name); ImGui.SameLine();
            if (ImGui.SmallButton($"Remove##wl{i}")) { cfg.Whitelist.RemoveAt(i); i--; changed = true; }
        }

        ImGui.Separator();
        ImGui.Text("Triggers (keywords; case-insensitive)");
        ImGui.InputText("Add trigger", ref trigAdd, 64); ImGui.SameLine();
        if (ImGui.Button("Add##tr") && !string.IsNullOrWhiteSpace(trigAdd))
        {
            if (!cfg.Triggers.Any(t => t.Equals(trigAdd, StringComparison.OrdinalIgnoreCase)))
                cfg.Triggers.Add(trigAdd.Trim());
            trigAdd = ""; changed = true;
        }
        for (int i = 0; i < cfg.Triggers.Count; i++)
        {
            var t = cfg.Triggers[i];
            ImGui.BulletText(t); ImGui.SameLine();
            if (ImGui.SmallButton($"Remove##tr{i}")) { cfg.Triggers.RemoveAt(i); i--; changed = true; }
        }

        if (changed) dirty = true;

        ImGui.Separator();
        if (ImGui.Button("Save & Apply"))
        {
            Commit(); cfg.Save(); onSaveAndApply(); dirty = false;
        }
        ImGui.SameLine();
        if (ImGui.Button("Reset to Defaults"))
        {
            onResetDefaults(); LoadStage();
        }
        ImGui.SameLine();
        if (ImGui.Button("Close")) IsOpen = false;

        if (dirty) { ImGui.SameLine(); ImGui.TextDisabled(" (unsaved changes)"); }
    }
}
