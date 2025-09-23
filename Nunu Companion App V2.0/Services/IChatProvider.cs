using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NunuCompanionAppV2.Models;

namespace NunuCompanionAppV2.Services;

public interface IChatProvider
{
    Task<string> CompleteAsync(
        IEnumerable<ChatMessage> messages,
        string model,
        float temperature,
        int maxTokens,
        CancellationToken ct);
}
