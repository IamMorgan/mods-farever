package dpf;

/**
 * The look of the game's dungeon dialog (rose-beige panel, dark title strip, rivets at the corners) for the mod's windows.
 * Colours are plain RGB; sizes are in "design" pixels, the windows scale them to the screen.
 */
class Style {
    public static inline var LINE = 0x8C6E67;       // outline of the window
    public static inline var HEADER = 0xF4E1DD;     // title strip
    public static inline var BODY = 0xE6CEC8;       // lower part
    public static inline var BAND = 0xCFB8B1;       // description band
    public static inline var CARD = 0xD3BAB2;
    public static inline var CARD_LINE = 0xB79F97;
    public static inline var DARK = 0x4E3A38;       // text on light
    public static inline var DIM = 0x8A726C;
    public static inline var TITLE = 0x5E4642;
    public static inline var BUTTON = 0xB49A92;
    public static inline var BUTTON_HOVER = 0xC6AEA6;
    public static inline var BUTTON_OFF = 0xC4B1AB;
    public static inline var BUTTON_ON = 0x9DAF74;
    public static inline var BUTTON_TEXT = 0xFFF6F2;
    public static inline var BUTTON_SHADOW = 0x6B5750;
    public static inline var DIFF = 0x4A3B34;       // difficulty buttons
    public static inline var DIFF_ON = 0x65544B;
    public static inline var DIFF_LINE = 0x2E231F;
    public static inline var DIFF_RING = 0xF1DAD2;
    public static inline var RIVET = 0xA58D86;
    public static inline var RIVET_LIGHT = 0xD9C4BE;
    public static inline var STRIPE = 0xB26D2E;     // line under the picture
    public static inline var CLOSE = 0xA48C85;
    public static inline var CLOSE_HOVER = 0x7A5F58;
    public static inline var ERROR = 0xA23B33;
    public static inline var OK = 0x4F8A3C;
    public static inline var GOLD = 0xF2C230;
    public static inline var GOLD_LINE = 0x6B4A0B;
    public static inline var ROW = 0xDDC6BF;
    public static inline var ROW_HOVER = 0xEBD8D2;

    /** The window's shape: outline, title strip, body and the four rivets. */
    public static function frame(ui:UiKit, g:Dynamic, w:Float, h:Float, headerH:Float):Void {
        ui.framed(g, 0, 0, w, h, 10, BODY, LINE, 2);
        ui.plate(g, 2, 2, w - 4, headerH, 8, HEADER);
        ui.rect(g, 2, headerH - 8, w - 4, 8, HEADER);
        ui.rect(g, 2, headerH, w - 4, 1.5, LINE, 0.55);
        for (p in [[13.0, 13.0], [w - 13, 13.0], [13.0, h - 13], [w - 13, h - 13]]) {
            ui.circle(g, p[0], p[1], 6.5, RIVET, 1, 12);
            ui.circle(g, p[0] - 1.3, p[1] - 1.3, 3, RIVET_LIGHT, 1, 10);
        }
    }

    /** A cross made of two bars, centred on (cx, cy). */
    public static function cross(ui:UiKit, g:Dynamic, cx:Float, cy:Float, size:Float, color:Int):Void {
        var a = size, t = size * 0.22;
        ui.poly(g, [cx - a, cy - a + t, cx - a + t, cy - a, cx + a, cy + a - t, cx + a - t, cy + a], color);
        ui.poly(g, [cx + a, cy - a + t, cx + a - t, cy - a, cx - a, cy + a - t, cx - a + t, cy + a], color);
    }

    /** A small crown, `w` wide (as tall as 0.75 w), top-left at (x, y). */
    public static function crown(ui:UiKit, g:Dynamic, x:Float, y:Float, w:Float):Void {
        var k = w / 16;
        function pts(grow:Float):Array<Float> {
            var out:Array<Float> = [];
            var shape = [0.0, 12, 0, 3.5, 4, 7, 8, 0, 12, 7, 16, 3.5, 16, 12];
            var i = 0;
            while (i < shape.length) {
                var px = shape[i], py = shape[i + 1];
                out.push(x + (px + (px < 8 ? -grow : grow)) * k);
                out.push(y + (py + (py < 6 ? -grow : grow)) * k);
                i += 2;
            }
            return out;
        }
        ui.poly(g, pts(1), GOLD_LINE);
        ui.poly(g, pts(0), GOLD);
        ui.rect(g, x, y + 9 * k, 16 * k, 3 * k, 0xD9A31A);
        ui.circle(g, x + 8 * k, y + 1.5 * k, 1.3 * k, 0xFFFFFF, 1, 8);
        ui.circle(g, x + 0.2 * k, y + 3.4 * k, 1.1 * k, 0xFFFFFF, 1, 8);
        ui.circle(g, x + 15.8 * k, y + 3.4 * k, 1.1 * k, 0xFFFFFF, 1, 8);
    }

    /** A check mark of height `size`, top-left at (x, y). */
    public static function check(ui:UiKit, g:Dynamic, x:Float, y:Float, size:Float, color:Int):Void {
        var k = size / 14;
        ui.poly(g, [x + 0 * k, y + 8 * k, x + 2.6 * k, y + 5.6 * k, x + 6 * k, y + 9 * k, x + 13.4 * k, y + 0 * k, x + 16 * k, y + 2.4 * k, x + 6 * k, y + 14 * k], color);
    }

    /** `count` dots round (0, 0), fading from the first to the last: rotate the object to spin it. */
    public static function spinner(ui:UiKit, g:Dynamic, radius:Float, dot:Float, count = 10):Void {
        for (i in 0...count) {
            var a = Math.PI * 2 * i / count - Math.PI / 2;
            ui.circle(g, Math.cos(a) * radius, Math.sin(a) * radius, dot * (0.55 + 0.45 * (i + 1) / count), DARK, 0.12 + 0.88 * (i + 1) / count, 8);
        }
    }
}
