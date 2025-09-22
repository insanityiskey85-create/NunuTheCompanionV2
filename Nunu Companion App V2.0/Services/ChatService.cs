using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NunuCompanionAppV2.Models;

namespace NunuCompanionAppV2.Services;

public sealed class ChatService
{
    private IChatProvider provider;
    private readonly List<ChatMessage> history = new();
    private readonly System.Func<(string model, float temp, int maxTokens, int maxHistory, string system)> getSettings;

    public IReadOnlyList<ChatMessage> History => history;

    public ChatService(IChatProvider provider, System.Func<(string model, float temp, int maxTokens, int maxHistory, string system)> settingsGetter)
    {
        this.provider = provider;
        this.getSettings = settingsGetter;
    }

    public void UpdateProvider(IChatProvider newProvider) => provider = newProvider;

    public void Reset(string? systemPrompt = null)
    {
        history.Clear();
        if (!string.IsNullOrWhiteSpace(systemPrompt))
            history.Add(new ChatMessage(ChatRole.System, systemPrompt));
    }

    public void EnsureSystem(string systemPrompt)
    {
        if (!history.Any(h => h.Role == ChatRole.System))
            history.Insert(0, new ChatMessage(ChatRole.System, systemPrompt));
    }

    public void AppendAssistant(string text) => history.Add(new ChatMessage(ChatRole.Assistant, text));

    public async Task<string> SendAsync(string user, CancellationToken ct)
    {
        var (model, temp, maxTokens, maxHistory, system) = getSettings();

        EnsureSystem(system);
        history.Add(new ChatMessage(ChatRole.User, user));

        var trimmed = new List<ChatMessage>();
        var sys = history.FirstOrDefault(h => h.Role == ChatRole.System);
        if (sys != null) trimmed.Add(sys);

        var tail = history.Where(h => h.Role != ChatRole.System).TakeLast(maxHistory * 2).ToList();
        trimmed.AddRange(tail);

        var reply = await provider.CompleteAsync(trimmed, model, temp, maxTokens, ct).ConfigureAwait(false);
        history.Add(new ChatMessage(ChatRole.Assistant, reply));
        return reply;
    }
}
