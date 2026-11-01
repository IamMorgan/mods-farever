"""Integrator: a desktop window where a command in plain words goes to an Ollama model, and the model acts in the game
through the Integrator mod (TCP 127.0.0.1:47800, one JSON object per line). Needs only Python 3 with tkinter."""
import json
import queue
import socket
import threading
import tkinter as tk
import urllib.request
from tkinter import scrolledtext, ttk

from hl_index import HlIndex

MOD_ADDRESS = ("127.0.0.1", 47800)
OLLAMA_URL = "http://localhost:11434/api/chat"
OLLAMA_TAGS_URL = "http://localhost:11434/api/tags"
MAX_STEPS = 12

SYSTEM_PROMPT = (
    "You control the game Farever through tools and can do anything the user asks. Work step by step and read each result "
    "before the next call. You know nothing about the game in advance, so discover it: "
    "find_types / find_members / describe_type show the game's classes, fields, methods and their signatures (use them to "
    "find the method and its argument types); game_fields lists the fields of an object; game_get reads a value; "
    "search finds records in a data array by text (shown names are in the game language, which is the user's); "
    "game_call / game_static call methods; game_set changes fields; net_* watch and change the network traffic. "
    "Paths start at the game app (for example hero.player) or at a class static (for example @Data.item); names are fields, "
    "numbers index an array. A callback argument of type (bool) -> void is passed as the string \"@noop\". "
    "Never give up after one failure: look at the error, explore with the discovery tools, try again. "
    "When done, answer the user briefly in the user's language."
)

