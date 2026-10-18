package buildcalc.sim;

/** The syntax tree of a skill script (the game writes them in hscript, a subset of Haxe). */
enum Expr {
    EConst(v:Dynamic);
    EIdent(name:String);
    EVar(names:Array<String>, inits:Array<Expr>);
    EField(e:Expr, name:String, safe:Bool);
    ECall(e:Expr, args:Array<Expr>);
    EBinop(op:String, a:Expr, b:Expr);
    EAssign(op:String, target:Expr, value:Expr);
    EUnop(op:String, prefix:Bool, e:Expr);
    EBlock(list:Array<Expr>);
    EIf(cond:Expr, then:Expr, otherwise:Expr);
    EWhile(cond:Expr, body:Expr);
    EFor(v:String, iter:Expr, body:Expr);
    EFunction(args:Array<String>, body:Expr, name:String);
    EReturn(e:Expr);
    EBreak;
    EContinue;
    EIndex(e:Expr, index:Expr);
    EArrayDecl(list:Array<Expr>);
    ETernary(cond:Expr, a:Expr, b:Expr);
    ESwitch(e:Expr, cases:Array<{values:Array<Expr>, body:Expr}>, def:Expr);
    ETry(e:Expr, v:String, c:Expr);
    ENew(type:String, args:Array<Expr>);
    EObject(fields:Array<{name:String, e:Expr}>);
}

typedef Token = {t:String, v:String, pos:Int};

/** A parsed script: its functions by name and its top-level statements (variables). */
class Script {
    public var functions = new Map<String, Expr>();
    public var top:Array<Expr> = [];

    public function new() {}

    // ---------------------------------------------------------------- lexer

    static var OPS = ["...", "<<=", ">>=", "?.", "??", "->", "=>", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=",
        "++", "--", "<<", ">>", "+", "-", "*", "/", "%", "=", "<", ">", "!", ".", ",", ";", ":", "(", ")", "{", "}", "[", "]", "?", "&", "|", "^", "~", "@"];

