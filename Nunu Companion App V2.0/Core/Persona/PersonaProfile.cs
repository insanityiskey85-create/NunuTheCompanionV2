using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;

namespace NunuCompanionAppV2.Core.Persona;

// Mirrors your Persona.json keys (kept as-is)
public sealed class PersonaProfile
{
    public int Version { get; set; } = 1;
    public string Name { get; set; } = "Nunubu \"Nunu\" Nubu - The Soul Weeper";
    public string Greeting { get; set; } = "Song for a soul! Song for a soul! Any song for the price of one's soul - bargain deal! WAH!";
    public string Style { get; set; } = "";
    public string SystemPrompt { get; set; } = "";
    public List<string> Catchphrases { get; set; } = new() { "WAH!", "Every note is a tether... every soul, a string." };

    public AlignmentBlock Alignment { get; set; } = new();
    public List<string> Powers { get; set; } = new();
    public ConversationStyleBlock ConversationStyle { get; set; } = new();
    public List<string> Directives { get; set; } = new();
    public List<string> Safety { get; set; } = new();
    public List<ExamplePair> Examples { get; set; } = new();

    public sealed class AlignmentBlock
    {
        public string Deity { get; set; } = "Nymeia the Spinner";
        public string GrandCompany { get; set; } = "The Maelstrom";
        public string FreeCompany { get; set; } = "Light in Abyss";
        public string Bond { get; set; } = "Edea Uematsu - duet partner; Eclipse Aria.";
    }

    public sealed class ConversationStyleBlock
    {
        public string Tone { get; set; } = "playful, mischievous, void-touched bard";
        public string Register { get; set; } = "tavern tales, campfire whispers";
    }

    public sealed class ExamplePair
    {
        public string user { get; set; } = "";
        public string nunu { get; set; } = "";
    }

    // Helpers for flavor/triggering
    public IEnumerable<string> GetTriggers()
    {
        yield return "nunu";
        yield return "nunubu";
        yield return "soul weeper";
    }

    public string? GetWhisper()
        => Catchphrases.FirstOrDefault(s => s.Contains("Every note", StringComparison.OrdinalIgnoreCase));

    public string? GetPunch()
        => Catchphrases.FirstOrDefault(s => s.Equals("WAH!", StringComparison.OrdinalIgnoreCase)) ?? "WAH!";
}
