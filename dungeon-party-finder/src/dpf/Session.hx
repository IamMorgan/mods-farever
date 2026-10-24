package dpf;

import dpf.DungeonList.DungeonInfo;
import dpf.PartyFlow.Card;
import dpf.PartyLogic.ButtonKind;
import dpf.Search.LobbyApi;
import dpf.Search.Peer;

enum Mode {
    Idle;
    Searching;
    /** A party has formed: the dungeon lobby is shown. */
    Party;
}

typedef ButtonView = {label:String, enabled:Bool, lit:Bool};

/** What the dungeon window shows right now. `signature` changes whenever anything visible does. */
typedef SessionView = {
    mode:Mode,
    status:String,
    info:String,
    spinner:Bool,
    cards:Array<Card>,
    button:ButtonView,
    message:String,
    signature:String
};

/**
 * One dungeon the player is looking for a group in: the chosen difficulty, the matchmaking (Search) and, once a party has
 * formed, the dungeon lobby (PartyFlow). The window only reads `view()` and calls `press()` / `selectDifficulty()`.
 */
class Session {
    public var dungeon(default, null):DungeonInfo;
    public var difficulty(default, null) = 0;
    public var usable(default, null):Array<Bool> = [true, false, false];
    public var russian = false;

    var party:GameParty;
    var lobbies:LobbyApi;
    var search:Search;
    var flow:PartyFlow;
    var inParty = false;
    var message = "";
    var lostAt = -1.0;
    var minPlayers:Int;

    public function new(dungeon:DungeonInfo, party:GameParty, lobbies:LobbyApi, minPlayers:Int, russian:Bool) {
        this.dungeon = dungeon;
        this.party = party;
        this.lobbies = lobbies;
        this.minPlayers = minPlayers;
        this.russian = russian;
        search = new Search(lobbies, party, () -> Date.now().getTime(), 4, minPlayers);
        flow = new PartyFlow(party);
        refresh();
    }

    public function setMinPlayers(value:Int):Void {
        minPlayers = value;
        search.minPlayers = value;
    }

    /** True while there is something to keep: a search or a party. */
    public function isBusy():Bool return search.isActive() || inParty;

    public function mode():Mode return inParty ? Party : (search.isActive() ? Searching : Idle);

    /** The difficulties the hero may pick, read again (a heroic mode may have just opened). */
    public function refresh():Void {
        try usable = GameDungeons.difficulties(party, dungeon.id) catch (_:Dynamic) usable = [true, false, false];
        difficulty = Difficulties.clamp(difficulty, usable);
    }

    public function selectDifficulty(value:Int):Void {
        if (isBusy() || value < 0 || value >= usable.length || !usable[value]) return;
        difficulty = value;
        message = "";
    }

    /** The key players are matched by (see SearchKey) for the hero's level and the chosen difficulty. */
    public function key():String
        return SearchKey.make(dungeon.id, difficulty, LevelBrackets.index(party.level(), party.maxLevel()));

    public function bracketLabel():String return LevelBrackets.label(LevelBrackets.index(party.level(), party.maxLevel()), party.maxLevel());

    public function startSearch(now:Float):Void {
        if (isBusy()) return;
        message = "";
        if (party.hero() == null || party.me() == null) { message = Locale.noHero(russian); return; }
        if (party.groupSize() > 1) { message = Locale.inParty(russian); return; }
        search.minPlayers = minPlayers;
        var me:Peer = {id: lobbies.selfId(), uid: party.uid(), name: party.name(), level: party.level()};
        search.start(key(), me, now);
        Log.write("search started: " + key() + " as " + me.uid + " (" + me.id + ")");
    }

    public function cancel():Void {
        search.cancel();
        if (inParty) endParty();
        message = "";
    }

    function endParty():Void {
        inParty = false;
        lostAt = -1;
        flow.end();
        search.reset();
    }

    /** The big button of the window. */
    public function press(now:Float):Void {
        switch mode() {
            case Idle: startSearch(now);
            case Searching: search.cancel(); message = "";
            case Party: flow.press();
        }
    }

    public function update(now:Float):Void {
        try {
            if (party.hero() == null) return; // loading between zones: wait
            var before = Std.string(search.state);
            search.update(now);
            if (Std.string(search.state) != before) Log.write("search: " + before + " -> " + Std.string(search.state) + " (" + search.count + " in lobby)");
            switch search.state {
                case Grouped if (!inParty):
                    inParty = true;
                    lostAt = -1;
                    flow.begin(dungeon.id, difficulty);
                    Log.write("party formed with " + party.groupSize() + " players, leader " + party.isLeader());
                case Failed(reason) if (message == ""):
                    message = reason == "party" ? Locale.inParty(russian) : Locale.platformDown(russian);
                    Log.write("search failed: " + reason + " " + search.lastError);
                default:
            }
            if (inParty) {
                if (party.groupSize() < 2) {
                    if (lostAt < 0) lostAt = now;
                    else if (now - lostAt > 2) { endParty(); message = Locale.partyLost(russian); }
                } else {
                    lostAt = -1;
                    flow.update(now);
                }
            }
        } catch (error:Dynamic) Log.write("session update failed: " + Std.string(error));
    }

    function myCard():Card
        return {name: party.name(), detail: party.detail(party.me()), ready: false, leader: false, me: true};

    function buttonView(kind:ButtonKind):ButtonView
        return switch kind {
            case Wait: {label: Locale.waitLobby(russian), enabled: false, lit: false};
            case Start(enabled): {label: Locale.start(russian), enabled: enabled, lit: false};
            case CancelStart: {label: Locale.cancel(russian), enabled: true, lit: false};
            case Ready(on): {label: Locale.ready(russian), enabled: true, lit: on};
            case Loading: {label: Locale.loading(russian), enabled: false, lit: false};
        };

    public function view():SessionView {
        var mode = mode();
        var status = "", info = "", spinner = false;
        var cards:Array<Card> = [];
        var button:ButtonView;
        var text = message;
        switch mode {
            case Idle:
                cards = [myCard()];
                button = {label: Locale.search(russian), enabled: true, lit: false};
            case Searching:
                cards = [myCard()];
                spinner = true;
                status = Type.enumEq(search.state, Inviting) ? Locale.inviting(russian) : Locale.searching(russian);
                info = search.count > 0 ? Locale.found(russian, search.count, 4) : "";
                button = {label: Locale.cancel(russian), enabled: true, lit: false};
            case Party:
                cards = flow.cards();
                var kind = flow.button();
                button = buttonView(kind);
                switch kind {
                    case Wait: status = Locale.waitLobby(russian); spinner = true;
                    case Start(false): status = Locale.waitPlayers(russian);
                    case Loading: status = Locale.loading(russian); spinner = true;
                    default:
                }
                if (text == "") text = flow.message;
                if (text == "" && flow.refused >= 2) text = Locale.lobbyRefused(russian);
        }
        var signature = [Std.string(mode), status, info, text, Std.string(difficulty), usable.join(","), button.label, Std.string(button.enabled), Std.string(button.lit)]
            .concat([for (c in cards) c.name + "|" + c.detail + "|" + c.ready + "|" + c.leader]).join("/");
        return {mode: mode, status: status, info: info, spinner: spinner, cards: cards, button: button, message: text, signature: signature};
    }
}
