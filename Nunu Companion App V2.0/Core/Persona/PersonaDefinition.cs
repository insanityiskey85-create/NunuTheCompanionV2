using System.Collections.Generic;

namespace NunuCompanionAppV2.Core;

public sealed class PersonaDefinition
{
    public string Name { get; set; } = "Nunu";
    public string? Description { get; set; }
    public List<string> Callsigns { get; set; } = new() { "nunu", "nunuchan" };
    public List<string> Greetings { get; set; } = new() { "Hello!", "Well met." };
    public List<string> Farewells { get; set; } = new() { "Till sea swallows all.", "Walk in the light." };
    public string Style { get; set; } = "cheerful, lore-friendly, elegant";
    public Dictionary<string, string>? Traits { get; set; }
}
