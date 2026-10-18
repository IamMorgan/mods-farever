package codexloot;

/**
 * Test mode: the assistant drives the Codex in the running game through files. It is on only while the folder
 * hlx/config/codexloot/test exists (the archive does not contain it), so the shipped mod never looks for commands.
 *
 * A command is written to hlx/config/codexloot/test/command.json ({"id": "...", "cmd": "...", ...}); the mod takes it (the
 * file is removed), runs it and writes the answer to result.json ({"id", "ok", "cmd", ...}). Nothing is sent to the server.
 *
 * Commands:
 *  - status: the Codex window, its tab, the chests listed, the selected chest, the hero.
 *  - open / close: opens the Codex window as the game does / closes it.
 *  - tab {tab: "codex" | "chests"}: switches the tab as a click on it does.
 *  - select {id}: selects a chest of the list. search {text}: types in the search of the chest list.
 *  - dump: every chest with its name, where to get it and its contents (the chance of each item) for the hero now.
 *  - names {text}: which chests the search finds for that text (and how long the first search took).
 *  - screenshot {file}: the game's 2D scene (all its windows) saved as a PNG in the test folder.
 */
class TestMode {
    public static inline var DIR = "hlx/config/codexloot/test";
    static inline var COMMAND = DIR + "/command.json";
    static inline var RESULT = DIR + "/result.json";

    static var nextCheck = 0.0;
    static var app:Dynamic;

    /** Each frame (GameApp.update): looks for a command twice a second, while the test folder exists. */
    public static function tick(gameApp:Dynamic):Void {
        app = gameApp;
        var now = haxe.Timer.stamp();
        if (now < nextCheck) return;
        nextCheck = now + 0.5;
        if (!sys.FileSystem.exists(DIR) || !sys.FileSystem.exists(COMMAND)) return;
        var cmd:Dynamic = null;
        try {
            var text = sys.io.File.getContent(COMMAND);
            sys.FileSystem.deleteFile(COMMAND);
            cmd = haxe.Json.parse(text);
        } catch (e:Dynamic) {
            answer({id: "?", ok: false, error: "the command file could not be read: " + Std.string(e)});
            return;
        }
        var id = Std.string(Reflect.field(cmd, "id"));
        var name = Std.string(Reflect.field(cmd, "cmd"));
        try run(cmd, id, name) catch (e:Dynamic) answer({id: id, cmd: name, ok: false, error: Std.string(e)});
    }

    static function baseUi():Dynamic return HlxRuntime.resolveStaticField(HlxRuntime.resolveType("ui.BaseUI"), "current");

    static function codexWindow():Dynamic {
        var windows = G.field(baseUi(), "windows");
        for (i in 0...G.len(windows)) {
            var w = G.at(windows, i);
            if (G.typeName(w) == "ui.win.codex.CodexWindow") return w;
        }
        return null;
    }

    static function status():Dynamic {
        var w = codexWindow();
        return {window: w != null, chestMode: CodexTabs.inChestMode(), selected: ChestSheet.selected(), listed: ChestSheet.listed(),
            heroKnown: CodexLoot.hero != null, russian: SettingsText.russian, tabBar: CodexTabs.debug(), chests: [for (c in ChestData.chests()) ChestData.idOf(c)]};
    }

    static function chestById(id:String):Dynamic {
        for (c in ChestData.chests()) if (ChestData.idOf(c) == id) return c;
        return null;
    }

    static function describeChest(chest:Dynamic):Dynamic {
        var loot = ChestLoot.compute(chest, CodexLoot.hero);
        return {id: ChestData.idOf(chest), name: ChestData.nameOf(chest), rarity: G.str(G.field(chest, "rarity")),
            lines: ChestData.describe(chest, loot), level: loot.level, maxItems: loot.maxItems, weighted: loot.weighted, affinity: loot.affinity,
            ownedLast: loot.ownedLast, minRarity: loot.minRarity, pool: loot.pool,
            items: [for (e in loot.entries) {id: G.str(G.field(e.item, "id")), name: Sheets.name("item", G.str(G.field(e.item, "id"))), chance: Math.round(e.chance * 10000) / 10000}]};
    }

