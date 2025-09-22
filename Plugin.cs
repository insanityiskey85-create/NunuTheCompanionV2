using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Dalamud.Game.Command;
using Dalamud.Interface.Windowing;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;
using Dalamud.Game.Text;
using Dalamud.Game.Text.SeStringHandling;
using NunuCompanionAppV2.Services;

namespace NunuCompanionAppV2;

public sealed class Plugin : IDalamudPlugin
{
    public string Name => "NunuCompanionAppV2";

    private readonly IDalamudPluginInterface pi;
    private readonly ICommandManager commands;
    private readonly IChatGui chatGui;
    private readonly IClientState client;

    private readonly WindowSystem windows = new("NunuCompanionAppV2");
    private readonly Windows.MainWindow mainWindow;
    private readonly Windows.ConfigWindow configWindow;

    private PluginConfig config = null!;
    private OpenAIProvider provider = null!;
    private ChatService chat = null!;
    private PersonaService persona = null!;

    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly Dictionary<string, DateTime> lastReplyBySender = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> recentOwnChunks = new();

    private void OnDraw() => windows.Draw();
    private void OnOpenMainUi() => mainWindow.IsOpen = true;
    private void OnOpenConfigUi() => configWindow.IsOpen = true;

    public Plugin(IDalamudPluginInterface pi, ICommandManager commands, IChatGui chatGui, IClientState client)
    {
        this.pi = pi;
        this.commands = commands;
        this.chatGui = chatGui;
        this.client = client;

        // Load config
        config = pi.GetPluginConfig() as PluginConfig ?? new PluginConfig();
        config.Initialize(pi);

        // Persona
        persona = new PersonaService(msg => chatGui.Print(msg));
        persona.SetPath(config.PersonaFilePath, config.AutoReloadPersona);

        // Provider + chat service with persona-aware settings getter
        provider = new OpenAIProvider(config.BaseUrl, config.ApiKey);
        chat = new ChatService(provider, () =>
        {
            var baseSystem = config.SystemPrompt ?? string.Empty;
            var effSystem = persona.GetEffectivePrompt(baseSystem, config.UsePersonaFile, config.PersonaOnTop);
            return (config.Model, config.Temperature, config.MaxTokens, config.MaxHistory, effSystem);
        });

        // Windows
        mainWindow = new Windows.MainWindow(chat, config);
        configWindow = new Windows.ConfigWindow(cfg: config,
            onSaveAndApply: () => { config.Save(); ApplySettings(); },
            onResetDefaults: () => { ResetToDefaults(); });

        windows.AddWindow(mainWindow);
        windows.AddWindow(configWindow);

        // UI hooks
        var ui = pi.UiBuilder;
        ui.Draw += OnDraw;
        ui.OpenMainUi += OnOpenMainUi;
        ui.OpenConfigUi += OnOpenConfigUi;

        // Slash command
        commands.AddHandler("/nunu", new CommandInfo(OnCommand)
        { HelpMessage = "Ask Nunu: /nunu <message> (persona, reply channel, triggers in Settings)." });

        // Chat listener (API 13)
        chatGui.ChatMessage += OnChatMessage;
    }

    // ===== Commands =====
    private void OnCommand(string _cmd, string args)
    {
        if (string.IsNullOrWhiteSpace(args))
        {
            chatGui.PrintError("[Nunu] Usage: /nunu <message>");
            return;
        }
        _ = AskAndReplyAsync(args.Trim());
    }

    // ===== Chat listener (API 13 signature) =====
    private void OnChatMessage(
        XivChatType type,
        int timestamp,
        ref SeString sender,
        ref SeString message,
        ref bool isHandled)
    {
        try
        {
            if (!config.EnableAutoListen) return;
            if (!IsAllowedChannel(type)) return;

            var myName = client.LocalPlayer?.Name.TextValue ?? string.Empty;
            var from = sender.TextValue?.Trim() ?? string.Empty;
            if (string.Equals(from, myName, StringComparison.OrdinalIgnoreCase))
                return;

            var text = message.TextValue ?? string.Empty;
            if (string.IsNullOrWhiteSpace(text)) return;

            lock (recentOwnChunks)
                if (recentOwnChunks.Contains(text)) return;

            if (config.MentionOnly && !text.Contains(config.MentionToken, StringComparison.OrdinalIgnoreCase))
                return;

            bool whitelisted = config.Whitelist.Any(n => n.Equals(from, StringComparison.OrdinalIgnoreCase));
            bool mentioned = text.Contains(config.MentionToken, StringComparison.OrdinalIgnoreCase);

            if (!whitelisted && !config.MentionOnly && config.Whitelist.Count > 0) return;
            if (config.MentionOnly && !whitelisted && !mentioned) return;

            if (config.Triggers.Count > 0)
            {
                var lower = text.ToLowerInvariant();
                if (!config.Triggers.Any(t => lower.Contains(t.ToLowerInvariant())))
                    return;
            }

            if (config.PerSenderCooldownSec > 0 &&
                lastReplyBySender.TryGetValue(from, out var last) &&
                (DateTime.UtcNow - last).TotalSeconds < config.PerSenderCooldownSec)
                return;

            lastReplyBySender[from] = DateTime.UtcNow;

            var prompt = text.Length > config.MaxReplyChars ? text[..config.MaxReplyChars] : text;
            _ = AskAndReplyAsync(prompt);
        }
        catch { }
    }

