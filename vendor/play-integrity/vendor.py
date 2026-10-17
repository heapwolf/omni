#!/usr/bin/env python3
"""Google Play Integrity, vendored as one jar: play-integrity.jar.

  python3 -I vendor.py           fetch, check against artifacts.lock, rebuild
  python3 -I vendor.py --record  the same, writing artifacts.lock first

Run by hand when the versions change, never by a build. Steps:

1. Fetch each artifact in artifacts.lock from Google's Maven into a new
   temporary directory, and check its SHA-256 against the lock (and against
   Google's published .sha256, which catches corruption only: same host).
2. Refuse native code, and any manifest entry not in allowed-manifest.txt.
3. Compile the bridge (src/keychain/android/play-integrity/OmniAttest.java)
   against the artifacts, and shrink them with R8 to what it reaches:
   no optimizing and no renaming, so what's kept is Google's code as built.
4. Write play-integrity.jar (sorted, fixed timestamps: the same inputs give
   the same bytes), classes.txt and manifest.txt, and its hash to the lock.

Needs a JDK 17+ (JAVA_HOME, else /opt/homebrew/opt/openjdk@17) and omni's
Android toolchain (~/.omni/toolchain: build-tools 36.0.0, android-34).
"""

import hashlib
import io
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OMNI = os.path.dirname(os.path.dirname(HERE))
BRIDGE = os.path.join(OMNI, "src/keychain/android/play-integrity/OmniAttest.java")
MAVEN = "https://dl.google.com/android/maven2/"
TOOLCHAIN = os.environ.get("OMNI_TOOLCHAIN", os.path.expanduser("~/.omni/toolchain"))
D8_JAR = os.path.join(TOOLCHAIN, "build-tools/36.0.0/lib/d8.jar")
ANDROID_JAR = os.path.join(TOOLCHAIN, "platforms/android-34/android.jar")
JAVA_HOME = os.environ.get("JAVA_HOME", "/opt/homebrew/opt/openjdk@17")
ANDROID = "{http://schemas.android.com/apk/res/android}"
# Zip entries' time in the jar: fixed, so the jar's bytes depend only on its contents.
EPOCH = (1980, 1, 1, 0, 0, 0)


def fail(message):
    sys.exit("vendor: " + message)


def read_lock():
    artifacts = []
    for line in open(os.path.join(HERE, "artifacts.lock")):
        line = line.split("#")[0].strip()
        if not line or line.startswith("output "):
            continue
        parts = line.split()
        artifacts.append((parts[0], parts[1] if len(parts) > 1 else None))
    return artifacts


def write_lock(artifacts, output):
    with open(os.path.join(HERE, "artifacts.lock"), "w") as f:
        f.write("# group:artifact:version sha256. Written by vendor.py --record; checked by vendor.py.\n")
        for coordinate, digest in artifacts:
            f.write(f"{coordinate} {digest}\n")
        f.write(f"output play-integrity.jar {output}\n")


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def url(coordinate, ext):
    group, artifact, version = coordinate.split(":")
    return f"{MAVEN}{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}.{ext}"


def manifest_entries(xml, coordinate):
    """Each entry an AAR's manifest adds, as 'element name' lines."""
    root = ET.fromstring(xml)
    entries = []
    for child in root:
        tag = child.tag
        if tag == "uses-sdk":
            continue
        if tag == "application":
            for item in child:
                entries.append(f"{item.tag} {item.get(ANDROID + 'name', '')}")
                for sub in item:
                    entries.append(f"{item.tag}/{sub.tag} {sub.get(ANDROID + 'name', '')}")
        elif tag == "queries":
            for item in child:
                target = item.get(ANDROID + "name") or item.get("package") or ""
                if item.tag == "intent":
                    target = " ".join(sorted(f"{e.tag}={e.get(ANDROID + 'name', '')}" for e in item))
                entries.append(f"queries/{item.tag} {target}")
        else:
            entries.append(f"{tag} {child.get(ANDROID + 'name', '')}")
    return [f"{e}  # {coordinate}" for e in entries]


