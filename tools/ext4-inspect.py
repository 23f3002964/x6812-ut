import sys
import ext4

p = sys.argv[1]
v = ext4.Volume(open(p, "rb"))


def names(node):
    out = []
    for de, ftype in node.opendir():
        name = de.name
        if isinstance(name, bytes):
            name = name.decode("utf-8", "replace")
        out.append((name, ftype))
    return out


def read(path):
    try:
        node = v.inode_at(path)
        return node.open().read()
    except Exception as e:
        return f"<err {e}>".encode()


print("=== / ===")
for name, ft in names(v.root):
    print(" ", name)

for base in ["/system", "/system/etc", "/system/bin"]:
    print(f"\n=== {base} (first 40) ===")
    try:
        node = v.inode_at(base)
        for name, ft in names(node)[:40]:
            print(" ", name)
    except Exception as e:
        print("  <err>", e)

for candidate in ["/system/build.prop", "/build.prop", "/system/etc/build.prop",
                  "/system/bin/init", "/system/etc/init/hw/init.rc"]:
    data = read(candidate)
    print(f"\n=== {candidate} ===")
    if isinstance(data, bytes) and data.startswith(b"<err"):
        print(data.decode())
    elif candidate.endswith("build.prop"):
        txt = data.decode("utf-8", "replace")
        for line in txt.splitlines():
            if any(k in line for k in ("ro.build.version", "ro.product", "ro.halium",
                                       "ro.vendor.api_level", "ro.build.type", "ro.build.id",
                                       "ro.build.fingerprint", "ro.treble", "ro.build.ab_update")):
                print(line)
    else:
        print("size:", len(data))
