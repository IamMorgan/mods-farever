package comixmod;

import hlx.runtime.HlxPrefixResult;
import comixmod.GameAccess as G;

typedef ComixConfig = {
    var enabled:Bool;
    var bubbleEnabled:Bool;
    var damageEnabled:Bool;
}

/**
 * Comic-style effects for Farever: speech bubbles over characters that wrote in the chat, light-blue
 * magic damage numbers and a comic burst (one at a time) for critical hits. Every game object is reached
 * through HlxRuntime, the effects are drawn on the game's 2D scene and scaled with its resolution.
 */
@:build(hlx.runtime.Mod.build())
class ComixMod {
    @:hlx.config
    static var config:ComixConfig = {enabled: true, bubbleEnabled: true, damageEnabled: true};

    static inline var MAGIC_COLOR = 0x66CCFF;
    static var app:Dynamic;
    static var bubbles:Bubbles;
    static var crit:CritBurst;
    static var reported = new Map<String, Bool>();

    static function main():Void {
        config.save();
        bubbles = new Bubbles();
        crit = new CritBurst();
    }

    static function report(where:String, error:Dynamic):Void {
        if (reported.exists(where)) return;
        reported.set(where, true);
        trace("[comix-mod] " + where + ": " + Std.string(error));
    }

    /** Pixel scale of the effects: 1 at a 1080p game, proportional to the game's resolution. */
    static function scale(s2d:Dynamic):Float {
        var height = G.number(G.field(s2d, "height"), 1080);
        return Math.max(0.5, height / 1080);
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        app = instance;
        var s2d = G.field(instance, "s2d"), s3d = G.field(instance, "s3d");
        try {
            var bubblesOn = config.enabled && config.bubbleEnabled;
            bubbles.update(s2d, s3d, dt, bubblesOn, scale(s2d));
            crit.update(dt, config.enabled && config.damageEnabled);
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
            if (text == "" || sender == null) return;
            bubbles.say(G.text(G.field(sender, "uid")), G.field(sender, "hero"), text);
        } catch (error:Dynamic) report("chat", error);
    }

    @:hlx.postfix(ui.comp.DamageDisplay.display)
    static function afterDamageNumber(damage:Dynamic, position:Dynamic, result:Dynamic):Dynamic {
        if (!config.enabled || !config.damageEnabled || app == null || damage == null || result == null) return result;
        try {
            var counter = G.field(result, "counter");
            Fonts.remember(G.field(counter, "font"));
            if (G.call("st.skill.DamageResult", "get_critical", damage) == true) {
                // The critical hit is drawn by the comic burst instead of the native number.
                var origin = G.call("h2d.Object", "localToGlobal", result, [null]);
                var s2d = G.field(app, "s2d");
                crit.show(s2d, G.number(G.field(origin, "x")), G.number(G.field(origin, "y")),
                    Math.round(G.number(G.field(damage, "_amount"))), scale(s2d));
                G.set(result, "visible", false);
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
