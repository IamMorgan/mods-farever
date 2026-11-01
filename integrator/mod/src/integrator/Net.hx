package integrator;

import integrator.GameAccess as G;

/**
 * Network layer of the game (hxbit): every hooked call is noted in a ring of events, and the rules set by the client can
 * block it or patch the bytes in place.
 *  - dir "out": bytes the client sends (hxbit.NetworkHost/NetworkClient.send, mpman.net.*.send)
 *  - dir "in": bytes the client receives (hxbit.NetworkClient.processMessage/processMessagesData)
 *  - dir "rpc": a call of an object method on the server (hxbit.NetworkHost.doRPC): the object type and the rpc id
 * A rule: {dir, label?, type?, rpc?, prefix?, action: "block"|"patch", offset?, hex?, times?}
 *  - label: the hooked function; type: part of the object type name (rpc); rpc: the rpc id; prefix: hex the bytes start with.
 *  - patch writes `hex` at `offset` of the bytes (counted from the start of the message); times: how often it fires (default always).
 */
class Net {
    static inline var MAX_EVENTS = 1000;
    static inline var HEX_BYTES = 96;

    public static var logging = true;
    public static var client:Dynamic;
    static var events:Array<Dynamic> = [];
    static var seq = 0;
    static var rules:Array<Dynamic> = [];
    static var nextRule = 1;

    /** A raw message. Returns true when a rule blocks it. */
    public static function raw(dir:String, label:String, bytes:Dynamic, start:Int):Bool {
        if (bytes == null) return false;
        var length = G.len(bytes);
        var blocked = false;
        for (rule in rules.copy()) {
            if (!matches(rule, dir, label, null, -1, bytes, start)) continue;
            if (act(rule, bytes, start, length)) blocked = true;
        }
        if (logging) note({dir: dir, label: label, len: length - start, start: start, hex: hex(bytes, start, length), blocked: blocked});
        return blocked;
    }

    /** An rpc of an object. Returns true when a rule blocks it. */
    public static function rpc(label:String, object:Dynamic, id:Int):Bool {
        var type = G.typeName(object);
        var blocked = false;
        for (rule in rules.copy()) {
            if (!matches(rule, "rpc", label, type, id, null, 0)) continue;
            if (Reflect.field(rule, "action") == "block") { blocked = true; use(rule); }
        }
        if (logging) note({dir: "rpc", label: label, type: type, rpc: id, blocked: blocked});
        return blocked;
    }

    /** Sends the bytes (hex) through the game's mpman.net.Client; needs one earlier send of the game to know the client. */
    public static function send(hexText:String):Int {
        if (client == null) throw "no mpman.net.Client seen yet: make the game send something first";
        var count = Std.int(hexText.length / 2);
        var bytes = G.staticCall("haxe.io.Bytes", "alloc", [count]);
        for (i in 0...count) G.call("haxe.io.Bytes", "set", bytes, [i, Std.parseInt("0x" + hexText.substr(i * 2, 2))]);
        G.call("mpman.net.Client", "send", client, [bytes]);
        return count;
    }

    public static function events_since(since:Int, limit:Int):Dynamic {
        var out = events.filter(e -> Reflect.field(e, "n") > since);
        if (out.length > limit) out = out.slice(out.length - limit);
        return {events: out, last: seq};
    }

    public static function addRule(rule:Dynamic):Int {
        var id = nextRule++;
        Reflect.setField(rule, "id", id);
        rules.push(rule);
        return id;
    }

    public static function removeRule(id:Int):Void rules = rules.filter(r -> Reflect.field(r, "id") != id);

    public static function allRules():Array<Dynamic> return rules;

    public static function clear():Void {
        events = [];
        rules = [];
    }

    static function note(event:Dynamic):Void {
        Reflect.setField(event, "n", ++seq);
        events.push(event);
        if (events.length > MAX_EVENTS) events.shift();
    }

    static function matches(rule:Dynamic, dir:String, label:String, type:String, id:Int, bytes:Dynamic, start:Int):Bool {
        if (Reflect.field(rule, "dir") != dir) return false;
        var l:Dynamic = Reflect.field(rule, "label");
        if (l != null && l != label) return false;
        var t:Dynamic = Reflect.field(rule, "type");
        if (t != null && (type == null || type.indexOf(Std.string(t)) < 0)) return false;
        var r:Dynamic = Reflect.field(rule, "rpc");
        if (r != null && r != id) return false;
        var p:Dynamic = Reflect.field(rule, "prefix");
        if (p != null) {
            if (bytes == null) return false;
            var want = Std.string(p);
            if (hex(bytes, start, start + Std.int(want.length / 2)) != want) return false;
        }
        return true;
    }

    /** Runs the action of a rule; true when the message must be dropped. */
    static function act(rule:Dynamic, bytes:Dynamic, start:Int, length:Int):Bool {
        var action = Reflect.field(rule, "action");
        use(rule);
        if (action == "block") return true;
        if (action == "patch") {
            var offset = Reflect.hasField(rule, "offset") ? Std.int(Reflect.field(rule, "offset")) : 0;
            var h = Std.string(Reflect.field(rule, "hex"));
            for (i in 0...Std.int(h.length / 2)) {
                var at = start + offset + i;
                if (at >= length) break;
                G.call("haxe.io.Bytes", "set", bytes, [at, Std.parseInt("0x" + h.substr(i * 2, 2))]);
            }
        }
        return false;
    }

    static function use(rule:Dynamic):Void {
        var times:Dynamic = Reflect.field(rule, "times");
        if (times == null) return;
        var left = Std.int(times) - 1;
        Reflect.setField(rule, "times", left);
        if (left <= 0) removeRule(Reflect.field(rule, "id"));
    }

    static function hex(bytes:Dynamic, from:Int, to:Int):String {
        var out = new StringBuf();
        var end = Std.int(Math.min(to, from + HEX_BYTES));
        for (i in from...end) {
            var v = G.integer(G.call("haxe.io.Bytes", "get", bytes, [i]));
            out.add(StringTools.hex(v & 255, 2).toLowerCase());
        }
        return out.toString();
    }
}
