package integrator;

import haxe.io.Bytes;
import sys.net.Socket;

/** Local TCP server on 127.0.0.1: one client at a time, one JSON object per line in both directions. Never blocks the game. */
class Server {
    public static inline var PORT = 47800;

    var listener:Socket;
    var client:Socket;
    var pending:Bytes = Bytes.alloc(0);
    var acceptErrorLogged = false;
    var chunk:Bytes = Bytes.alloc(65536);

    public function new() {
        try {
            listener = new Socket();
            listener.bind(new sys.net.Host("127.0.0.1"), PORT);
            listener.listen(1);
            listener.setBlocking(false);
            Log.t("server", "listening on 127.0.0.1:" + PORT);
        } catch (e:Dynamic) {
            listener = null;
            Log.t("server", "cannot listen: " + Std.string(e));
        }
    }

    /** Accepts a client, reads what has arrived and calls `handle` for every complete line; the return value is sent back. */
    public function poll(handle:String -> Dynamic):Void {
        if (listener == null) return;
        try {
            var c = listener.accept();
            if (c != null) {
                c.setBlocking(false);
                drop();
                client = c;
                Log.t("server", "client connected");
            }
        } catch (e:Dynamic) {
            if (Std.string(e) != "Blocked" && !acceptErrorLogged) {
                acceptErrorLogged = true;
                Log.t("server", "accept: " + Std.string(e));
            }
        }
        if (client == null) return;
        try {
            var n = client.input.readBytes(chunk, 0, chunk.length);
            var joined = Bytes.alloc(pending.length + n);
            joined.blit(0, pending, 0, pending.length);
            joined.blit(pending.length, chunk, 0, n);
            pending = joined;
        } catch (e:Dynamic) {
            if (Std.string(e) != "Blocked") {
                Log.t("server", "client gone: " + Std.string(e));
                drop();
                return;
            }
        }
        while (true) {
            var end = -1;
            for (i in 0...pending.length) if (pending.get(i) == 10) { end = i; break; }
            if (end < 0) break;
            var line = pending.getString(0, end);
            pending = pending.sub(end + 1, pending.length - end - 1);
            if (StringTools.trim(line) == "") continue;
            var answer = handle(line);
            try client.output.writeString(haxe.Json.stringify(answer) + "\n") catch (e:Dynamic) { drop(); return; }
        }
    }

    function drop():Void {
        if (client != null) try client.close() catch (_:Dynamic) {}
        client = null;
        pending = Bytes.alloc(0);
    }
}
