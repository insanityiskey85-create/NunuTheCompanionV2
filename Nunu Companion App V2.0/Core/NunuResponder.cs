using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Dalamud.Plugin.Services;
using NunuCompanionAppV2.Core.Persona;

namespace NunuCompanionAppV2.Core;

public sealed class NunuResponder
{
    private readonly IChatGui chat;
    private readonly IPluginLog log;
    private readonly Brain brain;
    private readonly Configuration config;

    public PersonaProfile Persona { get; private set; }

    private DateTimeOffset lastReply = DateTimeOffset.MinValue;
    private readonly Queue<DateTimeOffset> replyTimestamps = new();

    public NunuResponder(IChatGui chat, IPluginLog log, Brain brain, Configuration config, PersonaProfile persona)
    {
        this.chat = chat;
        this.log = log;
        this.brain = brain;
        this.config = config;
        this.Persona = persona;
    }

    public void UpdatePersona(PersonaProfile p) => Persona = p;

    public void Hook(ChatRouter router) => router.OnMessage += OnChat;
    public void Unhook(ChatRouter router) => router.OnMessage -= OnChat;

    public string Ask(string sender, string query) => ComposeReply(sender, query, "Say");

    private void OnChat(ChatRecord rec)
    {
        if (!config.AutoReplyEnabled) return;

        if (config.AllowedChannels.Count > 0 &&
            !config.AllowedChannels.Contains(rec.Type ?? "", StringComparer.OrdinalIgnoreCase))
            return;

        if (!IsTriggered(rec.Message ?? "")) return;
        if (!CanReplyNow()) return;

        var (speaker, query) = ExtractSpeakerQuery(rec.Sender ?? "Traveler", rec.Message ?? "");
        var reply = ComposeReply(speaker, query, rec.Type ?? "Say");
        chat.Print($"[Nunu] {reply}");
        MarkReply();
    }

    private bool IsTriggered(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;

        var cs = (config.Callsign ?? "").Trim();
        if (!string.IsNullOrEmpty(cs) && text.TrimStart().StartsWith(cs, StringComparison.OrdinalIgnoreCase))
            return true;

        foreach (var t in (config.ExtraTriggers ?? new()))
            if (!string.IsNullOrWhiteSpace(t) && text.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)
                return true;

        foreach (var t in Persona.GetTriggers())
            if (text.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)
                return true;

        return false;
    }

    private static (string speaker, string query) ExtractSpeakerQuery(string sender, string raw)
    {
        var t = (raw ?? "").Trim();
        var firstSpace = t.IndexOf(' ');
        if (firstSpace > 0)
        {
            var head = t[..firstSpace].TrimEnd(',', ':');
            if (head.StartsWith("!nunu", StringComparison.OrdinalIgnoreCase) ||
                head.StartsWith("@nunu", StringComparison.OrdinalIgnoreCase) ||
                head.Equals("nunu", StringComparison.OrdinalIgnoreCase))
            {
                t = t[(firstSpace + 1)..].Trim();
            }
        }
        return (sender, t);
    }

    private bool CanReplyNow()
    {
        var now = DateTimeOffset.Now;
        if ((now - lastReply).TotalMilliseconds < Math.Max(0, config.CooldownMs)) return false;

        var cutoff = now.AddMinutes(-1);
        while (replyTimestamps.Count > 0 && replyTimestamps.Peek() < cutoff) replyTimestamps.Dequeue();
        if (replyTimestamps.Count >= Math.Max(1, config.MaxRepliesPerMinute)) return false;

        return true;
    }

    private void MarkReply()
    {
        lastReply = DateTimeOffset.Now;
        replyTimestamps.Enqueue(lastReply);
    }

    private string ComposeReply(string sender, string query, string channel)
    {
        var core = new StringBuilder();

        if (string.IsNullOrWhiteSpace(query))
            core.Append("You pluck a string with no question; the aether hums anyway.");
        else
            core.Append("You ask: '").Append(query).Append("'. ");

        var hits = brain.Recall(query, 2).ToArray();
        if (hits.Length > 0)
        {
            core.Append("Threads I keep: ");
            for (var i = 0; i < hits.Length; i++)
            {
                if (i > 0) core.Append(" | ");
                core.Append('[').Append(hits[i].Id).Append("] ").Append(hits[i].Text);
            }
            core.Append(". ");
        }

        var whisper = Persona.GetWhisper();
        var punch = Persona.GetPunch();

        return LoreWeaver.Shape(Persona, sender, query, core.ToString(), whisper, punch);
    }
}
