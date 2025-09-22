namespace NunuCompanionAppV2.Models;

public enum ChatRole { System, User, Assistant }

public sealed class ChatMessage
{
    public ChatRole Role { get; set; }
    public string Content { get; set; } = string.Empty;

    public ChatMessage() { }
    public ChatMessage(ChatRole role, string content) { Role = role; Content = content; }
}
