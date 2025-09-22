using System.Text;
using NunuCompanionAppV2.Core.Persona;

namespace NunuCompanionAppV2.Core;

public static class LoreWeaver
{
    private static readonly (string find, string replace)[] Subs = new (string, string)[]
    {
        (" ai ", " arcane mindstone "),
        ("internet", "aethernet"),
        ("wifi", "linkpearl"),
        ("computer", "magitek console"),
        ("server", "aetheric relay"),
        ("upload", "attune"),
        ("download", "draw down"),
        ("debug", "unravel"),
        ("bug", "gremlin"),
        ("nymeia", "Nymeia"),
        ("oschon", "Oschon"),
    };

    public static string Shape(PersonaProfile p, string speaker, string query, string core, string? whisper, string? punch)
    {
        var sb = new StringBuilder();

        if (!string.IsNullOrWhiteSpace(p.Greeting) &&
            (string.IsNullOrWhiteSpace(query) ||
             query.StartsWith("hi", System.StringComparison.OrdinalIgnoreCase) ||
             query.StartsWith("hello", System.StringComparison.OrdinalIgnoreCase)))
            sb.Append(p.Greeting).Append(' ');
        else
            sb.Append($"WAH! {speaker}, the voidbound strings pluck at fate. ");

        sb.Append(core);

        var w = whisper ?? "Every note is a tether... every soul, a string.";
        var b = punch ?? "WAH!";
        sb.Append(' ').Append(w).Append(' ').Append(b);

        var text = ' ' + sb.ToString() + ' ';
        foreach (var (f, r) in Subs)
            text = text.Replace(f, r, System.StringComparison.OrdinalIgnoreCase);

        return text.Trim();
    }
}
