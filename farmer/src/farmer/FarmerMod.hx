package farmer;

import farmer.GameAccess as G;
import hlx.runtime.Bus;
import hlx.runtime.HlxPrefixResult;
import hlx.runtime.ModConfig;

typedef FarmerConfig = {
    var showButton:Bool;
    var unpinned:Bool;
    var buttonScalePercent:Int;
    var panelX:Float;
    var panelY:Float;
    var pickupLoot:Bool;
    var replaceGear:Bool;
}

/**
 * Farmer: a "Farm" button on the screen opens the window of the farm settings (resources to gather and hunt, gear to recycle,
 * emptying the bag into the bank, the level to reach); "Farm" starts the bot, which walks, fights and gathers by itself (see Bot).
 * Two settings work without the bot: "pick up loot" (Loot) and "replace gear" with a better one from the bag (Equip).
 *
 * Every game object is reached through HlxRuntime (see GameAccess): importing game classes here would compile private copies
 * of them into this mod, and the game would never see anything the mod does with those copies.
 */
@:build(hlx.runtime.Mod.build())
class FarmerMod {
    @:hlx.config
    static var config:FarmerConfig = {
        showButton: true, unpinned: false, buttonScalePercent: 100, panelX: 12, panelY: 364, pickupLoot: false, replaceGear: false
    };

    static inline var PLAN_FILE = "hlx/config/farmer/farm.json";
    static inline var ACTIVATE_DELAY = 3.0;

    static var button = new FarmButton();
    static var window = new FarmWindow();
    static var plan = new FarmPlan();
    static var bot = new Bot();
    static var active = false;
    static var heroSeenAt = -1.0;
    static var planSaved = "";