    private bool IsAllowedChannel(XivChatType t) =>
        (t == XivChatType.Say && config.ListenSay) ||
        (t == XivChatType.Party && config.ListenParty) ||
        (t == XivChatType.Alliance && config.ListenAlliance) ||
        (t == XivChatType.FreeCompany && config.ListenFC) ||
        (t == XivChatType.TellIncoming && config.ListenTell) ||
        (t == XivChatType.TellOutgoing && config.ListenTell);

    // ===== Core ask/reply =====
    private async Task AskAndReplyAsync(string prompt)
    {
        if (!await gate.WaitAsync(0))
        {
            chatGui.Print("[Nunu] Still singing—one moment.");
            return;
        }

        try
        {
            var reply = await chat.SendAsync(prompt, CancellationToken.None).ConfigureAwait(false);
            if (config.ReplyToChat) await SendToChatAsync(reply);
            else mainWindow.IsOpen = true;
        }
        catch (Exception ex)
        {
            chat.AppendAssistant("[error] " + ex.Message);
            chatGui.PrintError("[Nunu] " + ex.Message);
        }
        finally
        {
            gate.Release();
        }
    }

    private (XivChatType type, string prefix) ResolveReplyChannel()
    {
        switch (config.ReplyChannel)
        {
            case ReplyChannel.Echo: return (XivChatType.Echo, "/echo");
            case ReplyChannel.Say: return (XivChatType.Say, "/s");
            case ReplyChannel.Party: return (XivChatType.Party, "/p");
            case ReplyChannel.Alliance: return (XivChatType.Alliance, "/a");
            case ReplyChannel.FreeCompany: return (XivChatType.FreeCompany, "/fc");
            case ReplyChannel.Shout: return (XivChatType.Shout, "/sh");
            case ReplyChannel.Yell: return (XivChatType.Yell, "/y");
            case ReplyChannel.Tell:
                var target = string.IsNullOrWhiteSpace(config.TellTarget) ? "" : $" \"{config.TellTarget}\"";
                return (XivChatType.TellOutgoing, "/tell" + target);
            default: return (XivChatType.Echo, "/echo");
        }
    }

    private async Task SendToChatAsync(string text)
    {
        var (entryType, prefix) = ResolveReplyChannel();

        foreach (var chunk in Chunk(text, config.BroadcastChunkLen))
        {
            lock (recentOwnChunks) recentOwnChunks.Add(chunk);

            // local print styled as chosen channel
            chatGui.Print(new XivChatEntry
            {
                Type = entryType,
                Name = "Nunu",
                Message = new SeStringBuilder().AddText(chunk).Build()
            });

            // broadcast via chat command
            if (config.Broadcast && !string.IsNullOrWhiteSpace(prefix))
            {
                commands.ProcessCommand($"{prefix} {chunk}");
                await Task.Delay(350);
            }

            _ = Task.Run(async () =>
            {
                await Task.Delay(3000);
                lock (recentOwnChunks) recentOwnChunks.Remove(chunk);
            });
        }
    }

    private static IEnumerable<string> Chunk(string s, int max)
    {
        if (string.IsNullOrEmpty(s)) yield break;
        for (int i = 0; i < s.Length; i += max)
            yield return s.Substring(i, Math.Min(max, s.Length - i));
    }

    // ===== Apply & Defaults =====
    private void ApplySettings()
    {
        try
        {
            // Persona first (system prompt comes via settings getter every call)
            persona.SetPath(config.PersonaFilePath, config.AutoReloadPersona);

            var newProvider = new OpenAIProvider(config.BaseUrl, config.ApiKey);
            var old = provider;
            provider = newProvider;
            chat.UpdateProvider(newProvider);
            old?.Dispose();

            chatGui.Print("[Nunu] Settings saved & applied.");
        }
        catch (Exception ex)
        {
            chatGui.PrintError("[Nunu] Failed to apply settings: " + ex.Message);
        }
    }

    private void ResetToDefaults()
    {
        // LLM
        config.BaseUrl = "http://localhost:1234";
        config.ApiKey = "";
        config.Model = "gpt-4o-mini";
        config.Temperature = 0.7f;
        config.MaxTokens = 512;
        config.MaxHistory = 8;
        config.SystemPrompt = "You are Nunu Companion, a helpful, concise assistant for FFXIV players.";

        // Persona
        config.UsePersonaFile = false;
        config.PersonaFilePath = "";
        config.PersonaOnTop = true;
        config.AutoReloadPersona = true;

        // Chat
        config.ReplyToChat = true;
        config.Broadcast = true;
        config.BroadcastChunkLen = 440;
        config.ReplyChannel = ReplyChannel.Party;
        config.TellTarget = "";

        // Listen
        config.EnableAutoListen = true;
        config.MentionOnly = false;
        config.MentionToken = "@nunu";
        config.ListenSay = true;
        config.ListenParty = true;
        config.ListenAlliance = false;
        config.ListenFC = false;
        config.ListenTell = false;
        config.PerSenderCooldownSec = 8;
        config.MaxReplyChars = 1200;

        config.Save();
        ApplySettings();
        chatGui.Print("[Nunu] Settings reset to defaults.");
    }

    public void Dispose()
    {
        var ui = pi.UiBuilder;
        ui.Draw -= OnDraw;
        ui.OpenMainUi -= OnOpenMainUi;
        ui.OpenConfigUi -= OnOpenConfigUi;

        chatGui.ChatMessage -= OnChatMessage;

        commands.RemoveHandler("/nunu");
        windows.RemoveAllWindows();
        provider?.Dispose();
        persona?.Dispose();
        gate.Dispose();
    }
}
