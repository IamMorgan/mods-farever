package macromod;

import hlx.runtime.Bus;
import hlx.runtime.ModConfig;
import hlx.runtime.HlxPrefixResult;

typedef MacroConfig = {
    var m1_name:String; var m1_hotkey:Dynamic; var m1_mode:String; var m1_repeat:Bool;
    var m1_s1_key:Dynamic; var m1_s1_delay:Int; var m1_s2_key:Dynamic; var m1_s2_delay:Int;
    var m1_s3_key:Dynamic; var m1_s3_delay:Int; var m1_s4_key:Dynamic; var m1_s4_delay:Int;
    var m1_s5_key:Dynamic; var m1_s5_delay:Int; var m1_s6_key:Dynamic; var m1_s6_delay:Int;
    var m1_s7_key:Dynamic; var m1_s7_delay:Int; var m1_s8_key:Dynamic; var m1_s8_delay:Int;
    var m1_s9_key:Dynamic; var m1_s9_delay:Int; var m1_s10_key:Dynamic; var m1_s10_delay:Int;

    var m2_name:String; var m2_hotkey:Dynamic; var m2_mode:String; var m2_repeat:Bool;
    var m2_s1_key:Dynamic; var m2_s1_delay:Int; var m2_s2_key:Dynamic; var m2_s2_delay:Int;
    var m2_s3_key:Dynamic; var m2_s3_delay:Int; var m2_s4_key:Dynamic; var m2_s4_delay:Int;
    var m2_s5_key:Dynamic; var m2_s5_delay:Int; var m2_s6_key:Dynamic; var m2_s6_delay:Int;
    var m2_s7_key:Dynamic; var m2_s7_delay:Int; var m2_s8_key:Dynamic; var m2_s8_delay:Int;
    var m2_s9_key:Dynamic; var m2_s9_delay:Int; var m2_s10_key:Dynamic; var m2_s10_delay:Int;

    var m3_name:String; var m3_hotkey:Dynamic; var m3_mode:String; var m3_repeat:Bool;
    var m3_s1_key:Dynamic; var m3_s1_delay:Int; var m3_s2_key:Dynamic; var m3_s2_delay:Int;
    var m3_s3_key:Dynamic; var m3_s3_delay:Int; var m3_s4_key:Dynamic; var m3_s4_delay:Int;
    var m3_s5_key:Dynamic; var m3_s5_delay:Int; var m3_s6_key:Dynamic; var m3_s6_delay:Int;
    var m3_s7_key:Dynamic; var m3_s7_delay:Int; var m3_s8_key:Dynamic; var m3_s8_delay:Int;
    var m3_s9_key:Dynamic; var m3_s9_delay:Int; var m3_s10_key:Dynamic; var m3_s10_delay:Int;
}

/**
 * Macros for Farever. Every game object (hxd.Key, hxd.Event) is reached through HlxRuntime.
 * Importing game classes here would compile private copies of them into this mod, and the
 * game would never see anything the mod does with those copies.
 */
@:build(hlx.runtime.Mod.build())
class MacroMod {
    @:hlx.config
    static var config:MacroConfig = {
        m1_name: "Macro 1", m1_hotkey: 0, m1_mode: "Press (Toggle)", m1_repeat: false,
        m1_s1_key: 0, m1_s1_delay: 100, m1_s2_key: 0, m1_s2_delay: 100,
        m1_s3_key: 0, m1_s3_delay: 100, m1_s4_key: 0, m1_s4_delay: 100,
        m1_s5_key: 0, m1_s5_delay: 100, m1_s6_key: 0, m1_s6_delay: 100,
        m1_s7_key: 0, m1_s7_delay: 100, m1_s8_key: 0, m1_s8_delay: 100,
        m1_s9_key: 0, m1_s9_delay: 100, m1_s10_key: 0, m1_s10_delay: 100,

        m2_name: "Macro 2", m2_hotkey: 0, m2_mode: "Press (Toggle)", m2_repeat: false,
        m2_s1_key: 0, m2_s1_delay: 100, m2_s2_key: 0, m2_s2_delay: 100,
        m2_s3_key: 0, m2_s3_delay: 100, m2_s4_key: 0, m2_s4_delay: 100,
        m2_s5_key: 0, m2_s5_delay: 100, m2_s6_key: 0, m2_s6_delay: 100,
        m2_s7_key: 0, m2_s7_delay: 100, m2_s8_key: 0, m2_s8_delay: 100,
        m2_s9_key: 0, m2_s9_delay: 100, m2_s10_key: 0, m2_s10_delay: 100,

        m3_name: "Macro 3", m3_hotkey: 0, m3_mode: "Press (Toggle)", m3_repeat: false,
        m3_s1_key: 0, m3_s1_delay: 100, m3_s2_key: 0, m3_s2_delay: 100,
        m3_s3_key: 0, m3_s3_delay: 100, m3_s4_key: 0, m3_s4_delay: 100,
        m3_s5_key: 0, m3_s5_delay: 100, m3_s6_key: 0, m3_s6_delay: 100,
        m3_s7_key: 0, m3_s7_delay: 100, m3_s8_key: 0, m3_s8_delay: 100,
        m3_s9_key: 0, m3_s9_delay: 100, m3_s10_key: 0, m3_s10_delay: 100
    };

