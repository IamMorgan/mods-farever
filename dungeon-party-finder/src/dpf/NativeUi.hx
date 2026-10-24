package dpf;

import dpf.GameAccess as G;

/**
 * Helpers for building controls out of the game's own UI parts (domkit nodes: "button", "text", "flow"), the way the game's
 * own windows and the Dungeon Button mod do. Positions and sizes are set both on the heaps object and in the domkit style,
 * or the game's stylesheet puts them back on the next layout.
 */
class NativeUi {
    public static function node(component:String, parent:Dynamic, args:Array<Dynamic>, id:String, ?layout:String):Dynamic {
        var attributes:Dynamic = {id: id};
        if (layout != null) Reflect.setField(attributes, "layout", layout);
        var result = G.staticCall("domkit.Properties", "createNew", [component, parent, args, attributes]);
        if (result == null) throw "Could not create " + component;
        return result;
    }

    /** A line of the game's own text. */
    public static function label(parent:Dynamic, value:String, id = "dpfText"):Dynamic return G.field(node("text", parent, [escape(value)], id), "obj");

    /** One of the game's buttons; `click` runs when it is pressed. */
    public static function button(parent:Dynamic, value:String, id:String, click:Void -> Void):Dynamic {
        var obj = G.field(node("button", parent, [escape(value)], id), "obj");
        G.call("ui.UIElement", "set_onClick", obj, [click]);
        return obj;
    }

    public static function style(object:Dynamic, property:String, value:Dynamic):Void {
        var dom = G.field(object, "dom");
        if (dom != null) G.call("domkit.Properties", "initStyle", dom, [property, value]);
    }

    public static function padding(object:Dynamic, value:Int):Void {
        G.call("h2d.Flow", "set_padding", object, [value]);
        for (side in ["left", "right", "top", "bottom"]) style(object, "padding-" + side, value);
    }

    public static function size(object:Dynamic, w:Int, h:Int = -1):Void {
        G.call("h2d.Flow", "set_minWidth", object, [w]);
        G.call("h2d.Flow", "set_maxWidth", object, [w]);
        if (h >= 0) {
            G.call("h2d.Flow", "set_minHeight", object, [h]);
            G.call("h2d.Flow", "set_maxHeight", object, [h]);
        }
        var dom = G.field(object, "dom");
        if (dom != null) {
            for (property in ["width", "min-width", "max-width"]) G.call("domkit.Properties", "initStyle", dom, [property, w]);
            if (h >= 0) for (property in ["height", "min-height", "max-height"]) G.call("domkit.Properties", "initStyle", dom, [property, h]);
        }
    }

    public static function children(object:Dynamic):Array<Dynamic> {
        var count = G.integer(G.call("h2d.Object", "get_numChildren", object));
        return [for (i in 0...count) G.call("h2d.Object", "getChildAt", object, [i])];
    }

    /** Takes `child` out of its flow's layout: it stays where `position` puts it. */
    public static function absolute(parent:Dynamic, child:Dynamic):Void {
        var p = G.call("h2d.Flow", "getProperties", parent, [child]);
        G.call("h2d.FlowProperties", "set_isAbsolute", p, [true]);
        G.set(p, "horizontalAlign", null);
        G.set(p, "verticalAlign", null);
        G.set(p, "offsetX", 0);
        G.set(p, "offsetY", 0);
        var dom = G.field(child, "dom");
        if (dom != null) {
            G.call("domkit.Properties", "initStyle", dom, ["position", true]);
            for (key in ["halign", "valign"]) G.call("domkit.Properties", "initStyle", dom, [key, null]);
            for (key in ["offset-x", "offset-y"]) G.call("domkit.Properties", "initStyle", dom, [key, 0]);
        }
    }

    /** Puts `child` back into its flow's layout. */
    public static function inFlow(parent:Dynamic, child:Dynamic):Void {
        var p = G.call("h2d.Flow", "getProperties", parent, [child]);
        G.call("h2d.FlowProperties", "set_isAbsolute", p, [false]);
        style(child, "position", false);
    }

    public static function position(obj:Dynamic, x:Float, y:Float):Void G.call("h2d.Object", "setPosition", obj, [x, y]);

    public static function show(obj:Dynamic, visible:Bool):Void {
        if (obj != null) G.call("h2d.Object", "set_visible", obj, [visible]);
    }

    public static function enable(obj:Dynamic, on:Bool):Void {
        if (obj != null) G.call("ui.UIElement", "set_enable", obj, [on]);
    }

    public static function escape(value:String):String {
        if (value == null) return "";
        var text = StringTools.htmlEscape(value);
        return StringTools.replace(StringTools.replace(text, "[", "&#91;"), "$", "&#36;");
    }

    /** Text of a label made by `label`. */
    public static function setText(obj:Dynamic, value:String):Void {
        if (obj != null) G.call("ui.comp.FmtText", "set_text", obj, [escape(value)]);
    }

    /** Text of a button made by `button`. */
    public static function setButtonText(obj:Dynamic, value:String):Void {
        if (obj != null) G.call("ui.comp.Button", "setText", obj, [escape(value)]);
    }
}
