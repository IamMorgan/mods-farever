package codexloot;

/**
 * Item names in English AND Russian (besides the client's own language), so the chest search finds an item whichever
 * language it is typed in. The game keeps only the client's language in its data, so the other two come from the
 * game's own files: English from the base data (data.cdb), Russian from the translation file (lang/export_ru.xml).
 * Read once, on the first search.
 */
class ChestNames {
    static var en:Map<String, String>;
    static var ru:Map<String, String>;
    static var searchable = new Map<String, String>();

    public static function clear():Void searchable = new Map();

    static function resourceText(path:String):String {
        try {
            var res = G.callStatic("hxd.Res", "load", [path]);
            return G.str(G.call("hxd.res.Any", "toText", [res]));
        } catch (_:Dynamic) {}
        return "";
    }

    /** id -> English name, from the base data (data.cdb, sheet "item": texts.name, or the name of texts.inherit). */
    static function readEnglish():Map<String, String> {
        var out = new Map<String, String>();
        try {
            var text = resourceText("data.cdb");
            if (text == "") return out;
            var root:Dynamic = haxe.Json.parse(text);
            var own = new Map<String, String>();
            var parent = new Map<String, String>();
            for (sheet in (root.sheets : Array<Dynamic>)) {
                if (sheet.name != "item") continue;
                for (line in (sheet.lines : Array<Dynamic>)) {
                    var id:String = line.id;
                    var texts:Dynamic = line.texts;
                    if (id == null || texts == null) continue;
                    if (texts.name != null) own.set(id, texts.name);
                    else if (texts.inherit != null) parent.set(id, texts.inherit);
                }
            }
            for (id => name in own) out.set(id, name);
            for (id => from in parent) {
                var p = from;
                for (_ in 0...4) {
                    if (own.exists(p)) { out.set(id, own.get(p)); break; }
                    if (!parent.exists(p)) break;
                    p = parent.get(p);
                }
            }
        } catch (_:Dynamic) {}
        return out;
    }

    /** id -> Russian name, from lang/export_ru.xml (sheet "item", texts.name). */
    static function readRussian():Map<String, String> {
        var out = new Map<String, String>();
        try {
            var text = resourceText("lang/export_ru.xml");
            var start = text.indexOf('<sheet name="item">');
            if (start < 0) return out;
            var end = text.indexOf("</sheet>", start);
            if (end < 0) return out;
            var sheet = Xml.parse(text.substring(start, end + "</sheet>".length)).firstElement();
            for (item in sheet.elements()) {
                for (n in item.elementsNamed("texts.name")) {
                    var c = n.firstChild();
                    if (c != null && c.nodeValue != null) out.set(item.nodeName, c.nodeValue);
                }
            }
        } catch (_:Dynamic) {}
        return out;
    }

    static function load():Void {
        if (en != null) return;
        en = readEnglish();
        ru = readRussian();
    }

    /** The lower-case names of the item in the client's language, English and Russian, one per line. */
    public static function of(item:Dynamic):String {
        var id = G.str(G.field(item, "id"));
        var cached = searchable.get(id);
        if (cached != null) return cached;
        load();
        var names:Array<String> = [];
        var client = Sheets.name("item", id);
        try {
            var n = G.str(G.callStatic("HItem", "getName", [item]));
            if (n != "") client = n;
        } catch (_:Dynamic) {}
        for (n in [client, en.get(id), ru.get(id)])
            if (n != null && n != "" && names.indexOf(n.toLowerCase()) < 0) names.push(n.toLowerCase());
        var text = names.join("\n");
        searchable.set(id, text);
        return text;
    }

    /** True when `text` (any case) is part of one of the item's names. */
    public static function matches(item:Dynamic, text:String):Bool {
        var s = StringTools.trim(text).toLowerCase();
        return s == "" || of(item).indexOf(s) >= 0;
    }
}
