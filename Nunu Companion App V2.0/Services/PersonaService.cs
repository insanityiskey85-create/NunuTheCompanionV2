using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace NunuCompanionAppV2.Services;

public sealed class PersonaService : IDisposable
{
    private readonly Action<string> onLog;
    private FileSystemWatcher? watcher;
    private string personaPath = string.Empty;
    private string cachedPersona = string.Empty;
    private bool watch;
    private DateTime lastReload = DateTime.MinValue;

    public PersonaService(Action<string> onLog)
    {
        this.onLog = onLog;
    }

    public void SetPath(string path, bool watchChanges)
    {
        personaPath = path?.Trim() ?? string.Empty;
        watch = watchChanges;
        LoadOnce();

        DisposeWatcher();
        if (watch && File.Exists(personaPath))
        {
            try
            {
                watcher = new FileSystemWatcher(Path.GetDirectoryName(personaPath)!)
                {
                    Filter = Path.GetFileName(personaPath),
                    NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime,
                    EnableRaisingEvents = true
                };
                watcher.Changed += (_, __) => DebouncedReload();
                watcher.Created += (_, __) => DebouncedReload();
                watcher.Renamed += (_, __) => DebouncedReload();
            }
            catch (Exception ex)
            {
                onLog?.Invoke($"[Nunu] Persona watch failed: {ex.Message}");
            }
        }
    }

    public string GetPersonaRaw() => cachedPersona;

    public string GetEffectivePrompt(string basePrompt, bool usePersona, bool personaOnTop)
    {
        if (!usePersona || string.IsNullOrWhiteSpace(cachedPersona))
            return basePrompt ?? string.Empty;

        if (string.IsNullOrWhiteSpace(basePrompt))
            return cachedPersona;

        return personaOnTop
            ? $"{cachedPersona}\n\n{basePrompt}"
            : $"{basePrompt}\n\n{cachedPersona}";
    }

    public void LoadOnce()
    {
        try
        {
            if (string.IsNullOrWhiteSpace(personaPath))
            {
                cachedPersona = string.Empty;
                return;
            }
            if (!File.Exists(personaPath))
            {
                cachedPersona = string.Empty;
                onLog?.Invoke($"[Nunu] Persona file not found: {personaPath}");
                return;
            }

            cachedPersona = File.ReadAllText(personaPath, new UTF8Encoding(false)).Trim();
            onLog?.Invoke("[Nunu] Persona loaded.");
        }
        catch (Exception ex)
        {
            cachedPersona = string.Empty;
            onLog?.Invoke($"[Nunu] Persona load failed: {ex.Message}");
        }
    }

    private void DebouncedReload()
    {
        var now = DateTime.UtcNow;
        if ((now - lastReload).TotalMilliseconds < 400) return;
        lastReload = now;

        _ = Task.Run(async () =>
        {
            await Task.Delay(250);
            LoadOnce();
        });
    }

    private void DisposeWatcher()
    {
        try
        {
            if (watcher != null)
            {
                watcher.EnableRaisingEvents = false;
                watcher.Dispose();
                watcher = null;
            }
        }
        catch { }
    }

    public void Dispose() => DisposeWatcher();
}
