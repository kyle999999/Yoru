#!/usr/bin/env python3
"""Inspect a source package without executing it. Standard library only."""
import json, sys, zipfile

def inspect(path):
    with zipfile.ZipFile(path) as package:
        manifest = json.loads(package.read("Payload/source.json"))
        data = package.read("Payload/main.wasm")
    offset = 8
    def uint():
        nonlocal offset
        result = shift = 0
        while True:
            b = data[offset]; offset += 1
            result |= (b & 127) << shift
            if b < 128: return result
            shift += 7
    def string():
        nonlocal offset
        length = uint(); value = data[offset:offset+length].decode(); offset += length
        return value
    imports, exports = [], []
    while offset < len(data):
        section = data[offset]; offset += 1
        size = uint(); end = offset + size
        if section == 2:
            for _ in range(uint()):
                module, name = string(), string()
                kind = data[offset]; offset += 1
                if kind != 0: raise ValueError("non-function import")
                imports.append(module + "." + name); uint()
        elif section == 7:
            for _ in range(uint()):
                name = string(); offset += 1; uint(); exports.append(name)
        offset = end
    return {"manifest": manifest, "imports": imports, "exports": exports,
            "abi": "modern (postcard)" if "get_manga_update" in exports else "legacy (descriptors)"}
if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1]), indent=2))
