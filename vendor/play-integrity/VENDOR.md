# Play Integrity

Google's Play Integrity library, shrunk to what `OmniAttest.java` reaches.
Built in only for apps whose omni.json has `playIntegrity`.

| File | What |
|---|---|
| `artifacts.lock` | the 21 artifacts (Google Maven), SHA-256 each; the jar's SHA-256 |
| `play-integrity.jar` | the output: 146 classes, Google's code as built |
| `classes.txt` | every class in the jar |
| `manifest.txt` | every manifest entry the artifacts declare |
| `allowed-manifest.txt` | each entry reviewed: `add` or `omit` |
| `manifest-fragment.xml` | what omni's builder adds to `<application>` |
| `keep.pro` | R8's root: the bridge; shrinking only |
| `vendor.py` | fetch, check, audit, shrink, write |

## Rules

- `vendor.py` runs by hand, never in a build. The build only reads the jar, after checking its hash against the lock.
- An artifact whose SHA-256 differs from the lock fails.
- Native code in any artifact fails.
- A manifest entry not in `allowed-manifest.txt` fails. Only meta-data can be added.
- R8 runs in `--pg-compat` mode with `-dontoptimize` and `-dontobfuscate`, keeping all attributes.
- Keep rules come from the `com.google.*` artifacts only.
- The same inputs give the same jar, byte for byte.

## Update

1. Change versions in `artifacts.lock`.
2. `python3 -I vendor.py --record`
3. Review the diff of `classes.txt`, `manifest.txt` and `artifacts.lock`.

Needs JDK 17+ and `~/.omni/toolchain` (build-tools 36.0.0, android-34).
