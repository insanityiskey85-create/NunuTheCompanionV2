using System.IO;
using System.Text.Json;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2.Core.Persona;

public static class PersonaStore
{
    private static readonly JsonSerializerOptions J =
        new() { PropertyNameCaseInsensitive = true, ReadCommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true };

    public static PersonaProfile LoadFromFile(string path, IPluginLog log)
    {
        try
        {
            if (File.Exists(path))
            {
                var json = File.ReadAllText(path);
                var p = JsonSerializer.Deserialize<PersonaProfile>(json, J);
                if (p != null) return p;
            }
            log.Warning($"[Nunu] Persona not found or invalid at: {path}. Using defaults.");
        }
        catch (System.Exception ex)
        {
            log.Error(ex, "[Nunu] Failed to load Persona.json; using defaults.");
        }
        return new PersonaProfile();
    }
}
