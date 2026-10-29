package comixmod;

import hlx.runtime.HlxPrefixResult;
import comixmod.GameAccess as G;

typedef ComixConfig = {
    var enabled:Bool;
    var bubbleEnabled:Bool;
    var damageEnabled:Bool;
    var sizePercent:Int;
}

/**
 * Comic-style effects for Farever: speech bubbles over characters that wrote in the chat, light-blue
 * magic damage numbers and a comic burst (one at a time) for critical hits. Every game object is reached
 * through HlxRuntime, the effects are drawn on the game's 2D scene and scaled with its resolution.
 */
@:build(hlx.runtime.Mod.build())
class ComixMod {
    @:hlx.config
    static var config:ComixConfig = {enabled: true, bubbleEnabled: true, damageEnabled: true, sizePercent: 100};

    static inline var MAGIC_COLOR = 0x66CCFF;
    static inline var CRIT_COLOR = 0xFF2A1A;
    static var app:Dynamic;
    static var bubbles:Bubbles;
    static var crit:CritBurst;
    static var reported = new Map<String, Bool>();

    static function main():Void {
        config.save();
        bubbles = new Bubbles();
        crit = new CritBurst();
    }

    static var localizedLanguage = "";
    static var nextLanguageCheck = 0.0;

    /** Better Mod Settings re-reads configFormats.json whenever its window opens: write it in the client's language. */
    static function localizeSettings():Void {
        var now = haxe.Timer.stamp();
        if (now < nextLanguageCheck) return;
        nextLanguageCheck = now + 1;
        var language = G.text(G.current("Options", "language"));
        if (language == "") language = G.text(G.staticCall("hxd.System", "get_lang", []));
        if (language == "" || language == localizedLanguage) return;
        localizedLanguage = language;
        var path = "hlx/mods/" + HlxRuntime.moduleName() + "/configFormats.json";
        var text = SettingsText.json(SettingsText.isRussian(language));
        var current = try sys.io.File.getContent(path) catch (_:Dynamic) "";
        if (current != text) {
            // Vortex deploys a link to its own copy: replace the link, never write into that copy.
            try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
            sys.io.File.saveContent(path, text);
        }
    }

    static var nextConfigCheck = 0.0;
    static var lastCritAmount = -1;
    static var lastCritAt = -10.0;

    /** The settings window writes config.json while the game runs: take its values at once. */
    static function reloadConfig():Void {
        var now = haxe.Timer.stamp();
        if (now < nextConfigCheck) return;
        nextConfigCheck = now + 0.5;
        var path = "hlx/config/" + HlxRuntime.moduleName() + "/config.json";
        if (!sys.FileSystem.exists(path)) return;
        var saved:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
        if (saved.enabled != null) config.enabled = saved.enabled;
        if (saved.bubbleEnabled != null) config.bubbleEnabled = saved.bubbleEnabled;
        if (saved.damageEnabled != null) config.damageEnabled = saved.damageEnabled;
        if (saved.sizePercent != null) config.sizePercent = Std.int(saved.sizePercent);
    }

    static function report(where:String, error:Dynamic):Void {
        if (reported.exists(where)) return;
        reported.set(where, true);
        trace("[comix-mod] " + where + ": " + Std.string(error));
    }

    /** Pixel scale of the effects: 1 at a 1080p game and 100% size, proportional to the game's resolution and the size setting. */
    static function scale(s2d:Dynamic):Float {
        var height = G.number(G.field(s2d, "height"), 1080);
        return Math.max(0.5, height / 1080) * Math.max(30, Math.min(200, config.sizePercent)) / 100;
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        app = instance;
        var s2d = G.field(instance, "s2d"), s3d = G.field(instance, "s3d");
        try localizeSettings() catch (error:Dynamic) report("language", error);
        try reloadConfig() catch (error:Dynamic) report("config", error);
        try {
            var bubblesOn = config.enabled && config.bubbleEnabled;
            bubbles.update(s2d, s3d, dt, bubblesOn, scale(s2d));
            crit.update(s2d, s3d, dt, config.enabled && config.damageEnabled);
        } catch (error:Dynamic) report("update", error);
        return Continue;
    }

    @:hlx.postfix(st.player.ChatClient.localReceiveMessage)
    static function onChatMessage(instance:Dynamic, message:Dynamic, result:Void):Void {
        if (!config.enabled || !config.bubbleEnabled || app == null || message == null) return;
        try {
            // System notices have `notify`; everything else was already filtered by the game's chat rules
            // (a private message only reaches its sender and recipient, a group message its members).
            if (G.field(message, "notify") != null) return;
            var text = G.text(G.field(message, "text"));
            var sender = G.field(message, "sender");
            if (text == "") return;
            var hero = sender == null ? null : G.field(sender, "hero");
            var channel = G.field(message, "channel");
            var spot:Dynamic = null;
            // a local message carries the place it was said at
            if (Type.enumConstructor(channel) == "Local") spot = Type.enumParameters(channel)[0];
            if (hero == null && spot == null) return;
            var uid = sender == null ? "" : G.text(G.field(sender, "uid"));
            if (uid == "" && spot != null) uid = Math.round(G.number(G.field(spot, "x")) / 2) + "," + Math.round(G.number(G.field(spot, "y")) / 2);
            bubbles.say(uid, hero, spot, text);
        } catch (error:Dynamic) report("chat", error);
    }

    @:hlx.postfix(ui.comp.DamageDisplay.display)
    static function afterDamageNumber(damage:Dynamic, position:Dynamic, result:Dynamic):Dynamic {
        if (!config.enabled || !config.damageEnabled || app == null || damage == null || result == null) return result;
        try {
            var counter = G.field(result, "counter");
            Fonts.remember(G.field(counter, "font"));
            if (G.call("st.skill.DamageResult", "get_critical", damage) == true) {
                // the number itself stays the game's own, red
                G.call("domkit.Properties", "initStyle", G.field(counter, "dom"), ["color", CRIT_COLOR]);
                G.call("h2d.Text", "set_textColor", counter, [CRIT_COLOR]);
                // the same hit reported again right away is not a new crit; a new crit replaces the burst of the previous one
                var amount = Math.round(G.number(G.field(damage, "_amount")));
                var now = haxe.Timer.stamp();
                var same = amount == lastCritAmount && now - lastCritAt < 1.0;
                lastCritAmount = amount;
                lastCritAt = now;
                if (same) return result;
                var s2d = G.field(app, "s2d");
                crit.show(G.field(result, "parent"), position, scale(s2d));
            } else if (G.call("st.skill.DamageResult", "get_isMagic", damage) == true) {
                // Same way Fancy Damage Numbers does it: the inline style survives the native CSS refresh.
                G.call("domkit.Properties", "initStyle", G.field(counter, "dom"), ["color", MAGIC_COLOR]);
                G.call("h2d.Text", "set_textColor", counter, [MAGIC_COLOR]);
            }
        } catch (error:Dynamic) report("damage", error);
        return result;
    }

    @:hlx.prefix(GameApp.dispose)
    static function beforeGameAppDispose(instance:Dynamic):HlxPrefixResult<Void> {
        bubbles.clear();
        crit.clear();
        app = null;
        return Continue;
    }
}
