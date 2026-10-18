package buildcalc.sim;

import buildcalc.sim.Script.Expr;

/** An object a script can read, write and call (units, hits, statuses, skills of the simulation). */
interface IObj {
    function get(name:String):Dynamic;
    function set(name:String, v:Dynamic):Void;
    function call(name:String, args:Array<Dynamic>):Dynamic;
}

/** A plain object made by a script ({a: 1}) or by the simulator. */
class DynObj implements IObj {
    public var fields = new Map<String, Dynamic>();
    public function new() {}
    public function get(name:String):Dynamic return fields.get(name);
    public function set(name:String, v:Dynamic):Void fields.set(name, v);
    public function call(name:String, args:Array<Dynamic>):Dynamic {
        var f = fields.get(name);
        if (Std.isOfType(f, Closure)) return (f : Closure).run(args);
        return null;
    }
}

/** What a script sees around it: its globals (vars, rank, owner, Skill.X…) and the game functions it calls. */
interface Host {
    function global(name:String):Dynamic;
    function callGlobal(name:String, args:Array<Dynamic>):Dynamic;
    function missing(what:String):Void;
}

/** A script function with the scope it was made in. */
class Closure {
    var interp:Interp;
    var args:Array<String>;
    var body:Expr;
    var scope:Array<Map<String, Dynamic>>;

    public function new(interp:Interp, args:Array<String>, body:Expr, scope:Array<Map<String, Dynamic>>) {
        this.interp = interp;
        this.args = args;
        this.body = body;
        this.scope = scope;
    }

    public function run(values:Array<Dynamic>):Dynamic return interp.invoke(args, body, scope, values);
}

private enum Flow {
    FReturn(v:Dynamic);
    FBreak;
    FContinue;
}

/**
 * Runs a parsed script. Script variables live in the script's own top scope (kept between calls, like
 * the game's script instance); identifiers it does not define come from the host (the simulation).
 */
class Interp {
    public var script:Script;
    public var host:Host;
    var top = new Map<String, Dynamic>();
    public var steps = 0;

    public function new(script:Script, host:Host) {
        this.script = script;
        this.host = host;
        for (name => f in script.functions) switch (f) {
            case EFunction(a, b, _): top.set(name, new Closure(this, a, b, [top]));
            default:
        }
        for (e in script.top) try exec(e, [top]) catch (_:Dynamic) {}
    }

    public function has(fn:String):Bool return script.functions.exists(fn);

    /** Calls a function of the script (a handler: onInflictDamage, onStep…); null when it has none. */
    public function callFn(fn:String, args:Array<Dynamic>):Dynamic {
        var f = top.get(fn);
        if (f == null || !Std.isOfType(f, Closure)) return null;
        // each handler call has its own budget of steps
        var saved = steps;
        steps = 0;
        try {
            var r = (f : Closure).run(args);
            steps = saved;
            return r;
        } catch (e:Dynamic) {
            steps = saved;
            throw e;
        }
    }

    public function invoke(names:Array<String>, body:Expr, scope:Array<Map<String, Dynamic>>, values:Array<Dynamic>):Dynamic {
        var local = new Map<String, Dynamic>();
        for (i in 0...names.length) local.set(names[i], i < values.length ? values[i] : null);
        var s = scope.copy();
        s.push(local);
        try {
            exec(body, s);
        } catch (f:Flow) {
            switch (f) {
                case FReturn(v): return v;
                default:
            }
        }
        return null;
    }

    function lookup(name:String, scope:Array<Map<String, Dynamic>>):Dynamic {
        var i = scope.length - 1;
        while (i >= 0) {
            if (scope[i].exists(name)) return scope[i].get(name);
            i--;
        }
        return host.global(name);
    }

    function assignVar(name:String, v:Dynamic, scope:Array<Map<String, Dynamic>>):Void {
        var i = scope.length - 1;
        while (i >= 0) {
            if (scope[i].exists(name)) { scope[i].set(name, v); return; }
            i--;
        }
        scope[0].set(name, v);
    }

