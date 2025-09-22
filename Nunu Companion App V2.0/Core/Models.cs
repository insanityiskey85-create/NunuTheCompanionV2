namespace NunuCompanionAppV2.Core;

// Deliberately left simple to avoid duplicate types.
// NOTE: ChatRecord now lives in ChatRouter.cs. Remove any other ChatRecord declarations.
public sealed class UiNote
{
    public string Text { get; set; } = string.Empty;
}
