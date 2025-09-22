using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2.Core;

public sealed class PersonaStore
{
    private readonly string _root;
    private readonly string _relativeJson;
    private readonly IPluginLog _log;
    private PersonaDefinition _persona = new();

    public PersonaStore(string pluginRoot, string relativeJson, IPluginLog log)
    {
        _root = pluginRoot;
        _relativeJson = relativeJson;
        _log = log;
        Reload();
    }

    public PersonaDefinition Current => _persona;

    public void Reload()
    {
        try
        {
            var path = Path.Combine(_root, _relativeJson);
            if (!File.Exists(path))
            {
                _log.Warning($"Persona JSON not found: {path}. Using defaults.");
                _persona = new PersonaDefinition();
                return;
            }

            var json = File.ReadAllText(path);
            using var doc = JsonDocument.Parse(json);
            _persona = MapPersona(doc);
            _log.Info($"Loaded persona: {_persona.Name} (callsigns: {string.Join(", ", _persona.Callsigns)})");
        }
        catch (Exception ex)
        {
            _log.Error(ex, "Failed to load persona; using defaults.");
            _persona = new PersonaDefinition();
        }
    }

    private static PersonaDefinition MapPersona(JsonDocument doc)
    {
        var root = doc.RootElement;
        var p = new PersonaDefinition
        {
            Name = root.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() ?? "Nunu" : "Nunu",
            Description = root.TryGetProperty("description", out var d) && d.ValueKind == JsonValueKind.String ? d.GetString() : null,
            Style = root.TryGetProperty("style", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString() ?? "" : "",
            Traits = root.TryGetProperty("traits", out var t) && t.ValueKind == JsonValueKind.Object ? ToDict(t) : null,
            Callsigns = root.TryGetProperty("callsigns", out var cs) && cs.ValueKind == JsonValueKind.Array ? ToList(cs) : new List<string> { "nunu" },
            Greetings = root.TryGetProperty("greetings", out var g) && g.ValueKind == JsonValueKind.Array ? ToList(g) : new List<string> { "Hello!" },
            Farewells = root.TryGetProperty("farewells", out var f) && f.ValueKind == JsonValueKind.Array ? ToList(f) : new List<string> { "Till sea swallows all." }
        };
        return p;
    }

    private static List<string> ToList(JsonElement arr)
    {
        var list = new List<string>();
        foreach (var e in arr.EnumerateArray())
            if (e.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(e.GetString()))
                list.Add(e.GetString()!.Trim());
        return list;
    }

    private static Dictionary<string, string> ToDict(JsonElement obj)
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var prop in obj.EnumerateObject())
            if (prop.Value.ValueKind == JsonValueKind.String)
                d[prop.Name] = prop.Value.GetString() ?? "";
        return d;
    }
}
