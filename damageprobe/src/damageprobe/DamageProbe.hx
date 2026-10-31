package damageprobe;

import hlx.runtime.HlxPrefixResult;
import hlx.runtime.ResolvedMember;

/**
 * Developer probe, read-only: five seconds after the hero appears in the world it writes hlx/mods/damageprobe/probe.txt
 * with everything needed to see how a hit and its damage travel: the signatures (argument and return types) of the
 * hit / damage methods of the hero's classes and of the skill classes, the field types of the damage-related types,
 * and the damage-related fields of the live hero. The hero snapshot is repeated every 15 s (20 times at most) so the
 * values after some fighting are captured too. It hooks nothing but GameApp.update and changes nothing in the game.
 */
@:build(hlx.runtime.Mod.build())
class DamageProbe {
    static inline var DIR = "hlx/mods/damageprobe";
    static inline var OUT = DIR + "/probe.txt";
    static inline var DELAY = 5.0;
    static inline var REPEAT = 15.0;
    static inline var MAX_SNAPSHOTS = 20;

    static inline var KINDS = "void ui8 ui16 i32 i64 f32 f64 bool bytes dyn fun obj array type ref virtual dynobj abstract enum null method struct packed guid";
    static var kindNames = KINDS.split(" ");

    static var TYPES = [
        "ent.GameObject", "ent.Projectile", "st.skill.SkillArea", "st.skill.SkillContext", "st.skill.BaseSkill",
        "st.skill.DamageResult", "st.skill.HitResult"
    ];
    static var METHODS = [
        "rpcOnHit", "rpcOnHit__impl", "rpcTriggerClientHit", "rpcTriggerClientHit__impl", "rpcReceiveDamage",
        "rpcReceiveDamage__impl", "receiveDamage", "applyDamage", "computeDamage", "calcDamageAmount", "evalDamage",
        "onInflictDamage", "onReceiveDamage", "onInflictDamageEval", "onReceiveDamageEval", "onProxyDamage",
        "onProxyDamageEval", "damageUnit", "damageUnit__impl", "applyHitStrategy", "onHitNewTarget", "onHit",
        "onDamage", "displayDamage", "logDamage", "toDamage", "getDamageScale", "getDamageRatio", "getDamageStepIndex"
    ];

    static var seenAt = -1.0;
    static var nextSnapshot = 0.0;
    static var snapshots = 0;
    static var started = false;