    public static function lex(s:String):Array<Token> {
        var out:Array<Token> = [];
        var i = 0, n = s.length;
        while (i < n) {
            var c = s.charCodeAt(i);
            if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code) { i++; continue; }
            if (c == "/".code && i + 1 < n && s.charCodeAt(i + 1) == "/".code) {
                while (i < n && s.charCodeAt(i) != "\n".code) i++;
                continue;
            }
            if (c == "/".code && i + 1 < n && s.charCodeAt(i + 1) == "*".code) {
                var e = s.indexOf("*/", i + 2);
                i = e < 0 ? n : e + 2;
                continue;
            }
            var start = i;
            if (chIdStart(c)) {
                while (i < n && chId(s.charCodeAt(i))) i++;
                out.push({t: "id", v: s.substring(start, i), pos: start});
                continue;
            }
            if (isDigit(c) || (c == ".".code && i + 1 < n && isDigit(s.charCodeAt(i + 1)) && !(i + 2 < n && s.charAt(i + 1) == "."))) {
                if (c == "0".code && i + 1 < n && (s.charAt(i + 1) == "x" || s.charAt(i + 1) == "X")) {
                    i += 2;
                    while (i < n && isHex(s.charCodeAt(i))) i++;
                    out.push({t: "num", v: s.substring(start, i), pos: start});
                    continue;
                }
                while (i < n && isDigit(s.charCodeAt(i))) i++;
                // a dot followed by a digit (not "..." of an interval)
                if (i < n && s.charAt(i) == "." && !(i + 1 < n && s.charAt(i + 1) == ".")) {
                    i++;
                    while (i < n && isDigit(s.charCodeAt(i))) i++;
                }
                if (i < n && (s.charAt(i) == "e" || s.charAt(i) == "E")) {
                    i++;
                    if (i < n && (s.charAt(i) == "-" || s.charAt(i) == "+")) i++;
                    while (i < n && isDigit(s.charCodeAt(i))) i++;
                }
                out.push({t: "num", v: s.substring(start, i), pos: start});
                continue;
            }
            if (c == "'".code || c == '"'.code) {
                var q = c;
                i++;
                var buf = new StringBuf();
                while (i < n && s.charCodeAt(i) != q) {
                    if (s.charAt(i) == "\\" && i + 1 < n) {
                        var e = s.charAt(i + 1);
                        buf.add(e == "n" ? "\n" : (e == "t" ? "\t" : e));
                        i += 2;
                        continue;
                    }
                    buf.addChar(s.charCodeAt(i));
                    i++;
                }
                i++;
                out.push({t: "str", v: buf.toString(), pos: start});
                continue;
            }
            var found = false;
            for (op in OPS) if (s.substr(i, op.length) == op) {
                out.push({t: "op", v: op, pos: start});
                i += op.length;
                found = true;
                break;
            }
            if (!found) throw "unexpected character '" + s.charAt(i) + "' at " + i;
        }
        out.push({t: "eof", v: "", pos: n});
        return out;
    }

    static inline function chIdStart(c:Int):Bool return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == "$".code;
    static inline function chId(c:Int):Bool return chIdStart(c) || isDigit(c);
    static inline function isDigit(c:Int):Bool return c >= "0".code && c <= "9".code;
    static inline function isHex(c:Int):Bool return isDigit(c) || (c >= "a".code && c <= "f".code) || (c >= "A".code && c <= "F".code);

    // ---------------------------------------------------------------- parser

    var toks:Array<Token>;
    var p = 0;

    public static function parse(source:String):Script {
        var s = new Script();
        s.toks = lex(source);
        s.p = 0;
        while (!s.isEof()) {
            if (s.isId("function")) {
                s.next();
                var name = s.ident();
                var f = s.functionRest(name);
                s.functions.set(name, f);
            } else {
                var e = s.statement();
                if (e != null) s.top.push(e);
            }
        }
        return s;
    }

    inline function peek(k = 0):Token return toks[Std.int(Math.min(p + k, toks.length - 1))];
    inline function next():Token return toks[p++];
    inline function isEof():Bool return peek().t == "eof";
    function isOp(v:String, k = 0):Bool { var t = peek(k); return t.t == "op" && t.v == v; }
    function isId(v:String):Bool { var t = peek(); return t.t == "id" && t.v == v; }
    function err(msg:String):Dynamic throw msg + " at token '" + peek().v + "' (" + peek().pos + ")";

    function expect(v:String):Void {
        if (!isOp(v)) err("expected '" + v + "'");
        p++;
    }

    function ident():String {
        var t = next();
        if (t.t != "id") { p--; err("expected an identifier"); }
        return t.v;
    }

    function functionRest(name:String):Expr {
        expect("(");
        var args = [];
        while (!isOp(")")) {
            if (isOp("?")) next();
            args.push(ident());
            if (isOp(":")) { next(); typeHint(); }
            if (isOp("=")) { next(); expr(); }
            if (isOp(",")) next();
        }
        expect(")");
        if (isOp(":")) { next(); typeHint(); }
        var body = isOp("{") ? block() : (function() { var e = expr(); return EReturn(e); })();
        return EFunction(args, body, name);
    }

    /** Skips a type annotation (`Int`, `Array<Float>`, `{a:Int}`). */
    function typeHint():Void {
        if (isOp("{")) { skipBalanced("{", "}"); return; }
        ident();
        while (isOp(".")) { next(); ident(); }
        if (isOp("<")) {
            var depth = 0;
            do {
                if (isOp("<")) depth++;
                if (isOp(">")) depth--;
                next();
            } while (depth > 0 && !isEof());
        }
    }

    function skipBalanced(a:String, b:String):Void {
        var depth = 0;
        do {
            if (isOp(a)) depth++;
            if (isOp(b)) depth--;
            next();
        } while (depth > 0 && !isEof());
    }

    function block():Expr {
        expect("{");
        var list = [];
        while (!isOp("}")) {
            if (isEof()) err("unterminated block");
            var e = statement();
            if (e != null) list.push(e);
        }
        expect("}");
        return EBlock(list);
    }

    function statement():Expr {
        if (isOp(";")) { next(); return null; }
        if (isOp("{")) {
            // a block, unless it is an object literal used as a statement (rare)
            return block();
        }
        var t = peek();
        if (t.t == "id") switch (t.v) {
            case "var", "final":
                next();
                var names = [], inits = [];
                while (true) {
                    names.push(ident());
                    if (isOp(":")) { next(); typeHint(); }
                    inits.push(isOp("=") ? { next(); expr(); } : null);
                    if (isOp(",")) { next(); continue; }
                    break;
                }
                semicolon();
                return EVar(names, inits);
            case "if":
                next();
                expect("(");
                var c = expr();
                expect(")");
                var a = statementOrExpr();
                var save = p;
                if (isOp(";")) next();
                if (isId("else")) {
                    next();
                    return EIf(c, a, statementOrExpr());
                }
                p = save;
                return EIf(c, a, null);
            case "while":
                next();
                expect("(");
                var c = expr();
                expect(")");
                return EWhile(c, statementOrExpr());
            case "do":
                next();
                var body = statementOrExpr();
                if (!isId("while")) err("expected while");
                next();
                expect("(");
                var c = expr();
                expect(")");
                semicolon();
                return EBlock([body, EWhile(c, body)]);
            case "for":
                next();
                expect("(");
                var v = ident();
                if (!isId("in")) err("expected in");
                next();
                var it = expr();
                expect(")");
                return EFor(v, it, statementOrExpr());
            case "return":
                next();
                if (isOp(";") || isOp("}")) { semicolon(); return EReturn(null); }
                var e = expr();
                semicolon();
                return EReturn(e);
            case "break":
                next();
                semicolon();
                return EBreak;
            case "continue":
                next();
                semicolon();
                return EContinue;
            case "function":
                next();
                var name = peek().t == "id" ? ident() : "";
                var f = functionRest(name);
                return name != "" ? EVar([name], [f]) : f;
            case "try":
                next();
                var e = statementOrExpr();
                if (!isId("catch")) return e;
                next();
                expect("(");
                var v = ident();
                if (isOp(":")) { next(); typeHint(); }
                expect(")");
                return ETry(e, v, statementOrExpr());
            default:
        }
        var e = expr();
        semicolon();
        return e;
    }

    function statementOrExpr():Expr {
        var e = statement();
        return e == null ? EBlock([]) : e;
    }

    function semicolon():Void if (isOp(";")) next();

    // precedence, lowest first
    static var LEVELS:Array<Array<String>> = [["??"], ["||"], ["&&"], ["==", "!=", "<", ">", "<=", ">="], ["..."], ["|"], ["^"], ["&"], ["<<", ">>"], ["+", "-"], ["*", "/", "%"]];

    public function expr():Expr {
        var e = ternary();
        if (peek().t == "op") switch (peek().v) {
            case "=", "+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "<<=", ">>=":
                var op = next().v;
                return EAssign(op, e, expr());
            default:
        }
        return e;
    }

    function ternary():Expr {
        var c = binary(0);
        if (isOp("?")) {
            next();
            var a = expr();
            expect(":");
            var b = expr();
            return ETernary(c, a, b);
        }
        return c;
    }

    function binary(level:Int):Expr {
        if (level >= LEVELS.length) return unary();
        var e = binary(level + 1);
        while (peek().t == "op" && LEVELS[level].indexOf(peek().v) >= 0) {
            var op = next().v;
            e = EBinop(op, e, binary(level + 1));
        }
        return e;
    }

    function unary():Expr {
        if (peek().t == "op") switch (peek().v) {
            case "!", "-", "~":
                var op = next().v;
                return EUnop(op, true, unary());
            case "++", "--":
                var op = next().v;
                return EUnop(op, true, unary());
            default:
        }
        if (isId("cast")) {
            next();
            if (isOp("(")) {
                next();
                var e = expr();
                if (isOp(",")) { next(); typeHint(); }
                expect(")");
                return postfix(e);
            }
            return unary();
        }
        return postfix(primary());
    }

    function postfix(e:Expr):Expr {
        while (true) {
            if (isOp(".")) { next(); e = EField(e, ident(), false); continue; }
            if (isOp("?.")) { next(); e = EField(e, ident(), true); continue; }
            if (isOp("(")) { e = ECall(e, args()); continue; }
            if (isOp("[")) { next(); var i = expr(); expect("]"); e = EIndex(e, i); continue; }
            if (isOp("++") || isOp("--")) { e = EUnop(next().v, false, e); continue; }
            break;
        }
        return e;
    }

    function args():Array<Expr> {
        expect("(");
        var list = [];
        while (!isOp(")")) {
            list.push(expr());
            if (isOp(",")) next();
        }
        expect(")");
        return list;
    }

    /** Does a lambda `(a, b) -> …` start here? */
    function lambdaAhead():Bool {
        if (!isOp("(")) return false;
        var k = 1, depth = 1;
        while (depth > 0) {
            var t = peek(k);
            if (t.t == "eof") return false;
            if (t.t == "op" && t.v == "(") depth++;
            if (t.t == "op" && t.v == ")") depth--;
            k++;
        }
        var t = peek(k);
        return t.t == "op" && t.v == "->";
    }

    function primary():Expr {
        var t = peek();
        switch (t.t) {
            case "num":
                next();
                return EConst(Std.parseFloat(t.v.indexOf("0x") == 0 ? Std.string(Std.parseInt(t.v)) : t.v));
            case "str":
                next();
                return EConst(t.v);
            case "id":
                switch (t.v) {
                    case "true": next(); return EConst(true);
                    case "false": next(); return EConst(false);
                    case "null": next(); return EConst(null);
                    case "function":
                        next();
                        var name = peek().t == "id" ? ident() : "";
                        return functionRest(name);
                    case "new":
                        next();
                        var type = ident();
                        while (isOp(".")) { next(); type += "." + ident(); }
                        if (isOp("<")) skipBalanced("<", ">");
                        return ENew(type, args());
                    case "switch":
                        next();
                        var e = isOp("(") ? { next(); var x = expr(); expect(")"); x; } : expr();
                        expect("{");
                        var cases = [];
                        var def:Expr = null;
                        while (!isOp("}")) {
                            if (isId("case")) {
                                next();
                                var values = [expr()];
                                while (isOp(",") || isOp("|")) { next(); values.push(expr()); }
                                expect(":");
                                cases.push({values: values, body: caseBody()});
                            } else if (isId("default")) {
                                next();
                                expect(":");
                                def = caseBody();
                            } else err("expected case");
                        }
                        expect("}");
                        return ESwitch(e, cases, def);
                    case "if":
                        next();
                        expect("(");
                        var c = expr();
                        expect(")");
                        var a = expr();
                        if (isId("else")) { next(); return EIf(c, a, expr()); }
                        return EIf(c, a, null);
                    default:
                }
                next();
                if (isOp("->")) {
                    next();
                    return EFunction([t.v], EReturn(expr()), "");
                }
                return EIdent(t.v);
            case "op":
                if (t.v == "(") {
                    if (lambdaAhead()) {
                        next();
                        var names = [];
                        while (!isOp(")")) {
                            names.push(ident());
                            if (isOp(":")) { next(); typeHint(); }
                            if (isOp(",")) next();
                        }
                        expect(")");
                        expect("->");
                        var body = isOp("{") ? block() : EReturn(expr());
                        return EFunction(names, body, "");
                    }
                    next();
                    var e = expr();
                    if (isOp(":")) { next(); typeHint(); }
                    expect(")");
                    return e;
                }
                if (t.v == "[") {
                    next();
                    var list = [];
                    while (!isOp("]")) {
                        if (isId("for")) {
                            // array comprehension: [for (x in it) expr]
                            list.push(statement());
                        } else list.push(expr());
                        if (isOp(",")) next();
                    }
                    expect("]");
                    return EArrayDecl(list);
                }
                if (t.v == "{") {
                    // an object literal { a: 1 } or a block used as a value
                    if (peek(1).t == "id" && peek(2).t == "op" && peek(2).v == ":" || (peek(1).t == "op" && peek(1).v == "}")) {
                        next();
                        var fields = [];
                        while (!isOp("}")) {
                            var name = next().v;
                            expect(":");
                            fields.push({name: name, e: expr()});
                            if (isOp(",")) next();
                        }
                        expect("}");
                        return EObject(fields);
                    }
                    return block();
                }
            default:
        }
        return err("unexpected token");
    }

    function caseBody():Expr {
        var list = [];
        while (!isId("case") && !isId("default") && !isOp("}")) {
            var e = statement();
            if (e != null) list.push(e);
        }
        return EBlock(list);
    }
}
