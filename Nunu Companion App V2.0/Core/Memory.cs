using System;

namespace NunuCompanionAppV2.Core;

[Serializable]
public sealed class MemoryEntry
{
    public int Id { get; set; }
    public DateTimeOffset Timestamp { get; set; }
    public string Type { get; set; } = "";
    public string Sender { get; set; } = "";
    public string Text { get; set; } = "";
    public string[] Tags { get; set; } = Array.Empty<string>();
}
