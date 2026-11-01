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
            case "static":
                var result = G.staticCall(Std.string(Reflect.field(cmd, "type")), Std.string(Reflect.field(cmd, "method")), args(cmd));
                return {id: id, ok: true, type: G.typeName(result), value: toJson(result, depth)};
            default:
                return {id: id, ok: false, error: "unknown command: " + name};
        }
    }

    static function args(cmd:Dynamic):Array<Dynamic> {
        var a:Dynamic = Reflect.field(cmd, "args");
        return a == null ? [] : a;
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
