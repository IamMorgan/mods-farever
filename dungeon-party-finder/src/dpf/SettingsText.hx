package dpf;

/**
 * The Better Mod Settings page (configFormats.json) in the client's language (Locale.lang). BMS re-reads the file every time
 * its window opens, so the mod writes it once the game's language is known (see DpfMod.localizeSettings). The English page is
 * also the one shipped in the archive; tests/GenSettings.hx regenerates it.
 */
class SettingsText {
    public static function build():Dynamic {
        var configs:Array<Dynamic> = [];
        configs.push({key: "showButton", type: "checkbox", label: Locale.f("showButton")});
        configs.push({key: "unpinned", type: "checkbox", label: Locale.f("unpinned")});
        configs.push({key: "buttonScalePercent", type: "slider", label: Locale.f("buttonScale"), min: 50, max: 200, step: 10});
        return {schemaVersion: 1, displayName: Locale.listTitle(), configs: configs};
    }

    public static function json():String return haxe.Json.stringify(build(), null, "  ");
}
