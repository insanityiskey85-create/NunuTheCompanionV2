using Dalamud.Game.Text;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2.Core;

public sealed class NunuResponder
{
    private readonly IChatGui _chat;
    private readonly Brain _brain;
    private readonly PersonaStore _persona;
    private readonly Configuration _config;
    private readonly IPluginLog _log;

    public NunuResponder(IChatGui chat, Brain brain, PersonaStore persona, Configuration config, IPluginLog log)
    {
        _chat = chat;
        _brain = brain;
        _persona = persona;
        _config = config;
        _log = log;
    }

    public void HandleIncoming(XivChatType type, string sender, string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return;

        _brain.Remember(sender, text);

        if (!_config.AutoReply) return;
        if (!_brain.ShouldAnswer(text, out var call)) return;

        var reply = _brain.ComposeReply(sender, text, call);
        _chat.Print($"[{_persona.Current.Name}] {reply}");
        _log.Information("Replied: {Reply}", reply);
    }
}
