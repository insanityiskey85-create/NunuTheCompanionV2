using System;
using System.Reflection;
using Dalamud.Game.Command;
using Dalamud.Game.Text;
using Dalamud.Game.Text.SeStringHandling;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using NunuCompanionAppV2.Core;
using NunuCompanionAppV2.UI;

// alias to be explicit
using SeString = Dalamud.Game.Text.SeStringHandling.SeString;

namespace NunuCompanionAppV2;

public sealed class Plugin : IDalamudPlugin
{
    public string Name => "Nunu Companion App V2";

    private readonly IDalamudPluginInterface _pi;
    private readonly IChatGui _chat;
    private readonly ICommandManager _cmd;
    private readonly IPluginLog _log;
    private readonly IFramework _framework;

    private const string Command = "/nunu";

    private readonly Configuration _config;
    private readonly PersonaStore _persona;
    private readonly Brain _brain;
    private readonly NunuResponder _responder;
    private readonly ChatWindow _window;

    private Action? _detachChatHandler;
    private readonly Action _openConfigHandler;

    // Constructor injection: Dalamud will supply these.
    public Plugin(
        IDalamudPluginInterface pluginInterface,
        IChatGui chatGui,
        ICommandManager commandManager,
        IPluginLog log,
        IFramework framework)
    {
        _pi = pluginInterface;
        _chat = chatGui;
        _cmd = commandManager;
        _log = log;
        _framework = framework;

        // Config & core
        _config = _pi.GetPluginConfig() as Configuration ?? new Configuration();
        _config.Initialize(_pi);
        _config.Save();

        var pluginDir = _pi.AssemblyLocation.Directory?.FullName ?? AppContext.BaseDirectory;
        _persona = new PersonaStore(pluginDir, _config.PersonaPath, _log);
        _brain = new Brain(_config, _persona, _log);
        _responder = new NunuResponder(_chat, _brain, _persona, _config, _log);

        // UI
        _window = new ChatWindow(_brain, _persona, _config, _log);
        _pi.UiBuilder.Draw += _window.Draw;
        _openConfigHandler = () => _window.IsOpen = true;
        _pi.UiBuilder.OpenConfigUi += _openConfigHandler;

        // Command
        _cmd.AddHandler(Command, new CommandInfo(OnCommand)
        {
            HelpMessage = "Toggle window; /nunu reply on|off; /nunu callsign <word>"
        });

        // Chat event: bind with reflection to whatever signature Dalamud exposes
        AttachChatHandler();

        _log.Info("NunuCompanionAppV2 initialized (constructor injection; no PluginService attribute).");
    }

    private void OnCommand(string command, string args)
    {
        var trimmed = (args ?? string.Empty).Trim();

        if (trimmed.StartsWith("reply ", StringComparison.OrdinalIgnoreCase))
        {
            var on = trimmed.EndsWith("on", StringComparison.OrdinalIgnoreCase);
            _config.AutoReply = on;
            _config.Save();
            _chat.Print($"Nunu auto-reply: {(on ? "ON" : "OFF")}");
            return;
        }

        if (trimmed.StartsWith("callsign ", StringComparison.OrdinalIgnoreCase))
        {
            var cs = trimmed["callsign ".Length..].Trim();
            if (!string.IsNullOrWhiteSpace(cs))
            {
                _config.UserCallsign = cs;
                _config.Save();
                _chat.Print($"Nunu callsign set to: {cs}");
            }
            return;
        }

        _window.IsOpen = !_window.IsOpen;
    }

    // ========= Chat binding via reflection (handles multiple signatures) =========

    private void AttachChatHandler()
    {
        try
        {
            var chatType = _chat.GetType();
            var evt = chatType.GetEvent("ChatMessage") ?? chatType.GetEvent("OnMessage");
            if (evt == null)
            {
                _log.Warning("No chat event found on IChatGui (ChatMessage/OnMessage). Chat auto-reply disabled.");
                return;
            }

            var candidates = new[]
            {
                GetType().GetMethod(nameof(ChatHandler_New),     BindingFlags.NonPublic | BindingFlags.Instance),
                GetType().GetMethod(nameof(ChatHandler_NewPtr),  BindingFlags.NonPublic | BindingFlags.Instance),
                GetType().GetMethod(nameof(ChatHandler_OldRef),  BindingFlags.NonPublic | BindingFlags.Instance),
                GetType().GetMethod(nameof(ChatHandler_OldNoRef),BindingFlags.NonPublic | BindingFlags.Instance),
            };

            foreach (var m in candidates)
            {
                if (m == null) continue;
                try
                {
                    var del = Delegate.CreateDelegate(evt.EventHandlerType!, this, m, throwOnBindFailure: false);
                    if (del != null)
                    {
                        evt.AddEventHandler(_chat, del);
                        _detachChatHandler = () =>
                        {
                            try { evt.RemoveEventHandler(_chat, del); } catch { }
                        };
                        _log.Info($"Chat bound to handler: {m.Name} (delegate: {evt.EventHandlerType!.Name}).");
                        return;
                    }
                }
                catch
                {
                    // try next
                }
            }

            _log.Warning("Failed to attach chat handler: no compatible signature matched.");
        }
        catch (Exception ex)
        {
            _log.Error(ex, "Error attaching chat handler.");
        }
    }

    // Newer Dalamud (common)
    private void ChatHandler_New(XivChatType type, uint senderId, ref SeString sender, ref SeString message, ref bool isHandled)
        => HandleChatCore(type, sender.TextValue, message.TextValue);

    // Some builds use nint senderId
    private void ChatHandler_NewPtr(XivChatType type, nint senderId, ref SeString sender, ref SeString message, ref bool isHandled)
        => HandleChatCore(type, sender.TextValue, message.TextValue);

    // Older: ref SeString parameters
    private void ChatHandler_OldRef(XivChatType type, ref SeString sender, ref SeString message, ref bool isHandled)
        => HandleChatCore(type, sender.TextValue, message.TextValue);

    // Older: non-ref SeString parameters
    private void ChatHandler_OldNoRef(XivChatType type, SeString sender, SeString message, ref bool isHandled)
        => HandleChatCore(type, sender.TextValue, message.TextValue);

    private void HandleChatCore(XivChatType type, string sender, string text)
    {
        _responder.HandleIncoming(type, sender, text);
    }

    // ============================================================================

    public void Dispose()
    {
        try { _detachChatHandler?.Invoke(); } catch { /* ignore */ }
        _cmd.RemoveHandler(Command);

        _pi.UiBuilder.Draw -= _window.Draw;
        _pi.UiBuilder.OpenConfigUi -= _openConfigHandler;

        _log.Info("NunuCompanionAppV2 disposed.");
    }
}
