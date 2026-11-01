package integrator;

import hlx.runtime.HlxPrefixResult;

/**
 * Integrator: opens a local TCP port (see Server) through which the desktop app reads the game and calls its methods
 * (see Commands). Every game object is reached through HlxRuntime (see GameAccess), never through imported game classes.
 */
@:build(hlx.runtime.Mod.build())
class IntegratorMod {
    static var server:Server;

    static function main():Void {
        Log.t("mod", "Integrator loaded");
        server = new Server();
    }

    @:hlx.prefix(GameApp.update)
    static function beforeGameAppUpdate(instance:Dynamic, dt:Float):HlxPrefixResult<Void> {
        if (Commands.app == null) Log.t("mod", "first game update");
        Commands.app = instance;
        try server.poll(Commands.handle) catch (e:Dynamic) Log.t("err", "poll failed: " + Std.string(e));
        return Continue;
    }

    // Outgoing bytes: each layer of the client's send path (a message may be seen by several of them).
    @:hlx.prefix(hxbit.NetworkHost.send)
    static function outHost(instance:Dynamic, bytes:Dynamic):HlxPrefixResult<Void> return Net.raw("out", "NetworkHost.send", bytes, 0) ? Skip : Continue;

    @:hlx.prefix(hxbit.NetworkClient.send)
    static function outClient(instance:Dynamic, bytes:Dynamic):HlxPrefixResult<Void> return Net.raw("out", "NetworkClient.send", bytes, 0) ? Skip : Continue;

    @:hlx.prefix(mpman.net.Client.send)
    static function outMpClient(instance:Dynamic, bytes:Dynamic):HlxPrefixResult<Void> {
        Net.client = instance;
        return Net.raw("out", "mpman.Client.send", bytes, 0) ? Skip : Continue;
    }

    @:hlx.prefix(mpman.net.WSService.send)
    static function outWs(instance:Dynamic, bytes:Dynamic):HlxPrefixResult<Void> return Net.raw("out", "WSService.send", bytes, 0) ? Skip : Continue;

    // Incoming bytes.
    @:hlx.prefix(hxbit.NetworkClient.processMessage)
    static function inMessage(instance:Dynamic, bytes:Dynamic, pos:Int):HlxPrefixResult<Int> return Net.raw("in", "processMessage", bytes, pos) ? SkipWith(pos) : Continue;

    @:hlx.prefix(hxbit.NetworkClient.processMessagesData)
    static function inData(instance:Dynamic, bytes:Dynamic, pos:Int, length:Int):HlxPrefixResult<Void> return Net.raw("in", "processMessagesData", bytes, pos) ? Skip : Continue;

    // A call of an object method on the server.
    @:hlx.prefix(hxbit.NetworkHost.doRPC)
    static function rpcCall(instance:Dynamic, object:Dynamic, id:Int, onSend:Dynamic, onResult:Dynamic):HlxPrefixResult<Void> return Net.rpc("doRPC", object, id) ? Skip : Continue;
}
