package dpf;

import dpf.DungeonList.DungeonInfo;
import dpf.GameAccess as G;
import hlx.runtime.Bus;
import hlx.runtime.HlxPrefixResult;
import hlx.runtime.ModConfig;

typedef DpfConfig = {
    var showButton:Bool;
    var unpinned:Bool;
    var buttonScalePercent:Int;
    var panelX:Float;
    var panelY:Float;
}

/**
 * Dungeon Party Finder: a "DPF" button on the screen opens the list of dungeons; a dungeon opens the game's own dungeon window
 * (the one the portal opens), with a "Search" button added under "Start". The search puts the player together with others who
 * picked the same dungeon and difficulty and have a level of the same bracket (see Search): the earliest searcher becomes the
 * leader and invites the others into a group with the game's own invitation, inviting someone else in place of anyone who
 * declines. Once the group is whole, the window is the group's dungeon lobby ("Start" for the leader, "Ready" for the others).
 * The leader of a group wears a crown in the list of party members.
 *
 * Every game object is reached through HlxRuntime (see GameAccess): importing game classes here would compile private
 * copies of them into this mod, and the game would never see anything the mod does with those copies.
 */
@:build(hlx.runtime.Mod.build())
class DpfMod {
    @:hlx.config
    static var config:DpfConfig = {
        showButton: true, unpinned: false, buttonScalePercent: 100, panelX: 12, panelY: 320
    };

    static var ui = new UiKit();
    static var party = new GameParty();
    static var lobbies = new MpLobbyApi();
    static var session = new Session(party, lobbies);
    static var button = new DpfButton();
    static var list = new DungeonListWindow();
    static var crowns = new CrownMarker(ui);
    static var control = new SearchControl(ui, session, party);
    static var dungeons:Array<DungeonInfo> = null;
    static var dungeonsAt = -100.0;

    static function main():Void {
        config.save();
        button.x = config.panelX;
        button.y = config.panelY;
        button.onClick = toggleList;
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> config = ModConfig.load(HlxRuntime.moduleName(), config)
        );
    }

    /** The finder is out of the way until the character is in the world. */
    static var active = false;
    static var heroSeenAt = -1.0;
    static var noWindowSince = -1.0;
    static inline var ACTIVATE_DELAY = 3.0;
    /** A search whose window has been closed this long is given up. */
    static inline var WINDOW_GRACE = 1.5;

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        try tick(instance) catch (error:Dynamic) trace("[DPF] tick failed: " + Std.string(error));
        return Continue;
    }

    static function tick(app:Dynamic):Void {
        var now = haxe.Timer.stamp();
        party.app = app;
        DungeonScreens.app = app;
        try localizeSettings(now) catch (_:Dynamic) {}
        var hero = G.field(app, "hero");
        if (hero == null || G.field(app, "me") == null) {
            if (active) { active = false; button.hide(); list.hide(); crowns.hide(); }
            heroSeenAt = -1;
            session.update(now); // keeps its own pause while there is no hero
            return;
        }
        if (!active) {
            if (heroSeenAt < 0) heroSeenAt = now;
            if (now - heroSeenAt < ACTIVATE_DELAY) return;
            active = true;
        }

        session.update(now);
        watchWindow(now);
        var status = switch session.mode() { case Idle: 0; case Searching: 1; case Party: 2; };
        var scale = Math.max(0.5, Math.min(2.0, config.buttonScalePercent / 100));
        button.update(config.showButton, scale, config.unpinned, status, now);
        if (button.dragEnded) {
            button.dragEnded = false;
            config.panelX = button.x;
            config.panelY = button.y;
            config.save();
        }
        list.update();
        try crowns.update(party, now) catch (_:Dynamic) {}
    }

    /** The search button lives in the dungeon window: closing the window ends the search. */
    static function watchWindow(now:Float):Void {
        if (session.mode() != Searching || DungeonScreens.find() != null) { noWindowSince = -1; return; }
        if (noWindowSince < 0) noWindowSince = now;
        else if (now - noWindowSince > WINDOW_GRACE) { noWindowSince = -1; session.cancel(); }
    }

    // ---- the windows ----

    static function toggleList():Void {
        if (list.isOpen()) { list.hide(); return; }
        var now = haxe.Timer.stamp();
        if (dungeons == null || now - dungeonsAt > 30) {
            dungeons = GameDungeons.read();
            dungeonsAt = now;
        }
        list.show(dungeons, pick);
    }

    /** Opens the game's dungeon window for the dungeon (the one in front of the player is closed first). */
    static function pick(dungeon:DungeonInfo):Void {
        var open = DungeonScreens.find();
        if (open != null) {
            if (DungeonScreens.activityOf(open) == dungeon.id) { list.hide(); return; }
            if (session.mode() == Searching) session.cancel();
            DungeonScreens.close(open);
        }
        DungeonScreens.open(party, dungeon.id, () -> list.hide(), () -> list.hide());
    }

    @:hlx.postfix(ui.win.element.InstanceSelectScreen.update)
    static function afterDungeonWindowUpdate(instance:Dynamic, dt:Float, result:Void):Void {
        if (TestFlags.has("nocontrol")) return;
        try control.update(instance, dt) catch (error:Dynamic) trace("[DPF] dungeon window (" + control.stage + "): " + Std.string(error));
    }

    @:hlx.prefix(ui.win.element.InstanceSelectScreen.startAction)
    static function beforeDungeonStart(instance:Dynamic):HlxPrefixResult<Void> {
        // Not while a search runs, whichever way the action comes (mouse, keyboard, controller).
        return control.blocks(instance) ? Skip : Continue;
    }

    // ---- language ----

    static var localizedLanguage:String = null;
    static var nextLanguageCheck = 0.0;

    /**
     * Writes this mod's settings page (configFormats.json, re-read by Better Mod Settings each time its window opens) in the
     * client's language, and tells the windows which language to use. Checked once a second: the game's language option is
     * only known once the game has loaded its options, and can change while it runs.
     */
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
            session.cancel();
            lobbies.leave();
            button.hide();
            list.hide();
            crowns.hide();
        } catch (_:Dynamic) {}
        return Continue;
    }
}
