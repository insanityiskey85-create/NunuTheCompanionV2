using System;
using System.Collections.Generic;
using Dalamud.Configuration;

namespace NunuCompanionAppV2.Core;

[Serializable]
public sealed class Configuration : IPluginConfiguration
{
    public int Version { get; set; } = 2;

    // Behavior
    public bool AutoReplyEnabled { get; set; } = true;

    // Callsign to trigger replies (at message start)
    public string Callsign { get; set; } = "!nunu";

    // Other trigger tokens accepted anywhere
    public List<string> ExtraTriggers { get; set; } = new() { "nunu", "nunubu", "soul weeper" };

    // Which chat channels can trigger (names of XivChatType)
    public List<string> AllowedChannels { get; set; } = new() { "Say", "TellIncoming", "Party" };

    // Anti-spam
    public int CooldownMs { get; set; } = 3000;
    public int MaxRepliesPerMinute { get; set; } = 12;

    // Memory log for the Brain
    public List<MemoryItem> Memories { get; set; } = new();

    [NonSerialized] private Action<Configuration>? saver;
    public void BindSaver(Action<Configuration> s) => saver = s;
    public void Save() => saver?.Invoke(this);

    [Serializable]
    public sealed class MemoryItem
    {
        public int Id { get; set; }
        public string Sender { get; set; } = "";
        public string Text { get; set; } = "";
        public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.Now;
    }
}
