package integrator;

import integrator.GameAccess as G;

/**
 * Commands of the client (one JSON object each: {"id", "cmd", ...}); the answer is {"id", "ok", ...}.
 *  - ping
 *  - get {path, depth}: a value. The path starts at the GameApp ("hero.player.heroData") or at a static ("@Data.item").
 *    Names are fields, numbers index an array.
 *  - set {path, field, value}: sets a field of the object at the path.
 *  - call {path, type, method, args}: calls a method of the object at the path.
 *  - static {type, method, args}: calls a static method.
 *  - fields {path}: field names of the object at the path.
 *  - search {path, query}: records of the array at the path that have a text field containing the query.
 */
class Commands {
    public static var app:Dynamic;

    public static function handle(line:String):Dynamic {
        var id:Dynamic = null;
        try {
            var cmd:Dynamic = haxe.Json.parse(line);
            id = Reflect.field(cmd, "id");
            return run(cmd, id);
        } catch (e:Dynamic) {
            return {id: id, ok: false, error: Std.string(e)};
        }
    }

    static function run(cmd:Dynamic, id:Dynamic):Dynamic {
        var name = Std.string(Reflect.field(cmd, "cmd"));
        var depth = Reflect.hasField(cmd, "depth") ? Std.int(Reflect.field(cmd, "depth")) : 2;
        switch (name) {
            case "ping":
                return {id: id, ok: true, value: "pong"};
            case "get":
                var value = resolvePath(Std.string(Reflect.field(cmd, "path")));
                return {id: id, ok: true, type: G.typeName(value), value: toJson(value, depth)};
            case "set":
                var target = resolvePath(Std.string(Reflect.field(cmd, "path")));
                G.set(target, Std.string(Reflect.field(cmd, "field")), Reflect.field(cmd, "value"));
                return {id: id, ok: true};
            case "call":
                var target = resolvePath(Std.string(Reflect.field(cmd, "path")));
                var result = G.call(Std.string(Reflect.field(cmd, "type")), Std.string(Reflect.field(cmd, "method")), target, args(cmd));
                return {id: id, ok: true, type: G.typeName(result), value: toJson(result, depth)};
            case "search":
                var arr = resolvePath(Std.string(Reflect.field(cmd, "path")));
                var hits:Array<Dynamic> = [];
                var q = Std.string(Reflect.field(cmd, "query")).toLowerCase();
                for (i in 0...G.len(arr)) {
                    var found = matchIn(G.at(arr, i), q, 3, "");
                    if (found.length > 0) hits.push({index: i, matches: found});
                    if (hits.length >= 30) break;
                }
                return {id: id, ok: true, hits: hits};
            case "fields":
                var o = resolvePath(Std.string(Reflect.field(cmd, "path")));
                return {id: id, ok: true, fields: Reflect.fields(o)};
            case "static":
                var result = G.staticCall(Std.string(Reflect.field(cmd, "type")), Std.string(Reflect.field(cmd, "method")), args(cmd));
                return {id: id, ok: true, type: G.typeName(result), value: toJson(result, depth)};
            case "net_events":
                var since = Reflect.hasField(cmd, "since") ? Std.int(Reflect.field(cmd, "since")) : 0;
                var limit = Reflect.hasField(cmd, "limit") ? Std.int(Reflect.field(cmd, "limit")) : 100;
                var r = Net.events_since(since, limit);
                return {id: id, ok: true, events: r.events, last: r.last};
            case "net_send":
                return {id: id, ok: true, sent: Net.send(Std.string(Reflect.field(cmd, "hex")))};
            case "net_rule":
                return {id: id, ok: true, rule: Net.addRule(Reflect.field(cmd, "rule"))};
            case "net_rules":
                return {id: id, ok: true, rules: Net.allRules()};
            case "net_unrule":
                Net.removeRule(Std.int(Reflect.field(cmd, "rule")));
                return {id: id, ok: true};
            case "net_clear":
                Net.clear();
                return {id: id, ok: true};
            case "net_log":
                Net.logging = Reflect.field(cmd, "on") != false;
                return {id: id, ok: true, on: Net.logging};
            default:
                return {id: id, ok: false, error: "unknown command: " + name};
        }
    }

    /** Text fields (up to `depth` levels down) of a record that contain the query: ["field.path = text"]. */
    static function matchIn(value:Dynamic, q:String, depth:Int, prefix:String):Array<String> {
        var out:Array<String> = [];
        if (value == null) return out;
        if (isStringLike(value)) {
            var t = text(value);
            if (t.toLowerCase().indexOf(q) >= 0) out.push(prefix + " = " + t);
            return out;
        }
        if (depth <= 0 || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)) return out;
        var names:Array<String> = [];
        try names = Reflect.fields(value) catch (_:Dynamic) {}
        for (n in names) {
            if (StringTools.startsWith(n, "__")) continue;
            var child:Dynamic = try G.field(value, n) catch (_:Dynamic) null;
            out = out.concat(matchIn(child, q, depth - 1, prefix == "" ? n : prefix + "." + n));
        }
        return out;
    }

    static function args(cmd:Dynamic):Array<Dynamic> {
        var a:Dynamic = Reflect.field(cmd, "args");
        if (a == null) return [];
        // "@noop" stands for a callback (Bool)->Void that does nothing: the last argument of every apiRpc* method
        return [for (x in (a : Array<Dynamic>)) Std.isOfType(x, String) && x == "@noop" ? (function(_:Bool):Void {}) : x];
    }

    static function resolvePath(path:String):Dynamic {
        var value:Dynamic = app;
        var rest = path;
        if (StringTools.startsWith(path, "@")) {
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
            if (index != null && StringTools.trim(token) == Std.string(index) && G.typeName(value).indexOf("Array") >= 0) value = G.at(value, index);
            else value = G.field(value, token);
        }
        return value;
    }

    /** A game String as this module's own String, always rebuilt from its bytes (Json would print a game String as an object). */
    static function text(value:Dynamic):String {
        if (value == null) return "";
        var bytes:hl.Bytes = Reflect.field(value, "bytes");
        var length:Null<Int> = Reflect.field(value, "length");
        if (bytes == null || length == null || length < 0) return Std.string(value);
        return @:privateAccess String.__alloc__(bytes, length);
    }

    static function isStringLike(value:Dynamic):Bool {
        return Std.isOfType(value, String) || G.typeName(value) == "String" || (Reflect.hasField(value, "bytes") && Reflect.hasField(value, "length") && Reflect.fields(value).length == 2);
    }

    public static function toJson(value:Dynamic, depth:Int, seen:Array<Dynamic> = null):Dynamic {
        if (value == null) return null;
        if (Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)) return value;
        if (isStringLike(value)) return text(value);
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
        if (type.indexOf("StringMap") >= 0) {
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
}
