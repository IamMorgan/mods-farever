package macromod;

import hlx.runtime.Bus;
import hlx.runtime.ModConfig;
import hlx.runtime.HlxPrefixResult;
import macromod.GameAccess as G;
import macromod.KeyRowScanner.RowDecorator;
import macromod.SkillMatch.SkillRef;

typedef MacroConfig = {
    var notWhileRunning:Bool;
    var aoeNearestTarget:Bool;
    var combatOnly:Bool;
    var m1_name:String; var m1_hotkey:Dynamic; var m1_mode:String; var m1_repeat:Bool;
    var m1_s1_skill:String; var m1_s1_delay:Int; var m1_s2_skill:String; var m1_s2_delay:Int;
    var m1_s3_skill:String; var m1_s3_delay:Int; var m1_s4_skill:String; var m1_s4_delay:Int;
    var m1_s5_skill:String; var m1_s5_delay:Int; var m1_s6_skill:String; var m1_s6_delay:Int;
    var m1_s7_skill:String; var m1_s7_delay:Int; var m1_s8_skill:String; var m1_s8_delay:Int;
    var m1_s9_skill:String; var m1_s9_delay:Int; var m1_s10_skill:String; var m1_s10_delay:Int;

    var m2_name:String; var m2_hotkey:Dynamic; var m2_mode:String; var m2_repeat:Bool;
    var m2_s1_skill:String; var m2_s1_delay:Int; var m2_s2_skill:String; var m2_s2_delay:Int;
    var m2_s3_skill:String; var m2_s3_delay:Int; var m2_s4_skill:String; var m2_s4_delay:Int;
    var m2_s5_skill:String; var m2_s5_delay:Int; var m2_s6_skill:String; var m2_s6_delay:Int;
    var m2_s7_skill:String; var m2_s7_delay:Int; var m2_s8_skill:String; var m2_s8_delay:Int;
    var m2_s9_skill:String; var m2_s9_delay:Int; var m2_s10_skill:String; var m2_s10_delay:Int;

    var m3_name:String; var m3_hotkey:Dynamic; var m3_mode:String; var m3_repeat:Bool;
    var m3_s1_skill:String; var m3_s1_delay:Int; var m3_s2_skill:String; var m3_s2_delay:Int;
    var m3_s3_skill:String; var m3_s3_delay:Int; var m3_s4_skill:String; var m3_s4_delay:Int;
    var m3_s5_skill:String; var m3_s5_delay:Int; var m3_s6_skill:String; var m3_s6_delay:Int;
    var m3_s7_skill:String; var m3_s7_delay:Int; var m3_s8_skill:String; var m3_s8_delay:Int;
    var m3_s9_skill:String; var m3_s9_delay:Int; var m3_s10_skill:String; var m3_s10_delay:Int;
}

/**
 * Macros for Farever: each macro uses up to ten action-bar skills in a row, picked from a panel
 * of skill icons. Every game object is reached through HlxRuntime: importing game classes here
 * would compile private copies of them into this mod, and the game would never see anything the
 * mod does with those copies.
 */
@:build(hlx.runtime.Mod.build())
class MacroMod {
    @:hlx.config
    static var config:MacroConfig = {
        notWhileRunning: false,
        aoeNearestTarget: false,
        combatOnly: false,
        m1_name: "Macro 1", m1_hotkey: 0, m1_mode: "Press (Toggle)", m1_repeat: false,
        m1_s1_skill: "", m1_s1_delay: 100, m1_s2_skill: "", m1_s2_delay: 100,
        m1_s3_skill: "", m1_s3_delay: 100, m1_s4_skill: "", m1_s4_delay: 100,
        m1_s5_skill: "", m1_s5_delay: 100, m1_s6_skill: "", m1_s6_delay: 100,
        m1_s7_skill: "", m1_s7_delay: 100, m1_s8_skill: "", m1_s8_delay: 100,
        m1_s9_skill: "", m1_s9_delay: 100, m1_s10_skill: "", m1_s10_delay: 100,

        m2_name: "Macro 2", m2_hotkey: 0, m2_mode: "Press (Toggle)", m2_repeat: false,
        m2_s1_skill: "", m2_s1_delay: 100, m2_s2_skill: "", m2_s2_delay: 100,
        m2_s3_skill: "", m2_s3_delay: 100, m2_s4_skill: "", m2_s4_delay: 100,
        m2_s5_skill: "", m2_s5_delay: 100, m2_s6_skill: "", m2_s6_delay: 100,
        m2_s7_skill: "", m2_s7_delay: 100, m2_s8_skill: "", m2_s8_delay: 100,
        m2_s9_skill: "", m2_s9_delay: 100, m2_s10_skill: "", m2_s10_delay: 100,

        m3_name: "Macro 3", m3_hotkey: 0, m3_mode: "Press (Toggle)", m3_repeat: false,
        m3_s1_skill: "", m3_s1_delay: 100, m3_s2_skill: "", m3_s2_delay: 100,
        m3_s3_skill: "", m3_s3_delay: 100, m3_s4_skill: "", m3_s4_delay: 100,
        m3_s5_skill: "", m3_s5_delay: 100, m3_s6_skill: "", m3_s6_delay: 100,
        m3_s7_skill: "", m3_s7_delay: 100, m3_s8_skill: "", m3_s8_delay: 100,
        m3_s9_skill: "", m3_s9_delay: 100, m3_s10_skill: "", m3_s10_delay: 100
    };