    static function truthy(v:Dynamic):Bool {
        if (v == null) return false;
        if (Std.isOfType(v, Bool)) return v;
        if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float) != 0;
        return true;
    }

    static function num(v:Dynamic):Float {
        if (v == null) return 0;
        if (Std.isOfType(v, Bool)) return v ? 1 : 0;
        if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
        return 0;
    }

    function exec(e:Expr, scope:Array<Map<String, Dynamic>>):Dynamic {
        steps++;
        if (steps > 200000) throw "script ran too long";
        switch (e) {
            case EBlock(list):
                var s = scope.copy();
                s.push(new Map());
                var v:Dynamic = null;
                for (x in list) v = exec(x, s);
                return v;
            case EVar(names, inits):
                var cur = scope[scope.length - 1];
                for (i in 0...names.length) cur.set(names[i], inits[i] == null ? null : exec(inits[i], scope));
                return null;
            case EIf(c, a, b):
                if (truthy(exec(c, scope))) return exec(a, scope);
                return b == null ? null : exec(b, scope);
            case EWhile(c, body):
                var guard = 0;
                while (truthy(exec(c, scope)) && guard++ < 10000) {
                    try exec(body, scope) catch (f:Flow) {
                        switch (f) {
                            case FBreak: break;
                            case FContinue: continue;
                            default: throw f;
                        }
                    }
                }
                return null;
            case EFor(v, it, body):
                var list:Array<Dynamic> = iterate(it, scope);
                var s = scope.copy();
                var local = new Map<String, Dynamic>();
                s.push(local);
                for (x in list) {
                    local.set(v, x);
                    try exec(body, s) catch (f:Flow) {
                        switch (f) {
                            case FBreak: break;
                            case FContinue: continue;
                            default: throw f;
                        }
                    }
                }
                return null;
            case EReturn(x):
                throw FReturn(x == null ? null : exec(x, scope));
            case EBreak: throw FBreak;
            case EContinue: throw FContinue;
            case EFunction(args, body, name):
                var c = new Closure(this, args, body, scope.copy());
                if (name != "") scope[scope.length - 1].set(name, c);
                return c;
            case ETry(x, v, c):
                try return exec(x, scope) catch (f:Flow) throw f catch (err:Dynamic) {
                    var s = scope.copy();
                    var m = new Map<String, Dynamic>();
                    m.set(v, err);
                    s.push(m);
                    return exec(c, s);
                }
            default:
                return eval(e, scope);
        }
    }

    function iterate(it:Expr, scope:Array<Map<String, Dynamic>>):Array<Dynamic> {
        switch (it) {
            case EBinop("...", a, b):
                var from = Std.int(num(eval(a, scope))), to = Std.int(num(eval(b, scope)));
                return [for (i in from...to) i];
            default:
        }
        var v:Dynamic = eval(it, scope);
        if (v == null) return [];
        if (Std.isOfType(v, Array)) return (v : Array<Dynamic>).copy();
        if (Std.isOfType(v, IObj)) {
            var a:Dynamic = (v : IObj).get("__list");
            if (a != null) return (a : Array<Dynamic>).copy();
        }
        return [];
    }

    public function eval(e:Expr, scope:Array<Map<String, Dynamic>>):Dynamic {
        switch (e) {
            case EConst(v): return v;
            case EIdent(name): return lookup(name, scope);
            case EField(x, name, safe):
                var o:Dynamic = eval(x, scope);
                return field(o, name);
            case ECall(f, args):
                return call(f, [for (a in args) eval(a, scope)], scope);
            case EAssign(op, target, value):
                var v:Dynamic = eval(value, scope);
                if (op != "=") v = binop(op.substr(0, op.length - 1), eval(target, scope), v);
                assign(target, v, scope);
                return v;
            case EBinop(op, a, b):
                if (op == "&&") return truthy(eval(a, scope)) && truthy(eval(b, scope));
                if (op == "||") return truthy(eval(a, scope)) || truthy(eval(b, scope));
                if (op == "??") { var x:Dynamic = eval(a, scope); return x != null ? x : eval(b, scope); }
                return binop(op, eval(a, scope), eval(b, scope));
            case EUnop(op, prefix, x):
                switch (op) {
                    case "!": return !truthy(eval(x, scope));
                    case "-": return -num(eval(x, scope));
                    case "~": return ~Std.int(num(eval(x, scope)));
                    default:
                        var old = num(eval(x, scope));
                        var v = op == "++" ? old + 1 : old - 1;
                        assign(x, v, scope);
                        return prefix ? v : old;
                }
            case ETernary(c, a, b): return truthy(eval(c, scope)) ? eval(a, scope) : eval(b, scope);
            case EIndex(x, i):
                var o:Dynamic = eval(x, scope);
                var k:Dynamic = eval(i, scope);
                if (Std.isOfType(o, Array)) { var a:Array<Dynamic> = o; var n = Std.int(num(k)); return n >= 0 && n < a.length ? a[n] : null; }
                if (Std.isOfType(o, IObj)) return (o : IObj).get(Std.string(k));
                return null;
            case EArrayDecl(list):
                var out:Array<Dynamic> = [];
                for (x in list) switch (x) {
                    case EFor(v, it, body):
                        for (y in iterate(it, scope)) {
                            var s = scope.copy();
                            var m = new Map<String, Dynamic>();
                            m.set(v, y);
                            s.push(m);
                            out.push(exec(body, s));
                        }
                    default: out.push(eval(x, scope));
                }
                return out;
            case EObject(fields):
                var o = new DynObj();
                for (f in fields) o.set(f.name, eval(f.e, scope));
                return o;
            case ESwitch(x, cases, def):
                var v:Dynamic = eval(x, scope);
                for (c in cases) for (val in c.values) if (equals(v, eval(val, scope))) return exec(c.body, scope);
                return def == null ? null : exec(def, scope);
            case ENew(type, args):
                if (type == "Array" || type.indexOf("Map") >= 0) return type == "Array" ? [] : new DynObj();
                host.missing("new " + type);
                return new DynObj();
            default:
                return exec(e, scope);
        }
    }

    static function equals(a:Dynamic, b:Dynamic):Bool {
        if (a == null || b == null) return a == b;
        if ((Std.isOfType(a, Float) || Std.isOfType(a, Int)) && (Std.isOfType(b, Float) || Std.isOfType(b, Int))) return (a : Float) == (b : Float);
        return a == b;
    }

    function binop(op:String, a:Dynamic, b:Dynamic):Dynamic {
        switch (op) {
            case "+":
                if (Std.isOfType(a, String) || Std.isOfType(b, String)) return Std.string(a) + Std.string(b);
                return num(a) + num(b);
            case "-": return num(a) - num(b);
            case "*": return num(a) * num(b);
            case "/": return num(a) / num(b);
            case "%": return num(a) % num(b);
            case "==": return equals(a, b);
            case "!=": return !equals(a, b);
            case "<": return num(a) < num(b);
            case ">": return num(a) > num(b);
            case "<=": return num(a) <= num(b);
            case ">=": return num(a) >= num(b);
            case "&": return Std.int(num(a)) & Std.int(num(b));
            case "|": return Std.int(num(a)) | Std.int(num(b));
            case "^": return Std.int(num(a)) ^ Std.int(num(b));
            case "<<": return Std.int(num(a)) << Std.int(num(b));
            case ">>": return Std.int(num(a)) >> Std.int(num(b));
            default:
                host.missing("operator " + op);
                return null;
        }
    }

    function field(o:Dynamic, name:String):Dynamic {
        if (o == null) return null;
        if (Std.isOfType(o, IObj)) return (o : IObj).get(name);
        if (Std.isOfType(o, Array)) {
            var a:Array<Dynamic> = o;
            if (name == "length") return a.length;
            return null;
        }
        if (Std.isOfType(o, String)) {
            if (name == "length") return (o : String).length;
            return null;
        }
        return null;
    }

    function assign(target:Expr, v:Dynamic, scope:Array<Map<String, Dynamic>>):Void {
        switch (target) {
            case EIdent(name): assignVar(name, v, scope);
            case EField(x, name, _):
                var o:Dynamic = eval(x, scope);
                if (Std.isOfType(o, IObj)) (o : IObj).set(name, v);
            case EIndex(x, i):
                var o:Dynamic = eval(x, scope);
                var k:Dynamic = eval(i, scope);
                if (Std.isOfType(o, Array)) (o : Array<Dynamic>)[Std.int(num(k))] = v;
                else if (Std.isOfType(o, IObj)) (o : IObj).set(Std.string(k), v);
            default:
        }
    }

    function call(f:Expr, args:Array<Dynamic>, scope:Array<Map<String, Dynamic>>):Dynamic {
        switch (f) {
            case EField(x, name, safe):
                var o:Dynamic = eval(x, scope);
                if (o == null) return null;
                if (Std.isOfType(o, IObj)) return (o : IObj).call(name, args);
                if (Std.isOfType(o, Array)) return arrayCall(o, name, args);
                if (Std.isOfType(o, Closure)) return null;
                host.missing("method " + name + " of " + Std.string(o).substr(0, 20));
                return null;
            case EIdent(name):
                var local:Dynamic = null;
                var i = scope.length - 1;
                while (i >= 0) {
                    if (scope[i].exists(name)) { local = scope[i].get(name); break; }
                    i--;
                }
                if (local != null && Std.isOfType(local, Closure)) return (local : Closure).run(args);
                return host.callGlobal(name, args);
            default:
                var v:Dynamic = eval(f, scope);
                if (Std.isOfType(v, Closure)) return (v : Closure).run(args);
                return null;
        }
    }

    function arrayCall(a:Array<Dynamic>, name:String, args:Array<Dynamic>):Dynamic {
        switch (name) {
            case "push": a.push(args[0]); return a.length;
            case "pop": return a.pop();
            case "shift": return a.shift();
            case "remove": return a.remove(args[0]);
            case "indexOf": return a.indexOf(args[0]);
            case "contains": return a.indexOf(args[0]) >= 0;
            case "copy": return a.copy();
            case "filter":
                var f:Closure = args[0];
                return [for (x in a) if (truthy(f.run([x]))) x];
            case "map":
                var f:Closure = args[0];
                return [for (x in a) f.run([x])];
            case "length": return a.length;
            default:
                host.missing("array " + name);
                return null;
        }
    }
}
