using System.Collections.Generic;
using Dalamud.Configuration;
using Dalamud.Plugin;
using Dalamud.Game.Text;

namespace NunuCompanionAppV2;

public enum ReplyChannel
{
    Echo,
    Say,
    Party,
    Alliance,
    FreeCompany,
    Shout,
    Yell,
    Tell
}

public sealed class PluginConfig : IPluginConfiguration
{
    public int Version { get; set; } = 8;

    // LLM
    public string BaseUrl { get; set; } = "http://localhost:1234";
    public string ApiKey { get; set; } = "";
    public string Model { get; set; } = "gpt-4o-mini";
    public float Temperature { get; set; } = 0.7f;
    public int MaxTokens { get; set; } = 512;
    public int MaxHistory { get; set; } = 8;
    public string SystemPrompt { get; set; } =
        "You are Nunu Companion, a helpful, concise assistant for FFXIV players.";

    // Persona
    public bool UsePersonaFile { get; set; } = false;
    public string PersonaFilePath { get; set; } = "";
    public bool PersonaOnTop { get; set; } = true;
    public bool AutoReloadPersona { get; set; } = true;

    // Chat output
    public bool ReplyToChat { get; set; } = true;
    public bool Broadcast { get; set; } = true;
    public int BroadcastChunkLen { get; set; } = 440;
    public ReplyChannel ReplyChannel { get; set; } = ReplyChannel.Party;
    public string TellTarget { get; set; } = "";

    // Auto-listen / triggers / whitelist
    public bool EnableAutoListen { get; set; } = true;
    public bool MentionOnly { get; set; } = false;
    public string MentionToken { get; set; } = "@nunu";

    public bool ListenSay { get; set; } = true;
    public bool ListenParty { get; set; } = true;
    public bool ListenAlliance { get; set; } = false;
    public bool ListenFC { get; set; } = false;
    public bool ListenTell { get; set; } = false;

    public int PerSenderCooldownSec { get; set; } = 8;
    public int MaxReplyChars { get; set; } = 1200;

    public List<string> Whitelist { get; set; } = new();
    public List<string> Triggers { get; set; } = new() { "nunu", "help", "guide" };

    // extras
    public bool EnableMemory { get; set; } = true;
    public string Greeting { get; set; } = "Every note is a tether… every soul, a string.";

    private IDalamudPluginInterface? pi;
    public void Initialize(IDalamudPluginInterface pi) => this.pi = pi;
    public void Save() => pi?.SavePluginConfig(this);
}