    static function main():Void {
        Log.t("mod", "Farmer loaded (log: hlx/config/farmer/farmer.log)");
        config.save();
        button.x = config.panelX;
        button.y = config.panelY;
        loadPlan();
        button.onClick = toggleWindow;
        window.onStart = start;
        window.onStop = stop;
        window.onChanged = savePlan;
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> config = ModConfig.load(HlxRuntime.moduleName(), config)
        );
        Probe.extra.set("open", (_:Dynamic) -> { toggleWindow(); return "toggled"; });
        Probe.extra.set("bot", (cmd:Dynamic) -> bot.debug(Std.string(Reflect.field(cmd, "what")), cmd));
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        try Probe.tick(instance) catch (error:Dynamic) Log.t("err", "probe failed: " + Std.string(error));
        try tick(instance, dt) catch (error:Dynamic) Log.err("tick", error);
        Log.flush();
        return Continue;
    }

    static function tick(app:Dynamic, dt:Float):Void {
        var now = haxe.Timer.stamp();
        try localizeSettings(now) catch (_:Dynamic) {}
        var hero = G.field(app, "hero");
        if (hero == null || G.field(app, "me") == null) {
            if (active) { active = false; button.hide(); window.hide(); bot.reset(); Log.t("mod", "hero left the world: Farmer paused"); }
            heroSeenAt = -1;
            return;
        }
        if (!active) {
            if (heroSeenAt < 0) heroSeenAt = now;
            if (now - heroSeenAt < ACTIVATE_DELAY) return;
            active = true;
            Log.t("mod", "hero in the world: Farmer active");
        }
        bot.update(app, hero, plan, now, dt);
        if (config.pickupLoot || bot.running) Loot.update(hero, now);
        if (config.replaceGear || (bot.running && plan.replaceGear && bot.calm(now))) Equip.update(hero, now);
        var scale = Math.max(0.5, Math.min(2.0, config.buttonScalePercent / 100));
        button.update(config.showButton, scale, Locale.f("button"), bot.running ? 1 : (bot.finished ? 2 : 0), config.unpinned, now);
        if (button.dragEnded) {
            button.dragEnded = false;
            config.panelX = button.x;
            config.panelY = button.y;
            config.save();
        }
        window.update(bot.running, bot.statusText());
        if (bot.consumeChanged()) savePlan();
    }

    static function toggleWindow():Void {
        if (window.isOpen()) { window.hide(); return; }
        window.show(plan, bot.running);
    }

    static function start():Void {
        if (!plan.hasWork()) { bot.say(Locale.f("nothing")); return; }
        bot.start();
        savePlan();
    }

    static function stop():Void bot.stop();

    // ---- the plan file ----

    static function loadPlan():Void {
        try {
            if (sys.FileSystem.exists(PLAN_FILE)) plan = FarmPlan.fromJson(sys.io.File.getContent(PLAN_FILE));
        } catch (_:Dynamic) {}
        planSaved = plan.toJson();
    }

    static function savePlan():Void {
        var text = plan.toJson();
        if (text == planSaved) return;
        planSaved = text;
        try {
            if (!sys.FileSystem.exists("hlx/config/farmer")) sys.FileSystem.createDirectory("hlx/config/farmer");
            sys.io.File.saveContent(PLAN_FILE, text);
        } catch (_:Dynamic) {}
    }

    // ---- hooks of the bot ----

    @:hlx.prefix(client.PlayerController.getMoveDirection)
    static function beforeGetMoveDirection(instance:Dynamic, input:Dynamic):HlxPrefixResult<Dynamic> {
        if (!active) return Continue;
        var direction = try bot.steer(instance, input) catch (_:Dynamic) null;
        return direction == null ? Continue : SkipWith(direction);
    }

    @:hlx.prefix(lib.Input.getMove)
    static function beforeGetMove(point:Dynamic, includePad:hl.Ref<Bool>):HlxPrefixResult<Dynamic> {
        if (!active || point == null || !bot.moving()) return Continue;
        try {
            G.set(point, "x", 0.0);
            G.set(point, "y", -1.0);
            return SkipWith(point);
        } catch (_:Dynamic) return Continue;
    }

    /**
     * The game blocks every input while its window is not the focused one (App.allowInputs); the bot works anyway: with the window
     * in the background the game still answers "inputs allowed" while the bot runs. (The cursor and the sound keep following the
     * real focus: the user's mouse is never taken.)
     */
    @:hlx.prefix(GameApp.allowInputs)
    static function beforeAllowInputs(instance:Dynamic, flag:hl.Ref<Bool>):HlxPrefixResult<Bool> {
        if (!active || !bot.running) return Continue;
        var focused = true;
        try focused = G.call("hxd.Window", "get_isFocused", G.staticCall("hxd.Window", "getInstance", [])) == true catch (_:Dynamic) {}
        return focused ? Continue : SkipWith(true);
    }

    /**
     * The game cancels a cast when the hero moves: BaseSkill.shouldCancel (run every update of a running skill) answers true when
     * Skill.hasMoveCancel holds, the unit has a move request and 0.1 s of the skill have passed (stop reason Cancel). The bot's hero
     * casts on the run: no skill asks for that cancel, and no skill holds the legs (Skill.canMove, read by Unit.canMove).
     */
    @:hlx.prefix(st.skill.Skill.hasMoveCancel)
    static function beforeSkillHasMoveCancel(instance:Dynamic):HlxPrefixResult<Bool>
        return active && bot.running && AutoDodge.castOnTheRun ? SkipWith(false) : Continue;

    @:hlx.prefix(st.skill.Skill.canMove)
    static function beforeSkillCanMove(instance:Dynamic):HlxPrefixResult<Bool>
        return active && bot.running && AutoDodge.castOnTheRun ? SkipWith(true) : Continue;

    @:hlx.prefix(client.PlayerController.updateSkillInputs)
    static function beforeSkillInputs(instance:Dynamic):HlxPrefixResult<Void>
        return active && bot.holdingSkills() ? Skip : Continue;

    @:hlx.prefix(client.UnitController.tryUseSkill)
    static function beforeTryUseSkill(instance:Dynamic, skill:Dynamic, target:Dynamic):HlxPrefixResult<Void> {
        if (!active || !bot.holdingSkills()) return Continue;
        var kind = try G.text(G.field(skill, "kind")) catch (_:Dynamic) "";
        return kind == "Dash_Base" || bot.ownCast ? Continue : Skip;
    }

    @:hlx.prefix(client.PlayerController.tryResolveSkillRequests)
    static function beforeResolveSkills(instance:Dynamic):HlxPrefixResult<Bool> {
        if (!active || !bot.holdingSkills()) return Continue;
        var kind = try G.text(G.field(instance, "requestedSkillKind")) catch (_:Dynamic) "";
        return kind == "Dash_Base" || bot.ownCast ? Continue : SkipWith(false);
    }

    // ---- language ----

    static var localizedLanguage:String = null;
    static var nextLanguageCheck = 0.0;

    /** Writes this mod's settings page (configFormats.json) in the client's language, and tells the windows which language to use. */
    static function localizeSettings(now:Float):Void {
        if (now < nextLanguageCheck) return;
        nextLanguageCheck = now + 1;
        var language = G.str(G.current("Options", "language"));
        if (language == null || language == "") language = G.str(G.staticCall("hxd.System", "get_lang", []));
        if (language == null || language == "" || language == localizedLanguage) return;
        localizedLanguage = language;
        Locale.setLanguage(language);
        var path = "hlx/mods/" + HlxRuntime.moduleName() + "/configFormats.json";
        var text = SettingsText.json();
        var current = try sys.io.File.getContent(path) catch (_:Dynamic) "";
        if (current != text) {
            // Vortex deploys a link to its own copy: replace the link, never write into that copy.
            try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
            sys.io.File.saveContent(path, text);
        }
    }

    @:hlx.prefix(GameApp.dispose)
    static function beforeGameAppDispose(instance:Dynamic):HlxPrefixResult<Void> {
        try {
            bot.reset();
            button.hide();
            window.hide();
            Log.t("mod", "game closing");
        } catch (_:Dynamic) {}
        Log.flush(true);
        return Continue;
    }
}
