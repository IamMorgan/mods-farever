package farmer;

import farmer.GameAccess as G;

/**
 * Developer probe: reads the running game through files. It is on only while the folder hlx/config/farmer/test exists
 * (the archive does not contain it), so the shipped mod never looks for commands.
 *
 * A command is written to hlx/config/farmer/test/command.json ({"id": "...", "cmd": "...", ...}); the mod takes it (the
 * file is removed), runs it and writes the answer to result.json ({"id", "ok", ...}).
 *
 * Commands:
 *  - get {path, depth}: a value. The path starts at the GameApp ("hero.player.heroData") or at a static ("@Data.item").
 *    Names are fields, numbers index an array.
 *  - dump {path, file, depth}: the value as JSON into a file of the test folder.
 *  - call {path, type, method, args}: calls a method of the object at the path (args: JSON numbers/strings/bools).
 *  - static {type, method, args}: calls a static method.
 *  - eval {code}: reserved.
 */
class Probe {
    public static inline var DIR = "hlx/config/farmer/test";
    static inline var COMMAND = DIR + "/command.json";
    static inline var RESULT = DIR + "/result.json";

    static var nextCheck = 0.0;
    public static var app:Dynamic;
    /** Extra commands of the mod (name -> handler). */
    public static var extra:Map<String, Dynamic -> Dynamic> = [];

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

    static function answer(value:Dynamic):Void {
        sys.io.File.saveContent(RESULT, haxe.Json.stringify(value, null, "  "));
    }

    static function resolvePath(path:String):Dynamic {
        var value:Dynamic = app;
        var rest = path;
        if (StringTools.startsWith(path, "@")) {
            var cut = path.indexOf(".");
            var typeName = cut < 0 ? path.substr(1) : path.substr(1, cut - 1);
            rest = cut < 0 ? "" : path.substr(cut + 1);
            // "@Data.item" - the type may itself contain dots: the longest known prefix wins
            var parts = path.substr(1).split(".");
            var found = false;
            var i = parts.length - 1;
            while (i >= 1 && !found) {
                var t = HlxRuntime.resolveType(parts.slice(0, i).join("."));
                if (t != null) {
                    value = HlxRuntime.resolveStaticField(t, parts[i]);
                    rest = parts.slice(i + 1).join(".");
                    found = true;
                }
                i--;
            }
            if (!found) throw "static not found: " + path;
        }
        if (rest == "") return value;
        for (token in rest.split(".")) {
            if (token == "") continue;
            var index = Std.parseInt(token);
            if (index != null && StringTools.trim(token) == Std.string(index)) {
                if (G.typeName(value).indexOf("Array") >= 0) value = G.at(value, index);
                else value = G.field(value, token);
            } else if (token == "length") value = G.field(value, "length");
            else value = G.field(value, token);
        }
        return value;
    }

    static function isStringLike(value:Dynamic):Bool {
        return Std.isOfType(value, String) || G.typeName(value) == "String";
    }

