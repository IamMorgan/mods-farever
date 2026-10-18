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
 *  - select {chest}: selects a chest of the list. search {text}: types in the search of the chest list.
 *  - dump: every chest with its name, where to get it and its contents (the chance of each item) for the hero now.
 *  - names {text}: which chests the search finds for that text (and how long the first search took).
 *  - buttons: the buttons of the chest list (selected state, style classes). layers: the scene's layers, the window's parents, the tab bar's place.
 *  - click {chest}: clicks the button of a chest as the mouse does. textfonts: the fonts of the description. movebar {index}: moves the tab bar among the scene's children.
 *  - raw {chest}: the unfiltered loot table of a chest; table {id2}; tables {text}: loot tables by id; finditems {text}: items by id or name; mkitem {item, level, minRarity}: the item as the game makes it.
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
            heroKnown: CodexLoot.hero != null, heroApts: heroApts(), russian: SettingsText.russian, tabBar: CodexTabs.debug(), chests: [for (c in ChestData.chests()) ChestData.idOf(c)]};
    }

    static function heroApts():Array<String> {
        var apts = G.field(G.field(G.field(G.field(CodexLoot.hero, "inf"), "props"), "aptitudes"), "length") == null ? [] : [];
        var list = G.field(G.field(G.field(CodexLoot.hero, "inf"), "props"), "aptitudes");
        for (i in 0...G.len(list)) apts.push(G.str(G.field(G.at(list, i), "ref")));
        return apts;
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
            items: [for (e in loot.entries) {id: G.str(G.field(e.item, "id")), name: Sheets.name("item", G.str(G.field(e.item, "id"))), chance: Math.round(e.chance * 10000) / 10000, mine: e.mine,
                shownRarity: LootUi.rarityOf(LootUi.realItem(e.item, loot.level, loot.minRarity), e.item)}]};
    }

    /** A loot table as the game's data holds it (every row, unfiltered), sub-tables included. */
    static function rawTable(id:String, depth:Int):Dynamic {
        var table = Sheets.get("lootTable").get(id);
        if (table == null) return {id: id, missing: true};
        var rows:Array<Dynamic> = [];
        var loot = G.field(table, "loot");
        var items = Sheets.get("item");
        for (i in 0...G.len(loot)) {
            var e = G.at(loot, i);
            if (e == null) continue;
            var itemId = G.str(G.field(e, "item"));
            var rec = items.get(itemId);
            var row:Dynamic = {item: itemId, name: itemId == "" ? "" : Sheets.name("item", itemId), rarity: rec == null ? "" : G.str(G.field(rec, "rarity")),
                itemLevel: rec == null ? "" : G.str(G.field(rec, "level")), gfx: rec != null && G.field(rec, "gfx") != null,
                proba: G.str(G.field(e, "proba")), itemMin: G.str(G.field(e, "itemMin")), itemMax: G.str(G.field(e, "itemMax")),
                minLvl: G.str(G.field(e, "minLvl")), maxLvl: G.str(G.field(e, "maxLvl")), flags: G.str(G.field(e, "flags"))};
            var sub = G.str(G.field(e, "lootTable"));
            if (sub != "") Reflect.setField(row, "sub", depth > 4 ? sub : rawTable(sub, depth + 1));
            rows.push(row);
        }
        return {id: id, flags: G.str(G.field(table, "flags")), rows: rows};
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
                var chest = chestById(Std.string(Reflect.field(cmd, "chest")));
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
            case "raw":
                var item = Sheets.get("item").get(Std.string(Reflect.field(cmd, "chest")));
                if (item == null) { answer({id: id, cmd: name, ok: false, error: "no such item"}); return; }
                var gain = ChestLoot.gainOf(item);
                answer({id: id, cmd: name, ok: true, iLevel: G.str(G.field(item, "iLevel")), rarity: G.str(G.field(item, "rarity")),
                    gain: {lootTable: G.str(G.field(gain, "lootTable")), maxItems: G.str(G.field(gain, "maxItems")), mode: G.str(G.field(gain, "mode")),
                        rarity: G.str(G.field(G.field(gain, "rarity"), "min")) + "/" + G.str(G.field(G.field(gain, "rarity"), "max")),
                        levelRange: G.str(G.field(G.field(gain, "levelRange"), "min")) + "-" + G.str(G.field(G.field(gain, "levelRange"), "max"))},
                    table: rawTable(G.str(G.field(gain, "lootTable")), 0)});
            case "finditems":
                var text = Std.string(Reflect.field(cmd, "text")).toLowerCase();
                var found:Array<Dynamic> = [];
                for (iid => rec in Sheets.get("item")) {
                    var nm = Sheets.name("item", iid);
                    if (iid.toLowerCase().indexOf(text) < 0 && nm.toLowerCase().indexOf(text) < 0) continue;
                    found.push({id: iid, name: nm, rarity: G.str(G.field(rec, "rarity")), level: G.str(G.field(rec, "level")), iLevel: G.str(G.field(rec, "iLevel")),
                        type: G.str(G.field(rec, "type")), flags: G.str(G.field(rec, "flags")), gfx: G.field(rec, "gfx") != null,
                        aptitudes: [for (i in 0...G.len(G.field(rec, "aptitudes"))) G.str(G.field(G.at(G.field(rec, "aptitudes"), i), "ref"))]});
                }
                found.sort((a, b) -> Reflect.compare(a.id, b.id));
                answer({id: id, cmd: name, ok: true, count: found.length, items: found});
            case "tables":
                var text = Std.string(Reflect.field(cmd, "text")).toLowerCase();
                var list:Array<Dynamic> = [];
                for (tid => t in Sheets.get("lootTable")) if (tid.toLowerCase().indexOf(text) >= 0) list.push({id: tid, flags: G.str(G.field(t, "flags")), rows: G.len(G.field(t, "loot"))});
                list.sort((a, b) -> Reflect.compare(a.id, b.id));
                answer({id: id, cmd: name, ok: true, tables: list});
            case "table":
                answer({id: id, cmd: name, ok: true, table: rawTable(Std.string(Reflect.field(cmd, "id2")), 0)});
            case "mkitem":
                var iid = Std.string(Reflect.field(cmd, "item"));
                var minR = Reflect.field(cmd, "minRarity") == null ? null : Std.string(Reflect.field(cmd, "minRarity"));
                var lvl = Std.parseInt(Std.string(Reflect.field(cmd, "level")));
                var drop = {count: 1, flags: null, item: iid, itemFlags: null, lootLevel: lvl, lootTableFlags: null, maxRarity: null, minRarity: minR, rarity: minR};
                var made = G.callStatic("st.Item", "create", [iid, drop]);
                var inf = G.field(made, "inf");
                answer({id: id, cmd: name, ok: made != null, type: G.typeName(made), rarity: G.str(G.field(made, "rarity")), infRarity: G.str(G.field(inf, "rarity")),
                    level: G.str(G.field(made, "level")), iLevel: G.str(G.field(made, "iLevel")), affixes: G.len(G.field(made, "affixes")),
                    fields: [for (f in ["rarityIdx", "quality", "ilvl", "lootLevel", "stats", "customRarity"]) f + "=" + G.str(G.field(made, f))]});
            case "itemnames":
                var item = Sheets.get("item").get(Std.string(Reflect.field(cmd, "chest")));
                answer({id: id, cmd: name, ok: item != null, names: item == null ? null : ChestNames.of(item)});
            case "fonts":
                var w = codexWindow();
                var list:Array<Dynamic> = [];
                var seen:Array<Dynamic> = [];
                var stack:Array<Dynamic> = [G.field(app, "s2d")];
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
            case "movebar":
                CodexTabs.debugMove(Std.parseInt(Std.string(Reflect.field(cmd, "index"))));
                answer({id: id, cmd: name, ok: true, layers: layers()});
            case "textfonts":
                answer({id: id, cmd: name, ok: true, fonts: ChestSheet.debugFonts()});
            case "buttons":
                answer({id: id, cmd: name, ok: true, buttons: ChestSheet.debugButtons()});
            case "layers":
                answer({id: id, cmd: name, ok: true, layers: layers()});
            case "click":
                answer({id: id, cmd: name, ok: ChestSheet.debugClick(Std.string(Reflect.field(cmd, "chest"))), buttons: ChestSheet.debugButtons()});
            case "screenshot":
                var file = Reflect.field(cmd, "file") != null ? Std.string(Reflect.field(cmd, "file")) : "screen.png";
                screenshot(DIR + "/" + file);
                answer({id: id, cmd: name, ok: true, file: DIR + "/" + file, status: status()});
            default:
                answer({id: id, cmd: name, ok: false, error: "unknown command"});
        }
    }

    static function describeObject(o:Dynamic):Dynamic {
        return {type: G.typeName(o), x: G.num(G.field(o, "x")), y: G.num(G.field(o, "y")), scaleX: G.num(G.field(o, "scaleX")), absX: G.num(G.field(o, "absX")), absY: G.num(G.field(o, "absY")),
            visible: G.field(o, "visible"), kids: G.len(G.field(o, "children"))};
    }

    static function layers():Dynamic {
        var scene = G.field(app, "s2d");
        var list:Array<Dynamic> = [];
        var kids = G.children(scene);
        for (i in 0...kids.length) {
            var d = describeObject(kids[i]);
            Reflect.setField(d, "index", i);
            list.push(d);
        }
        var chain:Array<Dynamic> = [];
        var w:Dynamic = codexWindow();
        var window = w == null ? null : describeObject(w);
        if (w != null) {
            Reflect.setField(window, "calculatedHeight", G.num(G.field(w, "calculatedHeight")));
            Reflect.setField(window, "calculatedWidth", G.num(G.field(w, "calculatedWidth")));
            Reflect.setField(window, "matA", G.num(G.field(w, "matA")));
            Reflect.setField(window, "matD", G.num(G.field(w, "matD")));
            Reflect.setField(window, "overflow", G.str(G.field(w, "overflow")));
            var p = G.field(w, "parent");
            while (p != null) { chain.push(describeObject(p)); p = G.field(p, "parent"); }
        }
        var ui = baseUi();
        var named:Dynamic = {};
        for (n in ["root", "rootTips", "rootOverlay", "rootCursor", "rootBG"]) {
            var o = G.field(ui, n);
            var idx = -1;
            for (i in 0...kids.length) if (kids[i] == o) idx = i;
            Reflect.setField(named, n, o == null ? null : {index: idx, type: G.typeName(o)});
        }
        return {scene: list, window: window, windowParents: chain, ui: named, tabs: CodexTabs.debug()};
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
