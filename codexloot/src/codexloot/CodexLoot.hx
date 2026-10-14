package codexloot;

import hlx.runtime.Bus;
import hlx.runtime.ModConfig;

typedef LootConfig = {
    var enabled:Bool;
    /** Boss / Elite / Spark tags in the monster list. */
    var unitTags:Bool;
    /** Hide loot limited to other monster levels (the game does this when it generates loot). Off: show everything. */
    var levelFilter:Bool;
    /** Upper bound for the number of icons added to the window. */
    var maxItems:Int;
}

/**
 * Codex Loot: shows the full drop list of the selected monster in the Codex window, with the drop chance on every
 * item, a separate block for heroic mode loot, and Boss / Elite / Spark tags in the monster list.
 * Everything is read from the game's own data at run time, so new monsters and items need no update of the mod.
 * The mod writes nothing to disk or to the log (apart from its settings file).
 */
@:build(hlx.runtime.Mod.build())
class CodexLoot {
    @:hlx.config
    static var config:LootConfig = {
        enabled: true,
        unitTags: true,
        levelFilter: false,
        maxItems: 60
    };

    static function main():Void {
        config.save();
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> {
                config = ModConfig.load(HlxRuntime.moduleName(), config);
            }
        );
    }

    /** Runs once, when the player picks a monster in the Codex. */
    @:hlx.postfix(ui.win.codex.CodexUnitSheet.setSelectedUnit)
    static function afterSetSelectedUnit(instance:Dynamic, node:Dynamic, result:Void):Void {
        if (!config.enabled) return;
        try {
            var unit = G.field(instance, "selectedUnit");
            if (unit == null) return;
            var loot = LootCalc.compute(unit, config.levelFilter);
            LootUi.apply(instance, loot.normal, loot.heroic, config.maxItems);
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
