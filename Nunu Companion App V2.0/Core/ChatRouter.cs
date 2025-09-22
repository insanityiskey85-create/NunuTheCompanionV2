using System;
using Dalamud.Game.Text;
using Dalamud.Game.Text.SeStringHandling;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2.Core;

public sealed class ChatRecord
{
    public string Type { get; init; } = "";
    public string Sender { get; init; } = "";
    public string Message { get; init; } = "";
}

public sealed class ChatRouter : IDisposable
{
    private readonly IChatGui chat;
    private readonly IPluginLog log;

    public event Action<ChatRecord>? OnMessage;

    public ChatRouter(IChatGui chat, IPluginLog log)
    {
        this.chat = chat;
        this.log = log;
        this.chat.ChatMessage += HandleChat;
    }

    // Match Dalamud v13 signature
    private void HandleChat(XivChatType type, uint senderId, ref SeString sender, ref SeString message, ref bool isHandled)
    {
        var rec = new ChatRecord
        {
            Type = type.ToString(),
            Sender = sender.TextValue,
            Message = message.TextValue
        };
        OnMessage?.Invoke(rec);
    }

    public void Dispose()
    {
        try { chat.ChatMessage -= HandleChat; } catch { }
    }

    private void HandleChat(XivChatType type, int timestamp, ref SeString sender, ref SeString message, ref bool isHandled)
    {
        throw new NotImplementedException();
    }
}