    static function main():Void {}

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        try tick(instance) catch (error:Dynamic) {
            snapshots = MAX_SNAPSHOTS;
            try append(["probe failed: " + Std.string(error)]) catch (_:Dynamic) {}
        }
        return Continue;
    }

    static function tick(app:Dynamic):Void {
        var hero = field(app, "hero");
        if (hero == null || field(app, "me") == null) {
            seenAt = -1;
            return;
        }
        var now = haxe.Timer.stamp();
        if (seenAt < 0) seenAt = now;
        if (now - seenAt < DELAY || snapshots >= MAX_SNAPSHOTS || now < nextSnapshot) return;
        nextSnapshot = now + REPEAT;
        snapshots++;
        if (!started) {
            started = true;
            if (!sys.FileSystem.exists(DIR)) sys.FileSystem.createDirectory(DIR);
            sys.io.File.saveContent(OUT, "");
            append(["kinds: " + KINDS, "Instance methods list the receiver (this) as their first argument.", ""]);
            append(signatures(hero));
        }
        append(["", "=== hero snapshot " + snapshots + " ===", "hero class: " + typeName(hero)].concat(damageFields(hero)));
    }

    // ---- signatures ----

    static function signatures(hero:Dynamic):Array<String> {
        var lines:Array<String> = [];
        var names:Array<String> = [];
        var t = hl.Type.getDynamic(hero);
        while (t != null && t.kind == HObj) {
            names.push(t.getTypeName());
            t = t.getSuper();
        }
        lines.push("hero class chain: " + names.join(" > "));
        for (name in names.concat(TYPES)) {
            lines.push("");
            lines.push("## " + name);
            var resolved = HlxRuntime.resolveType(name);
            if (resolved == null) { lines.push("  type not found"); continue; }
            lines.push("  fields: " + fieldsText(resolved));
            for (method in METHODS) {
                var member:ResolvedMember = null;
                try member = HlxRuntime.resolveMember(resolved, method) catch (_:Dynamic) {}
                if (member != null) lines.push("  method " + method + ": " + signature(member));
            }
        }
        return lines;
    }

    static function signature(member:ResolvedMember):String {
        var type = member.type;
        if (type.getI32(0) != 10) return "kind=" + type.getI32(0);
        var fun = ptr(type, 8);
        var args = ptr(fun, 0);
        var count = fun.getI32(16);
        if (count != (cast type : hl.Type).getArgsCount() || count > 16) return "unexpected layout, nargs=" + count;
        return "(" + [for (i in 0...count) typeText(ptr(args, i * 8), 1)].join(", ") + ") -> " + typeText(ptr(fun, 8), 1);
    }

    /** Own fields of an object type (name:type), then the same for its parents. */
    static function fieldsText(type:hl.Bytes):String {
        var parts:Array<String> = [];
        var t = type;
        while (t != null && t.getI32(0) == 11) {
            var obj = ptr(t, 8);
            var fields = ptr(obj, 32);
            var own = [for (i in 0...obj.getI32(0)) ustr(ptr(fields, i * 24)) + ":" + typeText(ptr(fields, i * 24 + 8), 0)];
            parts.push("[" + typeName2(t) + "] " + own.join(", "));
            t = ptr(obj, 24);
        }
        return parts.join(" ");
    }

    /** `depth` 1 spells out virtual and object types with their fields. */
    static function typeText(t:hl.Bytes, depth:Int):String {
        if (t == null) return "null";
        var kind = t.getI32(0);
        var name = kind >= 0 && kind < kindNames.length ? kindNames[kind] : "kind" + kind;
        switch (kind) {
            case 11, 17, 18, 21: return typeName2(t);
            case 14, 19: return name + "<" + typeText(ptr(t, 8), depth) + ">";
            case 15:
                var virt = ptr(t, 8);
                var fields = ptr(virt, 0);
                return "{" + [for (i in 0...virt.getI32(8)) ustr(ptr(fields, i * 24)) + ":" + typeText(ptr(fields, i * 24 + 8), 0)].join(", ") + "}";
            default: return name;
        }
    }

    static function typeName2(t:hl.Bytes):String {
        var name:String = null;
        try name = (cast t : hl.Type).getTypeName() catch (_:Dynamic) {}
        return name == null ? "?" : name;
    }

    static function ptr(base:hl.Bytes, offset:Int):hl.Bytes {
        return hl.Bytes.fromAddress(haxe.Int64.make(base.getI32(offset + 4), base.getI32(offset)));
    }

    static function ustr(chars:hl.Bytes):String {
        return chars == null ? "?" : @:privateAccess String.fromUCS2(chars);
    }

    // ---- live hero ----

    /** Every field of the hero with "amage" or "hit" in its name, and the length of its damage history. */
    static function damageFields(hero:Dynamic):Array<String> {
        var lines:Array<String> = [];
        var names:Array<String> = [];
        try names = Reflect.fields(hero) catch (_:Dynamic) {}
        names.sort(Reflect.compare);
        for (name in names) {
            var low = name.toLowerCase();
            if (low.indexOf("amage") < 0 && low.indexOf("hit") < 0) continue;
            lines.push(name + " = " + valueText(field(hero, name), 3));
        }
        return lines;
    }

    static function valueText(value:Dynamic, depth:Int):String {
        if (value == null) return "null";
        if (Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)) return Std.string(value);
        var type = typeName(value);
        if (type == "String") return "\"" + str(value) + "\"";
        if (depth <= 0) return "<" + type + ">";
        var length = field(value, "length");
        if (type.indexOf("Array") >= 0 && length != null) {
            var items = [for (i in 0...Std.int(Math.min(length, 6))) valueText(try call(type, "getDyn", value, [i]) catch (_:Dynamic) null, depth - 1)];
            return type + "[" + length + "] {" + items.join(", ") + (length > 6 ? ", ..." : "") + "}";
        }
        var names:Array<String> = [];
        try names = Reflect.fields(value) catch (_:Dynamic) {}
        if (names.length == 0) return "<" + type + ">";
        return type + " {" + [for (n in names.slice(0, 40)) n + "=" + valueText(field(value, n), depth - 1)].join(", ") + "}";
    }

    // ---- game access ----

    static function field(object:Dynamic, name:String):Dynamic {
        if (object == null) return null;
        try return Reflect.field(object, name) catch (_:Dynamic) return null;
    }

    static function call(type:String, name:String, object:Dynamic, args:Array<Dynamic>):Dynamic {
        var member = HlxRuntime.resolveMember(HlxRuntime.resolveType(type), name);
        return HlxRuntime.callResolved(member, [object].concat(args));
    }

    static function typeName(object:Dynamic):String {
        if (object == null) return "";
        try return hl.Type.getDynamic(object).getTypeName() catch (_:Dynamic) return "";
    }

    /** A game String as this module's own String. */
    static function str(value:Dynamic):String {
        if (Std.isOfType(value, String)) return value;
        var bytes:hl.Bytes = Reflect.field(value, "bytes");
        var length:Null<Int> = Reflect.field(value, "length");
        if (bytes == null || length == null || length < 0) return Std.string(value);
        return @:privateAccess String.__alloc__(bytes, length);
    }

    static function append(lines:Array<String>):Void {
        var file = sys.io.File.append(OUT);
        for (line in lines) file.writeString(line + "\n");
        file.close();
    }
}
