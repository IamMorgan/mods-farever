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
    var minPlayers:Int;
    var debugLog:Bool;
}

/**
 * Dungeon Party Finder: a "DPF" button on the screen opens the list of dungeons; a dungeon opens a window like the game's own
 * dungeon dialog with a "Search" button. The search puts the player together with others who picked the same dungeon and
 * difficulty and have a level of the same bracket (see Search): the earliest searcher becomes the leader and invites the
 * others into a group with the game's own invitation; then the window turns into the dungeon lobby ("Start" for the leader,
 * "Ready" for the others). The leader of a group wears a crown in the list of party members.
 *
 * Every game object is reached through HlxRuntime (see GameAccess): importing game classes here would compile private
 * copies of them into this mod, and the game would never see anything the mod does with those copies.
 */
@:build(hlx.runtime.Mod.build())
class DpfMod {
    @:hlx.config
    static var config:DpfConfig = {
        showButton: true, unpinned: false, buttonScalePercent: 100, panelX: 12, panelY: 320, minPlayers: 4, debugLog: false
    };

    static var ui = new UiKit();
    static var party = new GameParty();
    static var lobbies = new MpLobbyApi();
    static var button = new DpfButton(ui);
    static var list = new DungeonListWindow(ui);
    static var window = new SearchWindow(ui);
    static var crowns = new CrownMarker(ui);
    static var session:Session;
    static var dungeons:Array<DungeonInfo> = null;
    static var dungeonsAt = -100.0;
    static var scene:Dynamic;
    static var russian = false;

    static function main():Void {
        config.save();
        applyConfig();
        button.x = config.panelX;
        button.y = config.panelY;
        button.onClick = toggleList;
        list.whenClosed(() -> {});
        window.whenClosed(onWindowClosed);
        Bus.subscribe(
            "better-mod-settings/config-changed/" + HlxRuntime.moduleName(),
            (_:Dynamic) -> {
                config = ModConfig.load(HlxRuntime.moduleName(), config);
                applyConfig();
            }
        );
    }

    static function applyConfig():Void {
        Log.enabled = config.debugLog;
        var min = config.minPlayers < 2 ? 2 : (config.minPlayers > 4 ? 4 : config.minPlayers);
        if (session != null) session.setMinPlayers(min);
    }

    static function minPlayers():Int return config.minPlayers < 2 ? 2 : (config.minPlayers > 4 ? 4 : config.minPlayers);

    /** The finder is out of the way until the character is in the world. */
    static var active = false;
    static var heroSeenAt = -1.0;
    static inline var ACTIVATE_DELAY = 3.0;

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        try tick(instance) catch (error:Dynamic) Log.write("tick failed: " + Std.string(error));
        return Continue;
    }

    static function tick(app:Dynamic):Void {
        var now = haxe.Timer.stamp();
        party.app = app;
        scene = G.field(app, "s2d");
        try localizeSettings(now) catch (_:Dynamic) {}
        var hero = G.field(app, "hero");
        if (hero == null || G.field(app, "me") == null) {
            if (active) { active = false; button.hide(); list.hide(); window.hide(); crowns.hide(); }
            heroSeenAt = -1;
            if (session != null) session.update(now); // keeps its own pause while there is no hero
            return;
        }
        if (!active) {
            if (heroSeenAt < 0) heroSeenAt = now;
            if (now - heroSeenAt < ACTIVATE_DELAY) return;
            active = true;
        }

        if (session != null) session.update(now);
        var status = session == null ? 0 : (switch session.mode() { case Idle: 0; case Searching: 1; case Party: 2; });
        var scale = Math.max(0.5, Math.min(2.0, config.buttonScalePercent / 100));
        button.update(config.showButton, scale, config.unpinned, status, now);
        if (button.dragEnded) {
            button.dragEnded = false;
            config.panelX = button.x;
            config.panelY = button.y;
            config.save();
        }
        list.update();
        window.update(now);
        try crowns.update(party, now) catch (_:Dynamic) {}
    }

    // ---- the windows ----

    static function toggleList():Void {
        if (list.isOpen()) { list.hide(); return; }
        window.hide();
        if (session != null && !session.isBusy()) session = null;
        var now = haxe.Timer.stamp();
        if (dungeons == null || now - dungeonsAt > 30) {
            dungeons = GameDungeons.read();
            dungeonsAt = now;
            Log.write("dungeons: " + [for (d in dungeons) d.id + " (" + d.level + ")"].join(", "));
        }
        list.russian = russian;
        list.show(scene, dungeons, party.level(), session == null ? "" : session.dungeon.id, pick);
    }

    static function pick(dungeon:DungeonInfo):Void {
        list.hide();
        // One search at a time: a running one keeps its window.
        if (session == null || !session.isBusy()) session = new Session(dungeon, party, lobbies, minPlayers(), russian);
        window.russian = russian;
        window.show(scene, session);
    }

    static function onWindowClosed():Void {
        if (session != null && !session.isBusy()) session = null;
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
        var language = G.text(G.current("Options", "language"));
        if (language == "") language = G.text(G.staticCall("hxd.System", "get_lang", []));
        if (language == "" || language == localizedLanguage) return;
        localizedLanguage = language;
        russian = Locale.isRussian(language);
        list.russian = russian;
        window.russian = russian;
        if (session != null) session.russian = russian;
        var path = "hlx/mods/" + HlxRuntime.moduleName() + "/configFormats.json";
        var text = SettingsText.json(russian);
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
            if (session != null) session.cancel();
            lobbies.leave();
            button.hide();
            list.hide();
            window.hide();
            crowns.hide();
        } catch (_:Dynamic) {}
        return Continue;
    }
}
