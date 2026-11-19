"""Pure artifact inspection and npm pruning for the official runtime builder.

No CLI, patch configuration, filesystem access or build-time side effects.
"""
import struct

EM_NAMES = {3: "i386", 40: "arm", 62: "x86-64", 183: "aarch64"}

ABI = {
    "arm64-v8a": {"machine": 183, "npm_cpu": "arm64", "node": "arm64", "ubuntu": "arm64", "termux": "aarch64"},
    "x86_64": {"machine": 62, "npm_cpu": "x64", "node": "x64", "ubuntu": "amd64", "termux": "x86_64"},
}


class Elf:
    """Minimal ELF reader (32/64-bit little-endian) for artifact inspection."""

    def __init__(self, data):
        if data[:4] != b"\x7fELF":
            raise ValueError("not ELF")
        self.data = data
        self.bits = 64 if data[4] == 2 else 32
        if data[5] != 1:
            raise ValueError("big-endian ELF not supported")
        if self.bits == 64:
            (_, self.type, self.machine, _, _, self.phoff, self.shoff, _, _, self.phentsize,
             self.phnum, self.shentsize, self.shnum, self.shstrndx) = struct.unpack_from(
                "<16sHHIQQQIHHHHHH", data, 0)
        else:
            (_, self.type, self.machine, _, _, self.phoff, self.shoff, _, _, self.phentsize,
             self.phnum, self.shentsize, self.shnum, self.shstrndx) = struct.unpack_from(
                "<16sHHIIIIIHHHHHH", data, 0)
        self.phdrs = []
        for i in range(self.phnum):
            off = self.phoff + i * self.phentsize
            if self.bits == 64:
                p_type, p_flags, p_offset, p_vaddr, _, p_filesz, p_memsz, p_align = struct.unpack_from(
                    "<IIQQQQQQ", data, off)
            else:
                p_type, p_offset, p_vaddr, _, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from(
                    "<IIIIIIII", data, off)
            self.phdrs.append(dict(type=p_type, offset=p_offset, vaddr=p_vaddr, filesz=p_filesz,
                                   memsz=p_memsz, align=p_align, flags=p_flags))

    def vaddr_to_offset(self, addr):
        for p in self.phdrs:
            if p["type"] == 1 and p["vaddr"] <= addr < p["vaddr"] + p["filesz"]:
                return addr - p["vaddr"] + p["offset"]
        raise ValueError("address 0x%x not in any LOAD segment" % addr)

    def interp(self):
        for p in self.phdrs:
            if p["type"] == 3:
                return self.data[p["offset"]:p["offset"] + p["filesz"]].rstrip(b"\0").decode()
        return None

    def min_load_align(self):
        aligns = [p["align"] for p in self.phdrs if p["type"] == 1]
        return min(aligns) if aligns else None

    def dynamic(self):
        """Returns [(tag, value, file_offset_of_entry)]."""
        out = []
        for p in self.phdrs:
            if p["type"] != 2:
                continue
            size = 16 if self.bits == 64 else 8
            fmt = "<qQ" if self.bits == 64 else "<iI"
            for i in range(p["filesz"] // size):
                off = p["offset"] + i * size
                tag, val = struct.unpack_from(fmt, self.data, off)
                if tag == 0:
                    break
                out.append((tag, val, off))
        return out

    def dynstr(self):
        dyn = dict((t, v) for t, v, _ in self.dynamic())
        if 5 not in dyn:
            return None, 0
        return self.vaddr_to_offset(dyn[5]), dyn.get(10, 0)

    def string_at(self, strtab_off, index):
        end = self.data.index(b"\0", strtab_off + index)
        return self.data[strtab_off + index:end].decode()

    def dyn_strings(self):
        off, _ = self.dynstr()
        res = {"needed": [], "soname": None, "runpath": None}
        if off is None:
            return res
        for tag, val, _ in self.dynamic():
            if tag == 1:
                res["needed"].append(self.string_at(off, val))
            elif tag == 14:
                res["soname"] = self.string_at(off, val)
            elif tag in (15, 29):
                res["runpath"] = self.string_at(off, val)
        return res


def elf_summary(data):
    e = Elf(data)
    info = {
        "class": e.bits,
        "machine": EM_NAMES.get(e.machine, str(e.machine)),
        "e_machine": e.machine,
        "type": {1: "REL", 2: "EXEC", 3: "DYN", 4: "CORE"}.get(e.type, str(e.type)),
        "interp": e.interp(),
        "minLoadAlign": e.min_load_align(),
    }
    try:
        info.update(e.dyn_strings())
    except Exception:  # odd/static ELF: keep header facts only
        pass
    needed = info.get("needed") or []
    # musl's libc is plain "libc.so" (glibc: libc.so.6); Android/bionic objects never reach this audit
    info["musl"] = bool("ld-musl" in (info["interp"] or "") or any("musl" in n or n == "libc.so" for n in needed))
    return info


def dsh_drop_reason(rel, abi, prune_dev):
    parts = rel.split("/")
    if "prebuilds" in parts:
        i = parts.index("prebuilds")
        if i + 1 < len(parts) and not parts[i + 1].startswith("linux-" + ABI[abi]["npm_cpu"]):
            return "foreign-prebuild"
        if i + 1 < len(parts) and "musl" in parts[i + 1]:
            return "foreign-prebuild"
    low = rel.lower()
    if low.endswith((".exe", ".dll", ".pdb", ".dylib")):
        return "foreign-binary"
    if "node-pty/third_party/conpty" in rel:
        return "foreign-binary"
    if prune_dev:
        if "/typescript/" not in "/" + rel and low.endswith((".d.ts", ".d.mts", ".d.cts", ".tsbuildinfo")):
            return "dev-metadata"
        if low.endswith((".js.map", ".mjs.map", ".cjs.map", ".ts.map", ".css.map")):
            return "dev-metadata"
        # A package that emits into src/ and lib/ also publishes the TypeScript
        # it was built from; the runtime loads the emitted JavaScript that sits
        # beside it. Only that layout is pruned: a top-level .ts may be a
        # package's actual entry point, so it keeps its place in the payload.
        if "/typescript/" not in "/" + rel and low.endswith((".ts", ".mts", ".cts")) and _under_emitted_dir(parts):
            return "dev-source"
    return None


def _under_emitted_dir(parts):
    """True when a TypeScript source sits in an emit directory, not at a package root.

    `src/` holds sources next to the `lib/` an emitter produced, and `lib/` holds
    both when a package emits in place (@js-temporal/polyfill). Either way the
    compiled `.js` beside the `.ts` is what gets imported.
    """
    if len(parts) < 3:
        return False
    return any(part in ("src", "lib", "dist", "esm", "cjs") for part in parts[:-1])

