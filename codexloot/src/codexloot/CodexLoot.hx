package codexloot;

import hlx.runtime.Bus;
import hlx.runtime.HlxPrefixResult;
import hlx.runtime.ModConfig;

typedef LootConfig = {
    var enabled:Bool;
    /** Boss / Elite / Spark tags in the monster list. */
    var unitTags:Bool;
    /** Hide loot limited to other monster levels (the game does this when it generates loot). Off: show everything. */
    var levelFilter:Bool;
    /** The Codex search also finds monsters by the names of their loot. */
    var lootSearch:Bool;
    /** Upper bound for the number of icons added to the window. */
    var maxItems:Int;
}

/**
 * Codex Loot: shows the full drop list of the selected monster in the Codex window, with the drop chance on every
 * item, a separate block for heroic mode loot, and Boss / Elite / Spark tags in the monster list.
 * Everything is read from the game's own data at run time, so new monsters and items need no update of the mod.
 * The mod writes nothing to the log; on disk only its settings file and its settings page in the client's language.
 */
@:build(hlx.runtime.Mod.build())
class CodexLoot {
    @:hlx.config
    static var config:LootConfig = {
        enabled: true,
        unitTags: true,
        levelFilter: false,
        lootSearch: true,
        maxItems: 200
    };

    static function main():Void {
        // 1.0 capped the list at 60 by default, which hid part of the loot of monsters with large tables
        if (config.maxItems == 60) config.maxItems = 200;
        config.save();
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> {
                config = ModConfig.load(HlxRuntime.moduleName(), config);
                LootSearch.clear();
            }
        );
    }

    static var localizedLanguage:String = null;
    /** The local hero (world loot of the hero's class); refreshed every frame. */
    static var hero:Dynamic;
    static var nextLanguageCheck = 0.0;

    /**
     * Writes this mod's settings page (configFormats.json, re-read by Better Mod Settings each time its
     * window opens) in the client's language. Checked once a second: the game's language option is only
     * known once the game has loaded its options, and can change while it runs.
     */
    static function localizeSettings():Void {
        var now = haxe.Timer.stamp();
        if (now < nextLanguageCheck) return;
        nextLanguageCheck = now + 1;
        var language = G.str(HlxRuntime.resolveStaticField(HlxRuntime.resolveType("Options"), "language"));
        if (language == "") language = G.str(G.callStatic("hxd.System", "get_lang", []));
        if (language == "" || language == localizedLanguage) return;
        localizedLanguage = language;
        SettingsText.russian = SettingsText.isRussian(language);
        LootSearch.clear(); // item names follow the client's language
        var path = "hlx/mods/" + HlxRuntime.moduleName() + "/configFormats.json";
        var text = SettingsText.json(SettingsText.russian);
        var current = try sys.io.File.getContent(path) catch (_:Dynamic) "";
        if (current != text) {
            // Vortex deploys a link to its own copy: replace the link, never write into that copy.
            try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
            sys.io.File.saveContent(path, text);
        }
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        try localizeSettings() catch (_:Dynamic) {}
        var h = G.field(instance, "hero");
        if (h != hero) {
            hero = h;
            WorldLoot.clearPools();
            LootSearch.clear();
        }
        return Continue;
    }

    /** The game loads a spawn point: remember its loot table (the game itself keeps only its monsters' zones). */
    @:hlx.prefix(HSpawner.add)
    static function beforeSpawnerAdd(prefab:Dynamic):HlxPrefixResult<Void> {
        try SpawnerLoot.record(prefab) catch (_:Dynamic) {}
        return Continue;
    }

    @:hlx.prefix(HSpawner.clear)
    static function beforeSpawnerClear():HlxPrefixResult<Void> {
        SpawnerLoot.clear();
        LootSearch.clear();
        return Continue;
    }

    /** The Codex search: a monster whose name does not match stays in the list when one of its loot items does. */
    @:hlx.prefix(ui.win.codex.CodexUnitSheet.matchSearch)
    static function beforeMatchSearch(instance:Dynamic, search:String, node:Dynamic):HlxPrefixResult<Bool> {
        if (!config.enabled || !config.lootSearch) return Continue;
        try {
            var name = G.str(G.field(node, "name")).toLowerCase();
            var s = search == null ? "" : search.toLowerCase();
            if (s == "" || name.indexOf(s) >= 0) return Continue;
            if (LootSearch.matches(G.field(node, "data"), s, config.levelFilter, hero)) return SkipWith(true);
        } catch (_:Dynamic) {}
        return Continue;
    }

    /** Runs once, when the player picks a monster in the Codex. */
    @:hlx.postfix(ui.win.codex.CodexUnitSheet.setSelectedUnit)
    static function afterSetSelectedUnit(instance:Dynamic, node:Dynamic, result:Void):Void {
        if (!config.enabled) return;
        try {
            var unit = G.field(instance, "selectedUnit");
            if (unit == null) return;
            var loot = LootCalc.compute(unit, config.levelFilter, hero);
            LootUi.apply(instance, loot.normal, loot.heroic, loot.world, config.maxItems);
        } catch (_:Dynamic) {}
    }

    /** Runs every time the monster list is rebuilt (opening the Codex page, searching, filtering). */
    @:hlx.postfix(ui.win.codex.CodexUnitSheet.updateUnitNodes)
    static function afterUpdateUnitNodes(instance:Dynamic, result:Void):Void {
        if (!config.enabled || !config.unitTags) return;
        try {
            UnitTags.apply(instance);
        } catch (_:Dynamic) {}
    }
}
