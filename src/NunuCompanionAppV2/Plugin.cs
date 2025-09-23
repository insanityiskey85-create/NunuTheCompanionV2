using Dalamud.Game.Command;
using Dalamud.Interface.Windowing;
using Dalamud.Plugin;
using Dalamud.Plugin.Services;

namespace NunuCompanionAppV2;

public sealed class Plugin : IDalamudPlugin
{
    public string Name => "NunuCompanionAppV2";

    [PluginService] internal static IDalamudPluginInterface PInterface { get; private set; } = null!;
    [PluginService] internal static ICommandManager         Commands   { get; private set; } = null!;

    private readonly WindowSystem windows = new("NunuCompanionAppV2");
    private readonly Windows.MainWindow   mainWindow;
    private readonly Windows.ConfigWindow configWindow;
    private readonly PluginConfig config;

    public Plugin()
    {
        config = PInterface.GetPluginConfig() as PluginConfig ?? new PluginConfig();
        config.Initialize(PInterface);

        mainWindow   = new Windows.MainWindow();
        configWindow = new Windows.ConfigWindow(config);

        windows.AddWindow(mainWindow);
        windows.AddWindow(configWindow);

        var ui = PInterface.UiBuilder;
        ui.Draw         += DrawUI;
        ui.OpenMainUi   += OpenMainUI;
        ui.OpenConfigUi += OpenConfigUI;

        Commands.AddHandler("/nunu", new CommandInfo(OnCommand) { HelpMessage = "Open Nunu Companion App window." });
    }

    private void DrawUI() => windows.Draw();
    private void OpenMainUI()   => mainWindow.IsOpen   = true;
    private void OpenConfigUI() => configWindow.IsOpen = true;
    private void OnCommand(string _, string __) => mainWindow.IsOpen = true;

    public void Dispose()
    {
        var ui = PInterface.UiBuilder;
        ui.Draw         -= DrawUI;
        ui.OpenMainUi   -= OpenMainUI;
        ui.OpenConfigUi -= OpenConfigUI;

        Commands.RemoveHandler("/nunu");
        windows.RemoveAllWindows();
    }
}
