using System;
using System.IO;
using System.Reflection;
using Dalamud.Game.Command;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using NunuCompanionAppV2.Core;
using NunuCompanionAppV2.Core.Persona;
using NunuCompanionAppV2.UI;

namespace NunuCompanionAppV2;

public sealed class Plugin : IDalamudPlugin, IDisposable
{
    public string Name => "Nunu Companion App V2.0";

    // Services
    private readonly IDalamudPluginInterface pi;
    private readonly IChatGui chat;
    private readonly ICommandManager commands;
    private readonly IPluginLog log;

    // Core
    private readonly Configuration config;
    private readonly PersonaProfile persona;
    private readonly Brain brain;
    private readonly ChatRouter router;
    private readonly NunuResponder responder;
    private readonly ChatWindow chatWindow;

    private const string Cmd = "/nunu";

    // Dalamud will resolve these constructor parameters
    public Plugin(
        IDalamudPluginInterface pluginInterface,
        IChatGui chatGui,
        ICommandManager commandManager,
        IPluginLog pluginLog)
    {
        pi = pluginInterface;
        chat = chatGui;
        commands = commandManager;
        log = pluginLog;

        // Config load
        config = pi.GetPluginConfig() as Configuration ?? new Configuration();
        config.BindSaver(c => pi.SavePluginConfig(c));

        // Persona load (keeps your Persona.json structure)
        var baseDir = new FileInfo(Assembly.GetExecutingAssembly().Location).Directory!;
        var personaPath = Path.Combine(baseDir.FullName, "Persona", "Persona.json");
        persona = PersonaStore.LoadFromFile(personaPath, log);

        brain = new Brain(config, log);

        router = new ChatRouter(chat, log);
        responder = new NunuResponder(chat, log, brain, config, persona);
        responder.Hook(router);

        chatWindow = new ChatWindow(responder, brain, config, persona, log);

        // UI
        pi.UiBuilder.Draw += chatWindow.Draw;
        pi.UiBuilder.OpenConfigUi += () => chatWindow.Toggle();

        // Commands
        commands.AddHandler(Cmd, new CommandInfo(OnCommand)
        {
            HelpMessage = "/nunu — toggle window; /nunu auto on|off; /nunu cs <callsign>; /nunu ask <text>"
        });

        log.Info("[Nunu] Plugin initialized.");
    }

    private void OnCommand(string command, string args)
    {
        args = args?.Trim() ?? string.Empty;
        if (string.IsNullOrEmpty(args))
        {
            chatWindow.Toggle();
            return;
        }

        var parts = args.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
        var verb = parts[0].ToLowerInvariant();
        var rest = parts.Length > 1 ? parts[1] : string.Empty;

        switch (verb)
        {
            case "auto":
                if (string.Equals(rest, "on", StringComparison.OrdinalIgnoreCase)) { config.AutoReplyEnabled = true; config.Save(); chat.Print("[Nunu] Auto-reply ON"); }
                else if (string.Equals(rest, "off", StringComparison.OrdinalIgnoreCase)) { config.AutoReplyEnabled = false; config.Save(); chat.Print("[Nunu] Auto-reply OFF"); }
                else chat.Print("[Nunu] Use: /nunu auto on|off");
                break;

            case "cs":
            case "callsign":
                if (!string.IsNullOrWhiteSpace(rest))
                {
                    config.Callsign = rest.Trim();
                    config.Save();
                    chat.Print($"[Nunu] Callsign set to: {config.Callsign}");
                }
                else chat.Print("[Nunu] Use: /nunu cs !nunu");
                break;

            case "ask":
                if (!string.IsNullOrWhiteSpace(rest))
                {
                    var reply = responder.Ask("You", rest.Trim());
                    chat.Print($"[Nunu] {reply}");
                    brain.Remember("You", rest.Trim());
                }
                else chat.Print("[Nunu] Use: /nunu ask <question>");
                break;

            case "reload":
                // Reload persona from file
                var baseDir = new FileInfo(Assembly.GetExecutingAssembly().Location).Directory!;
                var personaPath = Path.Combine(baseDir.FullName, "Persona", "Persona.json");
                var p = PersonaStore.LoadFromFile(personaPath, log);
                responder.UpdatePersona(p);
                chatWindow.UpdatePersona(p);
                chat.Print("[Nunu] Persona reloaded.");
                break;

            default:
                chat.Print("[Nunu] Unknown: auto|cs|ask|reload");
                break;
        }
    }

    public void Dispose()
    {
        try
        {
            responder.Unhook(router);
            router.Dispose();
        }
        catch { /* swallow on unload */ }

        try
        {
            pi.UiBuilder.Draw -= chatWindow.Draw;
            pi.UiBuilder.OpenConfigUi -= () => chatWindow.Toggle();
        }
        catch { }

        try
        {
            commands.RemoveHandler(Cmd);
        }
        catch { }
    }
}