    static var sequencer:Sequencer;
    static var keys:GameKeys;
    static var scene:GameScene;
    static var sceneRoot:Dynamic;
    static var escapeMenu:Dynamic;
    static var clearButtons:KeyRowScanner;

    static function main():Void {
        config.save();
        keys = new GameKeys();
        scene = new GameScene();
        var labels = new Map<String, String>();
        for (key in keyBindingKeys()) labels.set(keyLabel(key), key);
        clearButtons = new KeyRowScanner(scene, new KeyClearButtons(clearKey), labels);
        sequencer = new Sequencer(keys);
        applyConfig();
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> {
                config = ModConfig.load(HlxRuntime.moduleName(), config);
                applyConfig();
            }
        );
    }

    /** Every key setting: the three activation keys and the ten step keys of each macro. */
    static function keyBindingKeys():Array<String> {
        var keys = [];
        for (m in 1...MacroDefs.MACROS + 1) {
            keys.push("m" + m + "_hotkey");
            for (s in 1...MacroDefs.STEPS + 1) keys.push("m" + m + "_s" + s + "_key");
        }
        return keys;
    }

    /** The "X" button: sets the key back to Not set (0) and updates the visible key button at once. */
    static function clearKey(key:String, button:Dynamic):Void {
        Reflect.setField(config, key, 0);
        config.save();
        applyConfig();
        try scene.setButtonText(button, "Not set") catch (_:Dynamic) {}
    }

    /** The row label of a key setting; must match configFormats.json. */
    static function keyLabel(key:String):String {
        var parts = key.split("_"); // m2_hotkey / m2_s3_key
        var number = parts[0].substr(1);
        return parts[1] == "hotkey" ? "M" + number + " Activation Key" : "M" + number + " Step " + parts[1].substr(1) + " Key";
    }

    static function applyConfig():Void {
        sequencer.stopAll(); // release any held key before the settings change
        sequencer.macros = MacroDefs.fromConfig(config);
    }

    /** Runs every frame inside the game's own update loop (no haxe.Timer: its loop is never pumped here). */
    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        sceneRoot = HlxRuntime.resolveField(instance, "s2d");
        var now = haxe.Timer.stamp();
        try sequencer.update(now) catch (_:Dynamic) {}
        // The X buttons are only looked for while the Esc menu (and so the settings window) can be open.
        try {
            var menuOpen = escapeMenu != null && HlxRuntime.resolveField(escapeMenu, "allocated") == true;
            if (menuOpen || clearButtons.hasLive()) clearButtons.tick(sceneRoot, now);
        } catch (_:Dynamic) {}
        return Continue;
    }

    @:hlx.postfix(ui.win.EscapeMenu.init)
    static function afterEscapeMenuInit(instance:Dynamic, result:Void):Void {
        escapeMenu = instance;
    }

    @:hlx.prefix(GameApp.dispose)
    static function beforeGameAppDispose(instance:Dynamic):HlxPrefixResult<Void> {
        sequencer.stopAll();
        return Continue;
    }
}