    static var sequencer:Sequencer;
    static var keys:GameKeys;
    static var skills:GameSkills;
    static var hotbar = new HotbarSkills();
    static var sceneRoot:Dynamic;
    static var clearButtons:KeyRowScanner;
    static var stepRows:KeyRowScanner;
    static var stepBoxes = new Map<String, Dynamic>(); // step field -> its text field on screen
    static var settingsOpen = false;
    static var known:Array<SkillRef> = null;
    static var picker = new SkillPickerPanel();
    static var pickRequest:{macroNumber:Int, step:Int} = null; // which step's "Choose" was clicked

    static function main():Void {
        config.save();
        keys = new GameKeys();
        skills = new GameSkills(keys);
        skills.picks = PickStore.load();
        sequencer = new Sequencer(keys, skills);
        applyConfig();

        // The red X next to each activation key button ... (rows are found by their label, in
        // either language: the page may still be in the other one until it is rewritten)
        var keyLabels = new Map<String, String>();
        for (russian in [false, true])
            for (m in 1...MacroDefs.MACROS + 1) keyLabels.set(SettingsText.keyLabel(m, russian), "m" + m + "_hotkey");
        clearButtons = new KeyRowScanner(new GameScene("ui.comp.Button"), new KeyClearButtons(clearKey), keyLabels);
        // ... and next to each step's skill name.
        var stepLabels = new Map<String, String>();
        for (russian in [false, true])
            for (m in 1...MacroDefs.MACROS + 1) for (s in 1...MacroDefs.STEPS + 1) stepLabels.set(SettingsText.stepLabel(m, s, russian), stepField(m, s));
        stepRows = new KeyRowScanner(new GameScene("ui.comp.InputBox"), new StepRowDecorator(new KeyClearButtons(clearStep), onStepRow), stepLabels);

        for (m in 1...MacroDefs.MACROS + 1) {
            for (s in 1...MacroDefs.STEPS + 1) {
                var macroNumber = m, step = s;
                Bus.subscribe("better-mod-settings/action/" + HlxRuntime.moduleName() + "/m" + m + "_s" + s + "_pick",
                    (_:Dynamic) -> pickRequest = {macroNumber: macroNumber, step: step});
            }
        }
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> {
                config = ModConfig.load(HlxRuntime.moduleName(), config);
                applyConfig();
            }
        );
    }

    static function stepField(m:Int, s:Int):String return "m" + m + "_s" + s + "_skill";

    /** The "X" of an activation key: back to Not set (0), and the key button shows it at once. */
    static function clearKey(key:String, button:Dynamic):Void {
        Reflect.setField(config, key, 0);
        config.save();
        applyConfig();
        try new GameScene().setButtonText(button, "Not set") catch (_:Dynamic) {}
    }

    /** The "X" of a step: the step becomes empty and is skipped. */
    static function clearStep(key:String, box:Dynamic):Void setStep(key, "");

    /** Writes a step's skill name, saves, and shows it in the open settings window at once. */
    static function setStep(field:String, name:String):Void {
        Reflect.setField(config, field, name);
        config.save();
        applyConfig();
        var box = stepBoxes.get(field);
        if (box != null)
            try GameScene.setInputText(box, name) catch (_:Dynamic) {}
    }

    /** A step row appeared in the settings window. A step that holds a skill id (older configs)
        is switched to the skill's name. */
    static function onStepRow(field:String, box:Dynamic):Void {
        stepBoxes.set(field, box);
        var value:Dynamic = Reflect.field(config, field);
        var text:Null<String> = Std.isOfType(value, String) ? value : null;
        var name = SkillMatch.nameForId(text, knownSkills());
        if (name == null) return;
        skills.picks.set(name, SkillMatch.kindFor(text, skills.picks, knownSkills()));
        PickStore.save(skills.picks);
        setStep(field, name);
    }

    /** Action-bar and hero skills, read once per opening of the settings page. */
    static function knownSkills():Array<SkillRef> {
        if (known == null) {
            skills.hotbar = hotbar.read(sceneRoot);
            var list:Array<SkillRef> = [for (h in skills.hotbar) h];
            known = list.concat(HotbarSkills.heroSkills(GameSkills.localHero()));
        }
        return known;
    }

    static function openPicker(macroNumber:Int, step:Int):Void {
        var field = stepField(macroNumber, step);
        var entries = hotbar.read(sceneRoot);
        skills.hotbar = entries;
        var x = 100.0, y = 100.0;
        try {
            x = G.number(G.call("h2d.Scene", "get_mouseX", sceneRoot), x);
            y = G.number(G.call("h2d.Scene", "get_mouseY", sceneRoot), y);
        } catch (_:Dynamic) {}
        picker.show(sceneRoot, SettingsText.pickerTitle(macroNumber, step, russian), entries, x, y, entry -> {
            skills.picks.set(entry.name, entry.kind);
            PickStore.save(skills.picks);
            setStep(field, entry.name);
        });
    }

    static function applyConfig():Void {
        sequencer.stopAll(); // a running macro restarts with the new settings
        sequencer.macros = MacroDefs.fromConfig(config);
        sequencer.pauseWhileMoving = config.notWhileRunning;
        sequencer.combatOnly = config.combatOnly;
        skills.aoeAutoAim = config.aoeNearestTarget;
        skills.invalidate();
    }

    /** Runs every frame inside the game's own update loop (no haxe.Timer: its loop is never pumped here). */
    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        sceneRoot = HlxRuntime.resolveField(instance, "s2d");
        var hero = GameSkills.localHero();
        if (hero == null) hero = try HlxRuntime.resolveField(instance, "hero") catch (_:Dynamic) null;
        sequencer.hero = hero;
        sequencer.inCombat = hero != null && G.field(hero, "isInCombat") == true;
        try localizeSettings() catch (_:Dynamic) {}
        var now = haxe.Timer.stamp();
        try skills.update(now) catch (_:Dynamic) {}
        try sequencer.update(now) catch (_:Dynamic) {}

        // Both scanners are cheap (a few hundred UI nodes per frame, with a pause between passes)
        // and only find rows while the Farever Macros settings page is on screen.
        try {
            clearButtons.tick(sceneRoot, now);
            stepRows.tick(sceneRoot, now);
            var open = stepRows.hasLive();
            if (open != settingsOpen) {
                settingsOpen = open;
                known = null; // skills may have changed since the page was last open
                if (!open) { stepBoxes.clear(); picker.hide(); }
            }
        } catch (_:Dynamic) {}

        if (pickRequest != null) {
            var request = pickRequest;
            pickRequest = null;
            try openPicker(request.macroNumber, request.step) catch (_:Dynamic) {}
        }
        picker.update();
        return Continue;
    }

    static var russian = false;
    static var localizedLanguage:String = null;
    static var nextLanguageCheck = 0.0;

    /**
     * Writes this mod's settings page (configFormats.json, re-read by Better Mod Settings each
     * time its window opens) in the client's language, and keeps the stored macro modes in the
     * same language as the dropdown shows. Checked once a second: the game's language option is
     * only known once the game has loaded its options, and can change while it runs.
     */
    static function localizeSettings():Void {
        var now = haxe.Timer.stamp();
        if (now < nextLanguageCheck) return;
        nextLanguageCheck = now + 1;
        var language = G.text(G.current("Options", "language"));
        if (language == "") language = G.text(G.staticCall("hxd.System", "get_lang", []));
        if (language == "" || language == localizedLanguage) return;
        localizedLanguage = language;
        russian = SettingsText.isRussian(language);
        picker.russian = russian;
        var path = "hlx/mods/" + HlxRuntime.moduleName() + "/configFormats.json";
        var text = SettingsText.json(russian, MacroDefs.MACROS, MacroDefs.STEPS);
        var current = try sys.io.File.getContent(path) catch (_:Dynamic) "";
        if (current != text) {
            // Vortex deploys a link to its own copy: replace the link, never write into that copy.
            try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
            sys.io.File.saveContent(path, text);
        }
        var changed = false;
        for (m in 1...MacroDefs.MACROS + 1) {
            var field = "m" + m + "_mode";
            var value:Dynamic = Reflect.field(config, field);
            var mode = SettingsText.modes(russian)[SettingsText.modeIndex(value)];
            if (value != mode) { Reflect.setField(config, field, mode); changed = true; }
        }
        if (changed) config.save(); // the mode itself is unchanged: no need to restart macros
    }

    @:hlx.prefix(GameApp.dispose)
    static function beforeGameAppDispose(instance:Dynamic):HlxPrefixResult<Void> {
        sequencer.stopAll();
        picker.hide();
        return Continue;
    }
}

/** Adds the X to a step's text field and reports the field, so the mod can update its text. */
private class StepRowDecorator implements RowDecorator {
    var inner:KeyClearButtons;
    var onRow:(field:String, box:Dynamic) -> Void;

    public function new(inner:KeyClearButtons, onRow:(field:String, box:Dynamic) -> Void) {
        this.inner = inner;
        this.onRow = onRow;
    }

    public function isAlive(added:Dynamic):Bool return inner.isAlive(added);

    public function decorate(key:String, box:Dynamic):Dynamic {
        var added = inner.decorate(key, box);
        try onRow(key, box) catch (_:Dynamic) {}
        return added;
    }
}