    static function run(cmd:Dynamic, id:String, name:String):Void {
        switch (name) {
            case "status":
                answer({id: id, cmd: name, ok: true, status: status()});
            case "open":
                if (codexWindow() == null) {
                    var w = HlxRuntime.constructInstanceByName(HlxRuntime.resolveType("ui.win.codex.CodexWindow"), 1, [null]);
                    G.call("ui.BaseUI", "displayWindow", [baseUi(), w, null]);
                }
                answer({id: id, cmd: name, ok: true, status: status()});
            case "close":
                var w = codexWindow();
                if (w != null) G.call("ui.win.BaseWindow", "closeWindow", [w, null]);
                answer({id: id, cmd: name, ok: w != null, status: status()});
            case "tab":
                if (codexWindow() == null) { answer({id: id, cmd: name, ok: false, error: "the Codex window is not open"}); return; }
                CodexTabs.switchTo(Std.string(Reflect.field(cmd, "tab")) == "chests");
                answer({id: id, cmd: name, ok: true, status: status()});
            case "select":
                var chest = chestById(Std.string(Reflect.field(cmd, "id")));
                if (chest == null || !CodexTabs.inChestMode()) { answer({id: id, cmd: name, ok: false, error: "no such chest, or the Chests tab is not shown"}); return; }
                ChestSheet.select(chest);
                answer({id: id, cmd: name, ok: true, status: status()});
            case "search":
                var sheet = ChestSheet.current();
                if (sheet == null) { answer({id: id, cmd: name, ok: false, error: "the Chests tab is not shown"}); return; }
                G.call("ui.comp.SearchInput", "set_text", [G.field(sheet, "search"), Std.string(Reflect.field(cmd, "text"))]);
                var t0 = haxe.Timer.stamp();
                ChestSheet.refresh(sheet);
                answer({id: id, cmd: name, ok: true, ms: Math.round((haxe.Timer.stamp() - t0) * 1000), status: status()});
            case "dump":
                answer({id: id, cmd: name, ok: true, chests: [for (c in ChestData.chests()) describeChest(c)], status: status()});
            case "names":
                var text = Std.string(Reflect.field(cmd, "text"));
                var t0 = haxe.Timer.stamp();
                var found = [for (c in ChestData.chests()) if (ChestSheet.chestMatches(c, text)) ChestData.idOf(c)];
                answer({id: id, cmd: name, ok: true, text: text, found: found, ms: Math.round((haxe.Timer.stamp() - t0) * 1000)});
            case "inspect":
                var sheet = ChestSheet.current();
                if (sheet == null) { answer({id: id, cmd: name, ok: false, error: "the Chests tab is not shown"}); return; }
                var out:Dynamic = {};
                for (n in ["listPanel", "unitList", "unitPanel", "dataPanel", "leftPanel", "lorePanel", "loreTitle", "description", "progressPanel", "dropsPanel", "dropHeader", "dropsIconsRoot", "dropsIcons", "rightPanel"]) {
                    var o = G.field(sheet, n);
                    Reflect.setField(out, n, o == null ? null : {type: G.typeName(o), x: G.num(G.field(o, "x")), y: G.num(G.field(o, "y")), w: G.num(G.field(o, "calculatedWidth")),
                        h: G.num(G.field(o, "calculatedHeight")), minH: G.field(o, "minHeight"), maxH: G.field(o, "maxHeight"), visible: G.field(o, "visible"), overflow: G.str(G.field(o, "overflow"))});
                }
                answer({id: id, cmd: name, ok: true, parts: out});
            case "itemnames":
                var item = Sheets.get("item").get(Std.string(Reflect.field(cmd, "id")));
                answer({id: id, cmd: name, ok: item != null, names: item == null ? null : ChestNames.of(item)});
            case "fonts":
                var w = codexWindow();
                var list:Array<Dynamic> = [];
                var seen:Array<Dynamic> = [];
                var stack:Array<Dynamic> = [w];
                var n = 0;
                while (stack.length > 0 && n < 4000) {
                    var o = stack.pop();
                    n++;
                    if (o == null) continue;
                    var f = G.field(o, "font");
                    if (f != null && seen.indexOf(f) < 0) {
                        seen.push(f);
                        list.push({node: G.typeName(o), name: G.str(G.field(f, "name")), size: G.num(G.field(f, "size")), cyr: G.call("h2d.Font", "hasChar", [f, 0x0411]), sub: G.len(G.field(f, "subFonts"))});
                    }
                    for (c in G.children(o)) stack.push(c);
                }
                answer({id: id, cmd: name, ok: true, used: LootUi.font == null ? null : {name: G.str(G.field(LootUi.font, "name")), cyr: G.call("h2d.Font", "hasChar", [LootUi.font, 0x0411])}, fonts: list});
            case "screenshot":
                var file = Reflect.field(cmd, "file") != null ? Std.string(Reflect.field(cmd, "file")) : "screen.png";
                screenshot(DIR + "/" + file);
                answer({id: id, cmd: name, ok: true, file: DIR + "/" + file, status: status()});
            default:
                answer({id: id, cmd: name, ok: false, error: "unknown command"});
        }
    }

    static function screenshot(path:String):Void {
        var s2d = G.field(app, "s2d");
        if (s2d == null) throw "no 2D scene";
        var bmp = G.call("h2d.Scene", "captureBitmap", [s2d, null]);
        var tile = G.field(bmp, "tile");
        var tex = G.call("h2d.Tile", "getTexture", [tile]);
        var pixels = G.call("h3d.mat.Texture", "capturePixels", [tex, null, null, null]);
        var png = G.call("hxd.Pixels", "toPNG", [pixels, null]);
        G.callStatic("sys.io.File", "saveBytes", [path, png]);
        try G.call("h3d.mat.Texture", "dispose", [tex]) catch (_:Dynamic) {}
    }

    static function answer(o:Dynamic):Void {
        try {
            Reflect.setField(o, "at", Date.now().toString());
            sys.io.File.saveContent(RESULT, haxe.Json.stringify(o, null, "  "));
        } catch (_:Dynamic) {}
    }
}
