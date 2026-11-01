"""Integrator: a desktop window where a command in plain words goes to an Ollama model, and the model acts in the game
through the Integrator mod (TCP 127.0.0.1:47800, one JSON object per line). Needs only Python 3 with tkinter."""
import json
import queue
import socket
import threading
import tkinter as tk
import urllib.request
from tkinter import scrolledtext, ttk

MOD_ADDRESS = ("127.0.0.1", 47800)
OLLAMA_URL = "http://localhost:11434/api/chat"
OLLAMA_TAGS_URL = "http://localhost:11434/api/tags"
MAX_STEPS = 12

SYSTEM_PROMPT = (
    "You control the game Farever through tools. Do what the user asks by calling the tools, one step at a time; "
    "look at the results before the next call. Game paths start at the GameApp (for example hero.player) or at a static "
    "(@Data.item). World objects are in hero.layer.interactibles.N (Npc, CraftStation, Chest...) and hero.layer.units.N. "
    "Server requests are apiRpc* methods (for example ent.Element.apiRpcBuyItem with args [itemId, \"@noop\"]); "
    "the last argument of every apiRpc* method is a callback: pass the string \"@noop\" for it. "
    "When the task is done, answer briefly what was done."
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

TOOL_TO_COMMAND = {"game_get": "get", "game_set": "set", "game_call": "call", "game_static": "static",
                   "net_events": "net_events", "net_rule": "net_rule", "net_unrule": "net_unrule"}


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

    def run_tool(self, call):
        name = call["function"]["name"]
        arguments = call["function"].get("arguments") or {}
        if isinstance(arguments, str):
            arguments = json.loads(arguments)
        command = TOOL_TO_COMMAND.get(name)
        if command is None:
            return {"ok": False, "error": "unknown tool " + name}
        self.write("  %s %s" % (name, json.dumps(arguments, ensure_ascii=False)))
        try:
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