    public static function toJson(value:Dynamic, depth:Int, seen:Array<Dynamic> = null):Dynamic {
        if (value == null) return null;
        if (Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)) return value;
        if (isStringLike(value)) return G.str(value);
        if (seen == null) seen = [];
        var type = G.typeName(value);
        if (depth <= 0) return "<" + type + ">";
        for (s in seen) if (s == value) return "<cycle " + type + ">";
        if (type.indexOf("Array") >= 0) {
            var out:Array<Dynamic> = [];
            var n = G.len(value);
            for (i in 0...Std.int(Math.min(n, 4000))) out.push(toJson(try G.at(value, i) catch (_:Dynamic) null, depth - 1, seen));
            if (n > 4000) out.push("... " + n + " in all");
            return out;
        }
        if (type.indexOf("Map") >= 0 && type.indexOf("StringMap") >= 0) {
            var out:Dynamic = {};
            try {
                var keys = G.call(type, "keys", value);
                while (G.call("haxe.iterators.ArrayIterator", "hasNext", keys) == true) {
                    var k = G.s(G.call("haxe.iterators.ArrayIterator", "next", keys));
                    Reflect.setField(out, k, toJson(G.call(type, "get", value, [k]), depth - 1, seen));
                }
            } catch (_:Dynamic) { return "<" + type + ">"; }
            return out;
        }
        var out:Dynamic = {};
        seen.push(value);
        var names:Array<String> = [];
        try names = Reflect.fields(value) catch (_:Dynamic) {}
        if (names.length == 0) { seen.pop(); return "<" + type + ">"; }
        for (n in names) {
            if (StringTools.startsWith(n, "__")) continue;
            Reflect.setField(out, n, toJson(G.field(value, n), depth - 1, seen));
        }
        seen.pop();
        return out;
    }

    static function args(cmd:Dynamic):Array<Dynamic> {
        var a:Dynamic = Reflect.field(cmd, "args");
        return a == null ? [] : a;
    }

    static function run(cmd:Dynamic, id:String, name:String):Void {
        var depth = Reflect.hasField(cmd, "depth") ? Std.int(Reflect.field(cmd, "depth")) : 2;
        switch (name) {
            case "get":
                var value = resolvePath(Std.string(Reflect.field(cmd, "path")));
                answer({id: id, cmd: name, ok: true, type: G.typeName(value), value: toJson(value, depth)});
            case "dump":
                var value = resolvePath(Std.string(Reflect.field(cmd, "path")));
                var file = DIR + "/" + Std.string(Reflect.field(cmd, "file"));
                sys.io.File.saveContent(file, haxe.Json.stringify(toJson(value, Reflect.hasField(cmd, "depth") ? depth : 8)));
                answer({id: id, cmd: name, ok: true, file: file, type: G.typeName(value)});
            case "rows":
                // rows {path, fields:["id","texts.name"], filter, limit}: one line per record of an array, selected fields only
                var value = resolvePath(Std.string(Reflect.field(cmd, "path")));
                var fields:Array<String> = Reflect.field(cmd, "fields");
                var filter:String = Reflect.field(cmd, "filter");
                var limit = Reflect.hasField(cmd, "limit") ? Std.int(Reflect.field(cmd, "limit")) : 3000;
                var lines:Array<String> = [];
                for (i in 0...G.len(value)) {
                    var record = G.at(value, i);
                    var cells:Array<String> = [];
                    for (f in fields) {
                        var v:Dynamic = record;
                        for (part in f.split(".")) v = G.field(v, part);
                        cells.push(v == null ? "-" : (isStringLike(v) ? G.s(v) : (Std.isOfType(v, Bool) || Std.isOfType(v, Int) || Std.isOfType(v, Float) ? Std.string(v) : "<" + G.typeName(v) + (G.typeName(v).indexOf("Array") >= 0 ? " " + G.len(v) : "") + ">")));
                    }
                    var line = cells.join(" | ");
                    if (filter != null && line.indexOf(filter) < 0) continue;
                    lines.push(line);
                    if (lines.length >= limit) break;
                }
                answer({id: id, cmd: name, ok: true, total: G.len(value), lines: lines});
            case "elements":
                // elements {map, type, limit}: map elements (HElement.allElements) of one map / Element_type
                var table = G.current("HElement", "allElements");
                var wantMap:String = Reflect.field(cmd, "map");
                var wantType:Dynamic = Reflect.field(cmd, "type");
                var cap2 = Reflect.hasField(cmd, "limit") ? Std.int(Reflect.field(cmd, "limit")) : 400;
                var rowsOut:Array<String> = [];
                var keys = G.call(G.typeName(table), "keys", table);
                while (G.call("haxe.iterators.ArrayIterator", "hasNext", keys) == true && rowsOut.length < cap2) {
                    var k = G.s(G.call("haxe.iterators.ArrayIterator", "next", keys));
                    var def = G.call(G.typeName(table), "get", table, [k]);
                    if (wantMap != null && G.s(G.field(def, "mapId")) != wantMap) continue;
                    var inf = G.field(def, "inf");
                    var ty = G.integer(G.field(inf, "type"), -1);
                    if (wantType != null && ty != Std.int(wantType)) continue;
                    var posText = "?";
                    try {
                        var m = G.call("hrt.prefab.Object3D", "getAbsPos", G.field(def, "prefab"), [true]);
                        posText = Math.round(G.number(G.field(m, "_41"))) + "," + Math.round(G.number(G.field(m, "_42"))) + "," + Math.round(G.number(G.field(m, "_43")));
                    } catch (_:Dynamic) {}
                    rowsOut.push(k + " | type " + ty + " | " + G.s(G.field(def, "mapId")) + " | " + posText + " | " + G.s(G.field(inf, "inherit")) + " | " + G.s(G.field(G.field(inf, "props"), "targetZone")));
                }
                answer({id: id, cmd: name, ok: true, lines: rowsOut});
            case "call":
                var target = resolvePath(Std.string(Reflect.field(cmd, "path")));
                var result = G.call(Std.string(Reflect.field(cmd, "type")), Std.string(Reflect.field(cmd, "method")), target, args(cmd));
                answer({id: id, cmd: name, ok: true, type: G.typeName(result), value: toJson(result, depth)});
            case "static":
                var result = G.staticCall(Std.string(Reflect.field(cmd, "type")), Std.string(Reflect.field(cmd, "method")), args(cmd));
                answer({id: id, cmd: name, ok: true, type: G.typeName(result), value: toJson(result, depth)});
            default:
                var handler = extra.get(name);
                if (handler == null) answer({id: id, cmd: name, ok: false, error: "unknown command"});
                else answer({id: id, cmd: name, ok: true, value: handler(cmd)});
        }
    }
}
