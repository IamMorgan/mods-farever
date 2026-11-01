"""Reads a HashLink bytecode file (hlboot.dat) and answers questions about the game's classes: names, fields, methods with
signatures (also inherited ones) and statics. Only the type table and the function types are kept."""
import re
import struct

from hl_ops import OPS

KIND_NAMES = ["void", "ui8", "ui16", "i32", "i64", "f32", "f64", "bool", "bytes", "dyn", "fun", "obj", "array", "type", "ref",
              "virtual", "dynobj", "abstract", "enum", "null", "method", "struct", "packed", "guid"]


class HlIndex:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.data = f.read()
        self.pos = 0
        self.types = []
        self.ftypes = {}
        self.classes = {}
        self._parse()

    def _b(self):
        v = self.data[self.pos]
        self.pos += 1
        return v

    def _index(self):
        x = self._b()
        if not x & 0x80:
            return x & 0x7F
        if not x & 0x40:
            v = self._b() | ((x & 31) << 8)
            return -v if x & 0x20 else v
        c, d, e = self._b(), self._b(), self._b()
        v = ((x & 31) << 24) | (c << 16) | (d << 8) | e
        return -v if x & 0x20 else v

    def _i32(self):
        v = struct.unpack_from("<i", self.data, self.pos)[0]
        self.pos += 4
        return v

    def _parse(self):
        index, b = self._index, self._b
        if self.data[:3] != b"HLB":
            raise ValueError("not a HashLink bytecode file")
        self.pos = 3
        version = b()
        flags = index()
        nints, nfloats, nstrings = index(), index(), index()
        nbytes = index() if version >= 5 else 0
        ntypes, nglobals, nnatives, nfunctions = index(), index(), index(), index()
        if version >= 4:
            index()
        index()
        hasdebug = flags & 1
        self.pos += 4 * nints + 8 * nfloats
        size = self._i32()
        sbase = self.pos
        self.pos += size
        lens = [index() for _ in range(nstrings)]
        strings = []
        off = sbase
        for ln in lens:
            strings.append(self.data[off:off + ln].decode("utf-8", "replace"))
            off += ln + 1
        if version >= 5:
            size = self._i32()
            self.pos += size
            for _ in range(nbytes):
                index()
        if hasdebug:
            nd = index()
            size = self._i32()
            self.pos += size
            for _ in range(nd):
                index()
        types = self.types
        for _ in range(ntypes):
            kind = b()
            t = {"kind": kind}
            if kind in (10, 20):
                n = b()
                t["args"] = [index() for _ in range(n)]
                t["ret"] = index()
            elif kind in (11, 21):
                t["name"] = strings[index()]
                t["super"] = index()
                index()
                nf, npr, nb = index(), index(), index()
                t["fields"] = [(strings[index()], index()) for _ in range(nf)]
                t["protos"] = [(strings[index()], index(), index()) for _ in range(npr)]
                for _ in range(nb):
                    index()
                    index()
            elif kind == 15:
                nf = index()
                t["fields"] = [(strings[index()], index()) for _ in range(nf)]
            elif kind == 17:
                t["name"] = strings[index()]
            elif kind == 18:
                t["name"] = strings[index()]
                index()
                nc = index()
                t["cons"] = []
                for _ in range(nc):
                    cn = strings[index()]
                    npar = index()
                    t["cons"].append((cn, [index() for _ in range(npar)]))
            elif kind in (14, 19, 22):
                t["param"] = index()
            types.append(t)
        for _ in range(nglobals):
            index()
        for _ in range(nnatives):
            index(); index(); index(); index()
        for _ in range(nfunctions):
            ft, findex, nregs, nops = index(), index(), index(), index()
            self.ftypes[findex] = ft
            for _ in range(nregs):
                index()
            for _ in range(nops):
                name, n = OPS[b()]
                if n == -1:
                    if name == "OSwitch":
                        index()
                        for _ in range(index()):
                            index()
                        index()
                    else:
                        index(); index()
                        for _ in range(b()):
                            index()
                else:
                    for _ in range(max(n, 3) if n >= 4 else n):
                        index()
            if hasdebug:
                i = 0
                while i < nops:
                    c = b()
                    if c & 1:
                        b()
                    elif c & 2:
                        i += (c >> 2) & 15
                    elif c & 4:
                        i += 1
                    else:
                        b(); b()
                        i += 1
                for _ in range(index()):
                    index(); index()
                    if version >= 6:
                        index()
        for t in types:
            if t["kind"] in (11, 21):
                self.classes[t["name"]] = t
        self.data = None

    def tname(self, i, depth=0):
        t = self.types[i]
        k = t["kind"]
        if k in (11, 21, 17, 18):
            return t["name"]
        if k in (10, 20):
            if depth > 3:
                return "fun"
            return "(" + ", ".join(self.tname(a, depth + 1) for a in t["args"]) + ") -> " + self.tname(t["ret"], depth + 1)
        if k in (14, 19, 22):
            return KIND_NAMES[k] + "<" + self.tname(t["param"], depth + 1) + ">"
        if k == 15:
            if depth > 1:
                return "{...}"
            return "{" + ", ".join(n + ":" + self.tname(ti, depth + 1) for n, ti in t["fields"][:6]) + "}"
        return KIND_NAMES[k]

    def _super(self, t):
        s = t["super"]
        return self.types[s] if s >= 0 else None

    def method_signature(self, findex):
        ft = self.ftypes.get(findex)
        return self.tname(ft) if ft is not None else "?"

    def find_types(self, pattern, limit=60):
        rx = re.compile(pattern, re.I)
        names = sorted(n for n in self.classes if rx.search(n))
        return {"count": len(names), "types": names[:limit]}

    def find_members(self, pattern, limit=80):
        """Methods and fields whose 'Class.member' matches the regex."""
        rx = re.compile(pattern, re.I)
        out = []
        for name, t in self.classes.items():
            for pname, findex, _ in t["protos"]:
                full = name + "." + pname
                if rx.search(full):
                    out.append("method " + full + " " + self.method_signature(findex))
            for fname, ti in t["fields"]:
                full = name + "." + fname
                if rx.search(full):
                    out.append("field " + full + ": " + self.tname(ti))
        out.sort()
        return {"count": len(out), "members": out[:limit]}

    def describe_type(self, name, match=None):
        """Own and inherited fields and methods (with signatures) and the statics of a class."""
        t = self.classes.get(name)
        if t is None:
            near = [n for n in self.classes if name.lower() in n.lower()][:10]
            return {"error": "no such type: " + name, "similar": near}
        chain = []
        cur = t
        while cur is not None:
            chain.append(cur)
            cur = self._super(cur)
        fields = []
        methods = []
        for c in chain:
            for fname, ti in c["fields"]:
                fields.append(c["name"] + "." + fname + ": " + self.tname(ti))
            for pname, findex, _ in c["protos"]:
                methods.append(c["name"] + "." + pname + " " + self.method_signature(findex))
        statics = self.classes.get("$" + name)
        methods = sorted(set(methods))
        if match:
            rx = re.compile(match, re.I)
            fields = [f for f in fields if rx.search(f)]
            methods = [m for m in methods if rx.search(m)]
        out = {"type": name, "super": [c["name"] for c in chain[1:]], "fields": fields, "methods": methods}
        if statics is not None:
            sf = [fname + ": " + self.tname(ti) for fname, ti in statics["fields"]]
            sm = sorted(pname + " " + self.method_signature(findex) for pname, findex, _ in statics["protos"])
            if match:
                sf = [x for x in sf if rx.search(x)]
                sm = [x for x in sm if rx.search(x)]
            out["static_fields"] = sf
            out["static_methods"] = sm
        return out
