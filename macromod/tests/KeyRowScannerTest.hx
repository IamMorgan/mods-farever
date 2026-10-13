import macromod.KeyRowScanner;
import macromod.RowFinder;

class N {
    public var kids:Array<N> = [];
    public var up:N;
    public var label:Null<String>;
    public var button = false;
    public var alive = true;
    public function new(?label:String, button = false) { this.label = label; this.button = button; }
    public function add(n:N):N { kids.push(n); n.up = this; return n; }
}

class CountingTree implements SceneTree {
    public var visits = 0;
    public function new() {}
    public function children(n:Dynamic):Array<Dynamic> { visits++; return cast (n : N).kids; }
    public function parent(n:Dynamic):Dynamic return n == null ? null : (n : N).up;
    public function text(n:Dynamic):Null<String> return (n : N).label;
    public function isButton(n:Dynamic):Bool return (n : N).button;
}

class FakeDecorator implements RowDecorator {
    public var log:Array<String> = [];
    public var failFor:Array<String> = [];
    public function new() {}
    public function decorate(key:String, button:Dynamic):Dynamic {
        if (failFor.indexOf(key) >= 0) { log.push("fail " + key); return null; }
        log.push(key);
        var x = new N();
        (button : N).up.add(x);
        return x;
    }
    public function isAlive(added:Dynamic):Bool return (added : N).alive;
}

class KeyRowScannerTest {
    static var failures = 0;
    static function check(name:String, ok:Bool, ?info:String):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name + (!ok && info != null ? ": " + info : ""));
    }

    static function window(rows:Array<String>, filler:Int):{root:N, buttons:Map<String, N>} {
        var root = new N();
        for (i in 0...filler) root.add(new N("noise" + i)).add(new N("deeper" + i));
        var list = root.add(new N());
        var buttons = new Map<String, N>();
        for (label in rows) {
            var r = list.add(new N());
            r.add(new N(label));
            r.add(new N());
            var cell = r.add(new N());
            var b = cell.add(new N(null, true));
            buttons.set(label, b);
        }
        return {root: root, buttons: buttons};
    }

    // run frames until the scanner has had `seconds` of time
    static function run(s:KeyRowScanner, root:N, from:Float, seconds:Float):Float {
        var t = from;
        while (t < from + seconds) { s.tick(root, t); t += 0.016; }
        return t;
    }

    static function main():Void {
        var labels = ["M1 Activation Key" => "m1_hotkey", "M1 Step 1 Key" => "m1_s1_key", "M2 Step 3 Key" => "m2_s3_key"];
        var tree = new CountingTree();
        var deco = new FakeDecorator();
        var scanner = new KeyRowScanner(tree, deco, labels);
        var w = window(["M1 Activation Key", "Other row", "M1 Step 1 Key", "M2 Step 3 Key"], 1500);

        // 1. frame budget: one tick never inspects more than BUDGET nodes
        scanner.tick(w.root, 0.0);
        check("one frame inspects at most " + KeyRowScanner.BUDGET + " nodes", tree.visits <= KeyRowScanner.BUDGET, Std.string(tree.visits));

        // 2. all rows found within a couple of seconds, each decorated exactly once
        var t = run(scanner, w.root, 0.016, 3.0);
        check("all three key rows decorated", deco.log.length == 3, deco.log.join(","));
        check("the right keys", deco.log.indexOf("m1_hotkey") >= 0 && deco.log.indexOf("m1_s1_key") >= 0 && deco.log.indexOf("m2_s3_key") >= 0);
        check("hasLive while the window is open", scanner.hasLive());

        // 3. more passes do not decorate again
        t = run(scanner, w.root, t, 3.0);
        check("no duplicates on later passes", deco.log.length == 3, deco.log.join(","));

        // 4. window closed: decorations die, scanning can stop
        for (b in w.buttons) for (k in b.up.kids) k.alive = false;
        check("no live decorations after closing", !scanner.hasLive());

        // 5. reopened (new objects): decorated again
        var w2 = window(["M1 Activation Key", "M1 Step 1 Key", "M2 Step 3 Key"], 50);
        run(scanner, w2.root, t, 2.0);
        check("rebuilt page is decorated again", deco.log.length == 6, deco.log.join(","));

        // 6. a row that fails is not retried forever
        var deco2 = new FakeDecorator();
        deco2.failFor = ["m1_hotkey"];
        var s2 = new KeyRowScanner(new CountingTree(), deco2, labels);
        var w3 = window(["M1 Activation Key", "M1 Step 1 Key"], 10);
        run(s2, w3.root, 0.0, 3.0);
        check("failed row tried once, others decorated", deco2.log.join(",") == "fail m1_hotkey,m1_s1_key", deco2.log.join(","));

        // 7. nothing found in a scene without the settings window
        var deco3 = new FakeDecorator();
        var s3 = new KeyRowScanner(new CountingTree(), deco3, labels);
        run(s3, window([], 300).root, 0.0, 2.0);
        check("no window, nothing added", deco3.log.length == 0 && !s3.hasLive());

        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
