import macromod.RowFinder;

class Node {
    public var kids:Array<Node> = [];
    public var up:Node;
    public var label:Null<String>;
    public var button = false;
    public var caption = "";
    public function new(?label:String, button = false) { this.label = label; this.button = button; }
    public function add(n:Node):Node { kids.push(n); n.up = this; return n; }
}

class FakeTree implements SceneTree {
    public function new() {}
    public function children(n:Dynamic):Array<Dynamic> return cast (n : Node).kids;
    public function parent(n:Dynamic):Dynamic return n == null ? null : (n : Node).up;
    public function text(n:Dynamic):Null<String> return (n : Node).label;
    public function isButton(n:Dynamic):Bool return (n : Node).button;
}

class RowFinderTest {
    static var failures = 0;
    static function check(name:String, ok:Bool):Void {
        if (!ok) failures++;
        Sys.println((ok ? "ok   " : "FAIL ") + name);
    }

    // row = [label][line][button], like the settings window; label may sit one level deeper
    static function row(list:Node, label:String, nested:Bool):Node {
        var r = list.add(new Node());
        var holder = nested ? r.add(new Node()) : r;
        holder.add(new Node(label));
        r.add(new Node());
        var b = r.add(new Node(null, true));
        b.caption = "Key 5";
        return b;
    }

    static function main():Void {
        var window = new Node();
        var list = window.add(new Node());
        var b1 = row(list, "M1 Step 3 Key", false);
        var b2 = row(list, "M2 Step 3 Key", true);
        var x2 = row(list, "Clear M2 Step 3 Key", false);
        var tree = new FakeTree();
        check("finds the button of the right row", RowFinder.findButton(window, "M1 Step 3 Key", tree) == b1);
        check("finds it when the label is nested one level deeper", RowFinder.findButton(window, "M2 Step 3 Key", tree) == b2);
        check("the X row is a different row", RowFinder.findButton(window, "Clear M2 Step 3 Key", tree) == x2);
        check("unknown label gives nothing", RowFinder.findButton(window, "M9 Step 1 Key", tree) == null);
        // label whose smallest container holds several buttons (all rows in one flow): refuse instead of guessing
        var flat = new Node();
        flat.add(new Node("A"));
        flat.add(new Node(null, true));
        flat.add(new Node(null, true));
        check("ambiguous container is refused", RowFinder.findButton(flat, "A", tree) == null);
        // other widgets with the same text do not confuse the search of an exact label
        var w2 = new Node(); w2.add(new Node("M1 Step 3 Key extra"));
        check("only exact text matches", RowFinder.findLabel(w2, "M1 Step 3 Key", tree) == null);

        // The labels used in code must equal the ones in configFormats.json. Only the 3
        // activation keys are real keybindings now - macro steps are skill-id text fields,
        // not keys, so there's no "X" row-scanning to do for them any more.
        var cfg:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent("configFormats.json")).configs;
        var bad = 0, keys = 0;
        for (item in cfg) if (item.type == "keybinding") {
            keys++;
            var parts:Array<String> = (item.key : String).split("_");
            var n = parts[0].substr(1);
            var expected = "M" + n + " Activation Key";
            if (item.label != expected) bad++;
        }
        check("3 activation-key labels match the code", keys == 3 && bad == 0);
        Sys.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
