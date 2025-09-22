using System;

namespace NunuCompanionAppV2.Core;

public sealed class ChatMemoryItem
{
    public DateTime When { get; set; } = DateTime.UtcNow;
    public string User { get; set; } = "";
    public string Text { get; set; } = "";

    public ChatMemoryItem() { }
    public ChatMemoryItem(string user, string text)
    {
        User = user;
        Text = text;
        When = DateTime.UtcNow;
    }
}
