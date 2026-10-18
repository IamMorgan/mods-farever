package buildcalc;

import hlx.runtime.HlxPrefixResult;

/**
 * Build Calculator: picks the best equipment, weapon, talents, infusions, slot augments and upgrades
 * for the player's priorities (damage, defense, health, healing; melee or ranged) — from all items of
 * the game and from the player's own bag and stash — and keeps up to three templates. It lives in its
 * own tab of the hero profile window. See DESIGN.md.
 */
@:build(hlx.runtime.Mod.build())
class BuildCalc {
    static function main():Void {
        DebugLog.line("mod loaded");
    }

    static var nextLanguageCheck = 0.0;
    static var lastLanguage = "";

    static function followLanguage():Void {
        var now = haxe.Timer.stamp();
        if (now < nextLanguageCheck) return;
        nextLanguageCheck = now + 1;
        var language = G.str(HlxRuntime.resolveStaticField(G.type("Options"), "language"));
        if (language == "" || language == lastLanguage) return;
        lastLanguage = language;
        var used = Texts.setLanguage(language);
        Ui.resetFonts(); // the fonts are picked again for the characters of the new language
        DebugLog.line("language: " + language + " -> texts " + used);
    }

    /** The hero profile window builds its tab list: add the calculator tab. */
    @:hlx.postfix(ui.win.CharacterUI.initTabs)
    static function afterInitTabs(instance:Dynamic, result:Void):Void {
        DebugLog.guard("CharacterUI.initTabs", () -> BuildTab.addTab(instance));
    }

    /** The hero profile window (re)builds its content: draw the calculator on its tab. */
    @:hlx.postfix(ui.win.CharacterUI.init)
    static function afterCharacterInit(instance:Dynamic, result:Void):Void {
        DebugLog.guard("CharacterUI.init", () -> BuildTab.build(instance));
    }

    /** The arsenal weapon shown by the calculator (Views.asArsenal): worn, for the game's item tooltip. */
    @:hlx.prefix(st.Equipment.isEquipped)
    static function beforeIsEquipped(instance:Dynamic, item:Dynamic):HlxPrefixResult<Bool> {
        return Views.shownInArsenal(item) ? SkipWith(true) : Continue;
    }

    /** ... and worn in the arsenal slot (Slot_Weapon2), so the tooltip takes that slot's share (affixFactor 0.4). */
    @:hlx.prefix(st.Equipment.getEquipSlot)
    static function beforeGetEquipSlot(instance:Dynamic, item:Dynamic):HlxPrefixResult<String> {
        if (!Views.shownInArsenal(item)) return Continue;
        var name:Dynamic = null;
        try name = G.at(HlxRuntime.resolveStaticField(G.type("DataCache"), "EQUIPMENT_SLOTS"), 1) catch (_:Dynamic) {}
        return name == null ? Continue : SkipWith(name);
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        DebugLog.guard("language", followLanguage);
        DebugLog.guard("layout report", BuildTab.report);
        DebugLog.guard("calculation", BuildTab.tick);
        DebugLog.guard("test mode", () -> TestMode.tick(instance));

        DebugLog.flush();
        return Continue;
    }
}
