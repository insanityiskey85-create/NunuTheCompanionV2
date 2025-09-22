using System;
using System.Collections.Generic;
using System.Linq;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2.Core;

public sealed class Brain
{
    private readonly Configuration config;
    private readonly IPluginLog log;
    private readonly object gate = new();

    public Brain(Configuration config, IPluginLog log)
    {
        this.config = config;
        this.log = log;
    }

    public void Remember(string sender, string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;

        var now = DateTimeOffset.Now;
        lock (gate)
        {
            var nextId = (config.Memories.Count == 0) ? 1 : config.Memories.Max(m => m.Id) + 1;
            var item = new Configuration.MemoryItem
            {
                Id = nextId,
                Sender = sender ?? string.Empty,
                Text = text.Trim(),
                Timestamp = now
            };

            config.Memories.Add(item);

            const int cap = 500;
            if (config.Memories.Count > cap)
            {
                var removeCount = config.Memories.Count - cap;
                foreach (var old in config.Memories.OrderBy(m => m.Timestamp).Take(removeCount).ToList())
                    config.Memories.Remove(old);
            }

            config.Save();
        }
    }

    public IEnumerable<Configuration.MemoryItem> Recall(string? query, int k)
    {
        if (k <= 0) return Array.Empty<Configuration.MemoryItem>();

        lock (gate)
        {
            if (string.IsNullOrWhiteSpace(query))
                return config.Memories.OrderByDescending(m => m.Timestamp).Take(k).ToArray();

            var tokens = Tokenize(query.Trim());
            var hit = config.Memories
                .Select(m => new { Item = m, Score = Score(tokens, m.Text), Time = m.Timestamp })
                .Where(x => x.Score > 0)
                .OrderByDescending(x => x.Score)
                .ThenByDescending(x => x.Time)
                .Take(k)
                .Select(x => x.Item)
                .ToArray();

            if (hit.Length == 0)
                return config.Memories.OrderByDescending(m => m.Timestamp).Take(k).ToArray();

            return hit;
        }
    }

    public IEnumerable<Configuration.MemoryItem> Recent(int k)
    {
        if (k <= 0) return Array.Empty<Configuration.MemoryItem>();
        lock (gate)
            return config.Memories.OrderByDescending(m => m.Timestamp).Take(k).ToArray();
    }

    private static string[] Tokenize(string s) =>
        s.Split(new[] { ' ', '\t', '\r', '\n', '.', ',', '!', '?', ':', ';', '/', '\\', '-', '_', '(', ')', '[', ']', '{', '}', '"' },
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private static int Score(string[] tokens, string text)
    {
        if (tokens.Length == 0 || string.IsNullOrWhiteSpace(text)) return 0;
        var hit = 0;
        foreach (var t in tokens)
            if (text.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0) hit++;
        return hit;
    }
}
