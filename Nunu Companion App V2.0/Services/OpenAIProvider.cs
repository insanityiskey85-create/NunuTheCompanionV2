using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NunuCompanionAppV2.Models;

namespace NunuCompanionAppV2.Services;

public sealed class OpenAIProvider : IChatProvider, IDisposable
{
    private readonly HttpClient http;
    private readonly string baseUrl;
    private readonly string apiKey;

    public OpenAIProvider(string baseUrl, string apiKey, TimeSpan? timeout = null)
    {
        this.baseUrl = baseUrl.TrimEnd('/');
        this.apiKey = apiKey ?? string.Empty;
        http = new HttpClient { Timeout = timeout ?? TimeSpan.FromSeconds(60) };
    }

    public async Task<string> CompleteAsync(IEnumerable<ChatMessage> messages, string model, float temperature, int maxTokens, CancellationToken ct)
    {
        var req = new
        {
            model,
            temperature,
            max_tokens = maxTokens,
            messages = messages.Select(m => new {
                role = m.Role switch
                {
                    ChatRole.System => "system",
                    ChatRole.User => "user",
                    ChatRole.Assistant => "assistant",
                    _ => "user"
                },
                content = m.Content
            })
        };

        using var msg = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/v1/chat/completions");
        msg.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (!string.IsNullOrWhiteSpace(apiKey))
            msg.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        msg.Content = new StringContent(JsonSerializer.Serialize(req), Encoding.UTF8, "application/json");

        using var resp = await http.SendAsync(msg, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
        var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        if (!resp.IsSuccessStatusCode)
            throw new Exception($"LLM error {resp.StatusCode}: {json}");

        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString() ?? string.Empty;
    }

    public void Dispose() => http.Dispose();
}
