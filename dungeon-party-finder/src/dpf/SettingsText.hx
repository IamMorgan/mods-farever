package dpf;

/**
 * The Better Mod Settings page (configFormats.json) in the client's language. BMS re-reads the file every time its window
 * opens, so the mod writes it once the game's language is known (see DpfMod.localizeSettings). The English page is also the
 * one shipped in the archive; tests/GenSettings.hx regenerates it.
 */
class SettingsText {
    public static function build(russian:Bool):Dynamic {
        inline function t(en:String, ru:String):String return russian ? ru : en;
        var configs:Array<Dynamic> = [];
        configs.push({key: "showButton", type: "checkbox", label: t("Show the DPF button", "Показывать кнопку DPF")});
        configs.push({key: "unpinned", type: "checkbox",
            label: t("Unpin (drag the DPF button with the left mouse button)", "Открепить (переносить кнопку DPF зажатием левой кнопки мыши)")});
        configs.push({key: "buttonScalePercent", type: "slider", label: t("Button size %", "Размер кнопки, %"), min: 50, max: 200, step: 10});
        configs.push({key: "minPlayers", type: "slider",
            label: t("Players needed to start (4 = a full group; fewer starts after a short wait)", "Игроков для старта (4 — полная группа; меньше — после короткого ожидания)"),
            min: 2, max: 4, step: 1});
        configs.push({key: "debugLog", type: "checkbox",
            label: t("Write a log to hlx/dpf-debug.txt (for bug reports)", "Писать лог в hlx/dpf-debug.txt (для сообщений об ошибках)")});
        return {schemaVersion: 1, displayName: t("Dungeon Party Finder", "Поиск группы в данжи"), configs: configs};
    }

    public static function json(russian:Bool):String return haxe.Json.stringify(build(russian), null, "  ");
}
