#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?repo root}"
OUT="${RUNNER_TEMP:-/tmp}/mc26-sim"
mkdir -p "$OUT/mc" "$OUT/natives" "$OUT/harness" "$OUT/game"
cd "$OUT"

echo "== download Temurin JDK 25 =="
if [ ! -x "$OUT/jdk25/bin/java" ] && [ ! -x "$OUT/jdk25/Contents/Home/bin/java" ]; then
  curl -fSL --retry 3 -o jdk25.tar.gz \
    "https://api.adoptium.net/v3/binary/latest/25/ga/mac/x64/jdk/hotspot/normal/eclipse"
  mkdir -p jdk25
  tar -xzf jdk25.tar.gz -C jdk25 --strip-components=1
fi
if [ -x "$OUT/jdk25/Contents/Home/bin/java" ]; then
  JDK_HOME="$OUT/jdk25/Contents/Home"
else
  JDK_HOME="$OUT/jdk25"
fi
if [ ! -x "$JDK_HOME/bin/java" ]; then
  echo "JDK layout not recognized:"
  find "$OUT/jdk25" -maxdepth 5 -name java | head
  exit 1
fi
"$JDK_HOME/bin/java" -version

echo "== download Minecraft 26.3 =="
python3 - <<'PY'
import json, os, urllib.request
base = os.environ["RUNNER_TEMP"] + "/mc26-sim"
mc, nat = os.path.join(base, "mc"), os.path.join(base, "natives")
man = json.load(urllib.request.urlopen("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"))
ver = next(v for v in man["versions"] if v["id"] == "26.3")
meta = json.load(urllib.request.urlopen(ver["url"]))
open(os.path.join(base, "version.json"), "w").write(json.dumps(meta, indent=1))

def dl(url, dest):
    if not os.path.exists(dest):
        urllib.request.urlretrieve(url, dest)

dl(meta["downloads"]["client"]["url"], os.path.join(mc, "client.jar"))
n = 0
for lib in meta["libraries"]:
    d = lib.get("downloads") or {}
    art = d.get("artifact")
    if art:
        dl(art["url"], os.path.join(mc, os.path.basename(art["path"])))
        n += 1
    for k, cl in (d.get("classifiers") or {}).items():
        if "macos" in k or "osx" in k:
            dl(cl["url"], os.path.join(nat, os.path.basename(cl["path"])))
print("jars:", n, "natives:", len(os.listdir(nat)))
PY

echo "== build harness =="
cat > "$OUT/harness/Sim.java" <<'EOF'
public class Sim {
    public static void main(String[] args) throws Exception {
        Thread.setDefaultUncaughtExceptionHandler((t, e) -> {
            System.out.println("[SIM] uncaught in " + t.getName() + ": " + e);
            e.printStackTrace(System.out);
        });
        try {
            net.minecraft.client.main.Main.main(args);
        } catch (Throwable t) {
            System.out.println("[SIM] Main threw: " + t);
            t.printStackTrace(System.out);
            System.exit(2);
        }
    }
}
EOF
CP="$ROOT/JavaApp/libs343/*:$OUT/mc/*"
"$JDK_HOME/bin/javac" -cp "$CP" -d "$OUT/harness" "$OUT/harness/Sim.java"

echo "== run simulation =="
CP="$ROOT/JavaApp/libs343/*:$OUT/mc/*:$OUT/harness"
set +e
SDL_VIDEODRIVER=dummy "$JDK_HOME/bin/java" \
  -Dorg.lwjgl.librarypath="$OUT/natives" \
  -Dorg.lwjgl.util.Debug=true \
  -Djava.awt.headless=true \
  -cp "$CP" Sim \
  --version 26.3 --versionType release \
  --gameDir "$OUT/game" \
  --assetsDir "$OUT/game/assets" \
  --assetIndex 26 \
  --username Dev --uuid 00000000000000000000000000000000 \
  --accessToken 0 --userType legacy > "$OUT/sim.log" 2>&1 &
JAVA_PID=$!
for i in $(seq 1 180); do
  if ! kill -0 "$JAVA_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done
if kill -0 "$JAVA_PID" 2>/dev/null; then
  echo "timeout: killing java" >> "$OUT/sim.log"
  kill -9 "$JAVA_PID" 2>/dev/null || true
fi
wait "$JAVA_PID" 2>/dev/null
echo "exit=$?" >> "$OUT/sim.log"
tail -150 "$OUT/sim.log"