TOOLS = [
    {"type": "function", "function": {
        "name": "game_get",
        "description": "Read a value of the game. Names are fields, numbers index an array.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "depth": {"type": "integer"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "game_set",
        "description": "Set a field of the game object at the path.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "field": {"type": "string"}, "value": {}}, "required": ["path", "field", "value"]}}},
    {"type": "function", "function": {
        "name": "game_call",
        "description": "Call a method of the game object at the path (type is the full class name that has the method).",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "type": {"type": "string"}, "method": {"type": "string"},
            "args": {"type": "array", "items": {}}, "depth": {"type": "integer"}},
            "required": ["path", "type", "method"]}}},
    {"type": "function", "function": {
        "name": "game_static",
        "description": "Call a static method of a game class.",
        "parameters": {"type": "object", "properties": {
            "type": {"type": "string"}, "method": {"type": "string"},
            "args": {"type": "array", "items": {}}, "depth": {"type": "integer"}},
            "required": ["type", "method"]}}},
    {"type": "function", "function": {
        "name": "game_fields",
        "description": "Field names of the game object at the path.",
        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "search",
        "description": "In the array at the path (for example @Data.item.all) find records that have a text field containing the query "
                       "(case-insensitive). Returns [{index, matches: [\"field = text\"]}].",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "query": {"type": "string"}}, "required": ["path", "query"]}}},
    {"type": "function", "function": {
        "name": "find_types",
        "description": "Game classes whose full name matches the regex.",
        "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
    {"type": "function", "function": {
        "name": "find_members",
        "description": "Methods and fields whose 'Class.member' matches the regex, with signatures.",
        "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
    {"type": "function", "function": {
        "name": "describe_type",
        "description": "Fields, methods (with signatures, own and inherited) and statics of a class; `match` is an optional regex filter.",
        "parameters": {"type": "object", "properties": {
            "name": {"type": "string"}, "match": {"type": "string"}}, "required": ["name"]}}},
    {"type": "function", "function": {
        "name": "net_events",
        "description": "Network messages the game sent (dir out), received (dir in) and server calls (dir rpc) after event number `since`.",
        "parameters": {"type": "object", "properties": {
            "since": {"type": "integer"}, "limit": {"type": "integer"}}}}},
    {"type": "function", "function": {
        "name": "net_rule",
        "description": "Add a network rule: {dir: out|in|rpc, label?, type?, rpc?, prefix? (hex the bytes start with), "
                       "action: block|patch, offset?, hex?, times?}. Returns the rule id.",
        "parameters": {"type": "object", "properties": {"rule": {"type": "object"}}, "required": ["rule"]}}},
    {"type": "function", "function": {
        "name": "net_unrule",
        "description": "Remove a network rule by id.",
        "parameters": {"type": "object", "properties": {"rule": {"type": "integer"}}, "required": ["rule"]}}},
]

TOOL_TO_COMMAND = {"game_get": "get", "game_set": "set", "game_call": "call", "game_static": "static", "game_fields": "fields",
                   "search": "search", "net_events": "net_events", "net_rule": "net_rule", "net_unrule": "net_unrule"}
HLBOOT = r"D:\Steam\steamapps\common\Farever\hlboot.dat"
INDEX_TOOLS = ("find_types", "find_members", "describe_type")


class GameLink:
    def __init__(self):
        self.sock = None
        self.reader = None
        self.next_id = 1
        self.lock = threading.Lock()

    def connect(self):
        self.close()
        self.sock = socket.create_connection(MOD_ADDRESS, timeout=10)
        self.reader = self.sock.makefile("r", encoding="utf-8")

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.reader = None

    def send(self, command, fields):
        with self.lock:
            if self.sock is None:
                self.connect()
            message = dict(fields)
            message["id"] = self.next_id
            message["cmd"] = command
            self.next_id += 1
            try:
                self.sock.sendall((json.dumps(message) + "\n").encode("utf-8"))
                line = self.reader.readline()
            except OSError:
                self.close()
                raise
            if not line:
                self.close()
                raise ConnectionError("the mod closed the connection")
            return json.loads(line)


def ollama_models():
    with urllib.request.urlopen(OLLAMA_TAGS_URL, timeout=10) as response:
        return [m["name"] for m in json.loads(response.read().decode("utf-8"))["models"]]


def ollama_chat(model, messages):
    body = json.dumps({"model": model, "messages": messages, "tools": TOOLS, "stream": False}).encode("utf-8")
    request = urllib.request.Request(OLLAMA_URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=300) as response:
        return json.loads(response.read().decode("utf-8"))["message"]


class App:
    def __init__(self):
        self.link = GameLink()
        self.history = [{"role": "system", "content": SYSTEM_PROMPT}]
        self.events = queue.Queue()
        self.busy = False
        self.index = None
        self.index_lock = threading.Lock()

        self.root = tk.Tk()
        self.root.title("Integrator")
        self.root.geometry("760x560")
        top = tk.Frame(self.root)
        top.pack(fill="x", padx=6, pady=4)
        tk.Label(top, text="Model:").pack(side="left")
        self.model = ttk.Combobox(top, width=28, values=["qwen3:8b"])
        self.model.set("qwen3:8b")
        self.model.pack(side="left", padx=4)
        tk.Button(top, text="Refresh models", command=self.refresh_models).pack(side="left", padx=4)
        tk.Button(top, text="Check the mod", command=self.check_mod).pack(side="left", padx=4)
        self.log = scrolledtext.ScrolledText(self.root, state="disabled", wrap="word")
        self.log.pack(fill="both", expand=True, padx=6)
        # a disabled Text never gets the focus, so without this Ctrl+C copies nothing
        self.log.bind("<Button-1>", lambda _e: self.log.focus_set())
        for key in ("<Control-a>", "<Control-A>"):
            self.log.bind(key, lambda _e: (self.log.tag_add("sel", "1.0", "end"), "break")[1])
        bottom = tk.Frame(self.root)
        bottom.pack(fill="x", padx=6, pady=6)
        self.entry = tk.Entry(bottom)
        self.entry.pack(side="left", fill="x", expand=True)
        self.entry.bind("<Return>", lambda _e: self.submit())
        tk.Button(bottom, text="Send", command=self.submit).pack(side="left", padx=4)
        self.root.after(100, self.drain)
        self.refresh_models()

    def write(self, text):
        self.events.put(text)

    def drain(self):
        try:
            while True:
                text = self.events.get_nowait()
                self.log.configure(state="normal")
                self.log.insert("end", text + "\n")
                self.log.see("end")
                self.log.configure(state="disabled")
        except queue.Empty:
            pass
        self.root.after(100, self.drain)

    def refresh_models(self):
        def work():
            try:
                names = ollama_models()
                self.root.after(0, lambda: self.model.configure(values=names))
                self.write("models: " + (", ".join(names) or "none installed"))
            except Exception as error:
                self.write("Ollama: no connection (%s)" % error)
        threading.Thread(target=work, daemon=True).start()

    def check_mod(self):
        def work():
            try:
                self.write("mod: " + json.dumps(self.link.send("ping", {})))
            except Exception as error:
                self.write("mod: no connection (%s)" % error)
        threading.Thread(target=work, daemon=True).start()

    def submit(self):
        text = self.entry.get().strip()
        if not text or self.busy:
            return
        self.entry.delete(0, "end")
        self.busy = True
        self.write("> " + text)
        self.history.append({"role": "user", "content": text})
        threading.Thread(target=self.run_model, args=(self.model.get().strip(),), daemon=True).start()

    def game_index(self):
        with self.index_lock:
            if self.index is None:
                self.write("  (reading the game's type table, once)")
                self.index = HlIndex(HLBOOT)
            return self.index

    def run_tool(self, call):
        name = call["function"]["name"]
        arguments = call["function"].get("arguments") or {}
        if isinstance(arguments, str):
            arguments = json.loads(arguments)
        command = TOOL_TO_COMMAND.get(name)
        if command is None and name not in INDEX_TOOLS:
            return {"ok": False, "error": "unknown tool " + name}
        self.write("  %s %s" % (name, json.dumps(arguments, ensure_ascii=False)))
        try:
            if command is None:
                result = {"ok": True, "result": getattr(self.game_index(), name)(**arguments)}
            else:
                result = self.link.send(command, arguments)
        except Exception as error:
            result = {"ok": False, "error": str(error)}
        self.write("  -> " + json.dumps(result, ensure_ascii=False)[:600])
        return result

    def run_model(self, model):
        try:
            for _ in range(MAX_STEPS):
                message = ollama_chat(model, self.history)
                self.history.append(message)
                calls = message.get("tool_calls") or []
                if not calls:
                    self.write(message.get("content", ""))
                    return
                for call in calls:
                    result = self.run_tool(call)
                    self.history.append({"role": "tool", "content": json.dumps(result, ensure_ascii=False)[:8000]})
            self.write("(stopped: too many steps)")
        except Exception as error:
            self.write("error: %s" % error)
        finally:
            self.busy = False

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().run()