def run(args, what):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"{what} failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def main():
    record = "--record" in sys.argv
    for path, what in [(D8_JAR, "build-tools 36.0.0"), (ANDROID_JAR, "android-34"), (BRIDGE, "the bridge")]:
        if not os.path.exists(path):
            fail(f"no {what} at {path}")
    java = os.path.join(JAVA_HOME, "bin/java")
    javac = os.path.join(JAVA_HOME, "bin/javac")

    artifacts = read_lock()
    work = tempfile.mkdtemp(prefix="omni-play-integrity-")
    jars, rules, entries, recorded = [], [], [], []
    integers, metadata = {}, {}
    for coordinate, pinned in artifacts:
        # An AAR, or a plain jar for the Java-only ones.
        try:
            data, ext = fetch(url(coordinate, "aar")), "aar"
        except urllib.error.HTTPError:
            data, ext = fetch(url(coordinate, "jar")), "jar"
        digest = sha256(data)
        # Google's published sum: SHA-256, or SHA-1 for older artifacts.
        try:
            published, mine = fetch(url(coordinate, ext + ".sha256")).decode().split()[0].strip(), digest
        except urllib.error.HTTPError:
            published, mine = fetch(url(coordinate, ext + ".sha1")).decode().split()[0].strip(), hashlib.sha1(data).hexdigest()
        if mine != published:
            fail(f"{coordinate}: {mine} isn't Google's published {published}")
        if record:
            pinned = digest
        elif pinned != digest:
            fail(f"{coordinate}: {digest}, but the lock has {pinned}")
        recorded.append((coordinate, digest))

        name = coordinate.replace(":", "_")
        if ext == "jar":
            path = os.path.join(work, name + ".jar")
            open(path, "wb").write(data)
            jars.append(path)
            if any(n.endswith(".so") for n in zipfile.ZipFile(io.BytesIO(data)).namelist()):
                fail(f"{coordinate} carries native code")
            continue
        aar = zipfile.ZipFile(io.BytesIO(data))
        names = aar.namelist()
        native = [n for n in names if n.startswith("jni/") or n.endswith(".so")]
        if native:
            fail(f"{coordinate} carries native code: {native}")
        for entry in names:
            if entry == "classes.jar" or (entry.startswith("libs/") and entry.endswith(".jar")):
                path = os.path.join(work, f"{name}_{os.path.basename(entry)}")
                open(path, "wb").write(aar.read(entry))
                jars.append(path)
            # Keep rules from Google's Play libraries. AndroidX's keep their own
            # classes whether or not anything reaches them.
            elif entry == "proguard.txt" and coordinate.startswith("com.google."):
                path = os.path.join(work, f"{name}.pro")
                open(path, "wb").write(aar.read(entry))
                rules.append(path)
        if "AndroidManifest.xml" in names:
            xml = aar.read("AndroidManifest.xml")
            entries += manifest_entries(xml, coordinate)
            for item in ET.fromstring(xml).iter("meta-data"):
                metadata[item.get(ANDROID + "name")] = item.get(ANDROID + "value")
        if "res/values/values.xml" in names:
            for item in ET.fromstring(aar.read("res/values/values.xml")).iter("integer"):
                integers[item.get("name")] = item.text

    reviewed = {}
    for line in open(os.path.join(HERE, "allowed-manifest.txt")):
        line = line.split("#")[0].strip()
        if line:
            verb, entry = line.split(" ", 1)
            if verb not in ("add", "omit"):
                fail(f"allowed-manifest.txt: '{verb}' is neither add nor omit")
            reviewed[entry] = verb
    refused = [e for e in entries if e.split("#")[0].strip() not in reviewed]
    if refused:
        fail("manifest entries not in allowed-manifest.txt:\n  " + "\n  ".join(refused))

    # What omni declares: meta-data only, its value resolved from the library's resources.
    fragment = []
    for entry, verb in sorted(reviewed.items()):
        if verb != "add":
            continue
        kind, name = entry.split(" ", 1)
        if kind != "meta-data":
            fail(f"only meta-data may be added: {entry}")
        value = metadata.get(name) or ""
        if value.startswith("@integer/"):
            value = integers.get(value[len("@integer/"):]) or ""
        if not value.isdigit():
            fail(f"{name}: no literal value for {metadata.get(name)}")
        fragment.append(f'<meta-data android:name="{name}" android:value="{value}" />')

    # The bridge, compiled against everything, is R8's root.
    classes = os.path.join(work, "bridge")
    os.makedirs(classes)
    run([javac, "-nowarn", "-source", "11", "-target", "11", "-classpath", os.pathsep.join([ANDROID_JAR] + jars),
         "-d", classes, BRIDGE], "javac")
    bridge_jar = os.path.join(work, "bridge.jar")
    with zipfile.ZipFile(bridge_jar, "w") as z:
        for root, _, files in os.walk(classes):
            for f in files:
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, classes))

    shrunk = os.path.join(work, "shrunk.jar")
    log = run([java, "-cp", D8_JAR, "com.android.tools.r8.R8", "--classfile", "--pg-compat",
               "--lib", ANDROID_JAR, "--output", shrunk, "--pg-conf", os.path.join(HERE, "keep.pro")]
              + sum((["--pg-conf", r] for r in rules), []) + [bridge_jar] + jars, "R8")

    # The jar: Google's classes only (omni compiles the bridge itself), sorted, fixed times.
    kept = []
    out = io.BytesIO()
    with zipfile.ZipFile(shrunk) as source, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as target:
        for entry in sorted(source.namelist()):
            if entry.startswith("com/omni/") or entry.endswith("/") or not entry.endswith(".class"):
                continue
            info = zipfile.ZipInfo(entry, EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, source.read(entry))
            kept.append(entry[:-len(".class")].replace("/", "."))
    jar = out.getvalue()
    open(os.path.join(HERE, "play-integrity.jar"), "wb").write(jar)
    open(os.path.join(HERE, "classes.txt"), "w").write("\n".join(kept) + "\n")
    open(os.path.join(HERE, "manifest.txt"), "w").write("\n".join(sorted(entries)) + "\n")
    open(os.path.join(HERE, "manifest-fragment.xml"), "w").write("\n".join(fragment) + "\n")
    output = sha256(jar)

    if record:
        write_lock(recorded, output)
    else:
        pinned = next((l.split()[2] for l in open(os.path.join(HERE, "artifacts.lock")) if l.startswith("output ")), None)
        if pinned != output:
            fail(f"play-integrity.jar is {output}, but the lock has {pinned}: review classes.txt, then --record")
    warnings = [l for l in log.splitlines() if "arning" in l]
    print(f"play-integrity.jar: {len(kept)} classes, {len(jar)} bytes, sha256 {output}")
    for w in warnings[:20]:
        print("  R8: " + w)


if __name__ == "__main__":
    main()
