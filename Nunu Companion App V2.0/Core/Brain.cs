using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2.Core;

public sealed class Brain
{
    private readonly Configuration _config;
    private readonly PersonaStore _persona;
    private readonly IPluginLog _log;

    public IReadOnlyList<ChatMemoryItem> Memory => _config.Memory;

    public Brain(Configuration config, PersonaStore persona, IPluginLog log)
    {
        _config = config;
        _persona = persona;
        _log = log;
    }

    public void Remember(string user, string text)
    {
        _config.Memory.Add(new ChatMemoryItem(user, text));
        if (_config.Memory.Count > 256)
            _config.Memory.RemoveAt(0);
        _config.Save();
    }

    public bool ShouldAnswer(string message, out string matchedCallsign)
    {
        var all = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var c in _persona.Current.Callsigns) all.Add(c);
        if (!string.IsNullOrWhiteSpace(_config.UserCallsign)) all.Add(_config.UserCallsign);

        foreach (var c in all)
        {
            if (!string.IsNullOrWhiteSpace(c) && message.Contains(c, StringComparison.OrdinalIgnoreCase))
            {
                matchedCallsign = c;
                return true;
            }
        }

        matchedCallsign = "";
        return false;
    }

    public string ComposeReply(string speaker, string message, string matchedCallsign)
    {
        var p = _persona.Current;
        var greet = p.Greetings.Count > 0 ? p.Greetings[new Random().Next(p.Greetings.Count)] : "Well met.";
        var tone = string.IsNullOrWhiteSpace(p.Style) ? "warm" : p.Style;

        var recent = Memory.Reverse().Take(3).Select(m => $"{m.User}: {m.Text}").ToList();
        var recap = recent.Count > 0 ? $" I recall: {string.Join(" | ", recent)}." : string.Empty;

        var sb = new StringBuilder();
        sb.Append($"{greet} {speaker}, you called \"{matchedCallsign}\". ");
        sb.Append($"({tone}) ");
        sb.Append(ReplyCore(message));
        sb.Append(recap);

        return sb.ToString().Trim();
    }

    private static string ReplyCore(string message)
    {
        if (message.Contains("bye", StringComparison.OrdinalIgnoreCase))
            return "May your path be ever bright.";
        if (message.Contains("thanks", StringComparison.OrdinalIgnoreCase))
            return "Think nothing of it.";
        if (message.Contains("where", StringComparison.OrdinalIgnoreCase))
            return "If you seek directions, the aetheryte plaza is ever a good start.";
        if (message.Contains("help", StringComparison.OrdinalIgnoreCase))
            return "Ask, and I shall do what I can.";
        return "What would you have of me?";
    }
}
