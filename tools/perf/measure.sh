#!/usr/bin/env bash
# Measurement-only Android emulator harness. It intentionally does not alter app source or data.
set +e

ARTIFACT_DIR=${1:-perf-artifacts/apks}
RUNS=${2:-5}
OUT=perf-artifacts
PACKAGE_DEBUG=org.lichess.mobileV2.debug
PACKAGE_PROFILE=org.lichess.mobileV2
ACTIVITY=.MainActivity
ADB=${ADB:-adb}
mkdir -p "$OUT"/{starts,logcat,screenshots,meminfo,gfxinfo,trace}
SUMMARY="$OUT/summary.md"
: > "$SUMMARY"

note() { echo "$*" | tee -a "$OUT/harness.log"; }
safe() { "$@" >>"$OUT/harness.log" 2>&1; return 0; }
valid_runs() { [[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || RUNS=5; }
valid_runs

cache_status='Not attempted'
if $ADB root >>"$OUT/harness.log" 2>&1 && $ADB shell 'echo 3 > /proc/sys/vm/drop_caches' >>"$OUT/harness.log" 2>&1; then
  cache_status='Dropped with adb root before launch samples'
else
  cache_status='Could not drop Linux page caches (adb root unavailable or denied); force-stop still used'
fi
$ADB unroot >>"$OUT/harness.log" 2>&1 || true

set_network() {
  local wanted=$1 current method=unknown
  if [[ "$wanted" == on ]]; then
    $ADB shell cmd connectivity airplane-mode disable >>"$OUT/harness.log" 2>&1
    sleep 2
    current=$($ADB shell settings get global airplane_mode_on 2>/dev/null | tr -d '\r')
    if [[ "$current" == 0 ]]; then method='cmd connectivity airplane-mode disable'; else
      $ADB shell svc wifi enable >>"$OUT/harness.log" 2>&1
      method='svc wifi enable (airplane-mode verification failed)'
    fi
  else
    $ADB shell cmd connectivity airplane-mode enable >>"$OUT/harness.log" 2>&1
    sleep 2
    current=$($ADB shell settings get global airplane_mode_on 2>/dev/null | tr -d '\r')
    if [[ "$current" == 1 ]]; then method='cmd connectivity airplane-mode enable'; else
      $ADB shell svc wifi disable >>"$OUT/harness.log" 2>&1
      $ADB shell svc data disable >>"$OUT/harness.log" 2>&1
      method='svc wifi/data disable (airplane-mode verification failed)'
    fi
  fi
  echo "$wanted,$current,$method" >> "$OUT/network-methods.csv"
}

record_start() {
  local variant=$1 network=$2 kind=$3 n=$4 package=$5 runlog="$OUT/logcat/${variant}-${network}-${kind}-${n}.log"
  $ADB logcat -c >>"$OUT/harness.log" 2>&1
  if [[ "$kind" == cold ]]; then $ADB shell am force-stop "$package" >>"$OUT/harness.log" 2>&1; else $ADB shell input keyevent HOME >>"$OUT/harness.log" 2>&1; sleep 1; fi
  local result; result=$($ADB shell am start -W -n "$package/$ACTIVITY" 2>&1)
  printf '%s\n' "$result" > "$OUT/starts/${variant}-${network}-${kind}-${n}.txt"
  sleep 2
  $ADB logcat -d -v threadtime > "$runlog" 2>&1
  cat "$runlog" >> "$OUT/logcat/${variant}.full.log"
  local total wait this displayed
  total=$(printf '%s\n' "$result" | sed -n 's/^TotalTime: //p' | tail -1)
  wait=$(printf '%s\n' "$result" | sed -n 's/^WaitTime: //p' | tail -1)
  this=$(printf '%s\n' "$result" | sed -n 's/^ThisTime: //p' | tail -1)
  displayed=$(rg 'Displayed .*org\.lichess\.mobileV2' "$runlog" || true)
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$variant" "$network" "$kind" "$n" "${total:-NA}" "${wait:-NA}" "${this:-NA}" >> "$OUT/starts.csv"
  printf '%s\n' "$displayed" >> "$OUT/logcat/${variant}-displayed-lines.log"
}

screenshots_and_memory() {
  local variant=$1 package=$2
  $ADB logcat -c >>"$OUT/harness.log" 2>&1
  $ADB shell am force-stop "$package" >>"$OUT/harness.log" 2>&1
  $ADB shell am start -W -n "$package/$ACTIVITY" > "$OUT/starts/${variant}-screenshot-cold.txt" 2>&1
  local elapsed=0 point
  for point in 1 3 6 10; do
    sleep $((point - elapsed)); elapsed=$point
    $ADB exec-out screencap -p > "$OUT/screenshots/${variant}-${point}s.png" 2>>"$OUT/harness.log" || true
  done
  $ADB shell dumpsys meminfo "$package" > "$OUT/meminfo/${variant}-10s.txt" 2>&1
}

screen_walk() {
  local variant=$1 package=$2 width height i x tab dump bounds
  width=$($ADB shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\)/\1/p' | tail -1); height=$($ADB shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\)/\2/p' | tail -1)
  if [[ ! "$width" =~ ^[0-9]+$ || ! "$height" =~ ^[0-9]+$ ]]; then echo "$variant,unreliable,screen size unavailable" >> "$OUT/walk-status.csv"; return; fi
  for i in 0 1 2; do
    tab=(home puzzles more); x=$(( width * (2 * i + 1) / 6 ))
    $ADB shell dumpsys gfxinfo "$package" reset >>"$OUT/harness.log" 2>&1
    $ADB shell input tap "$x" $((height - 70)) >>"$OUT/harness.log" 2>&1; sleep 3
    $ADB shell dumpsys gfxinfo "$package" > "$OUT/gfxinfo/${variant}-${tab[$i]}.txt" 2>&1
    echo "$variant,${tab[$i]},tap x=$x y=$((height - 70))" >> "$OUT/walk-status.csv"
  done
  # Best effort only: inspect accessibility text, then tap a visible Palette/Theme control if present.
  $ADB shell uiautomator dump /sdcard/perf-window.xml >>"$OUT/harness.log" 2>&1
  $ADB pull /sdcard/perf-window.xml "$OUT/gfxinfo/${variant}-palette-window.xml" >>"$OUT/harness.log" 2>&1
  dump="$OUT/gfxinfo/${variant}-palette-window.xml"
  bounds=$(sed -n 's/.*\(Palette\|Theme\).*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]\".*/\2 \3 \4 \5/p' "$dump" | head -1)
  if [[ -n "$bounds" ]]; then
    read -r x1 y1 x2 y2 <<< "$bounds"; $ADB shell input tap $(((x1+x2)/2)) $(((y1+y2)/2)) >>"$OUT/harness.log" 2>&1
    echo "$variant,attempted,accessibility Palette/Theme control" >> "$OUT/palette-status.csv"
  else echo "$variant,not reached,no Palette/Theme accessibility text found" >> "$OUT/palette-status.csv"; fi
}

trace_startup() {
  local variant=$1
  timeout 90 flutter run --profile --trace-startup -d "${ANDROID_SERIAL:-emulator-5554}" --no-pub > "$OUT/trace/${variant}.txt" 2>&1
  echo "$variant,exit=$? (best effort; timeout/non-zero is non-fatal)" >> "$OUT/trace/status.csv"
}

printf 'variant,network,kind,run,total_ms,wait_ms,this_ms\n' > "$OUT/starts.csv"
printf 'requested,airplane_mode_setting,method\n' > "$OUT/network-methods.csv"
for apk in "$ARTIFACT_DIR"/*.apk; do
  [[ -f "$apk" ]] || continue
  base=$(basename "$apk")
  case "$base" in app-debug.apk) variant=debug; package=$PACKAGE_DEBUG;; app-profile.apk) variant=profile; package=$PACKAGE_PROFILE;; *) continue;; esac
  note "Installing $variant: $apk"
  $ADB install -r -g "$apk" >>"$OUT/harness.log" 2>&1 || { echo "$variant,install failed" >> "$OUT/install-status.csv"; continue; }
  : > "$OUT/logcat/${variant}.full.log"; : > "$OUT/logcat/${variant}-displayed-lines.log"
  for network in on off; do
    set_network "$network"
    for ((n=1; n<=RUNS; n++)); do record_start "$variant" "$network" cold "$n" "$package"; done
    for ((n=1; n<=RUNS; n++)); do record_start "$variant" "$network" warm "$n" "$package"; done
  done
  set_network on
  screenshots_and_memory "$variant" "$package"
  screen_walk "$variant" "$package"
  trace_startup "$variant"
done

{
  echo '## Android emulator performance measurements'
  echo
  echo "- Requested samples per condition: $RUNS"
  echo "- Cache handling: $cache_status"
  echo '- Emulator figures are comparison data, not real-device timings.'
  echo '- Network method and verification: `network-methods.csv` artifact.'
  echo
  echo '### Startup TotalTime (ms)'
  echo '| Variant | Network | Start | Median | Min | Max | Samples |'
  echo '| --- | --- | --- | ---: | ---: | ---: | ---: |'
  awk -F, 'NR>1 && $5 ~ /^[0-9]+$/ { k=$1 SUBSEP $2 SUBSEP $3; a[k]=a[k] " " $5; c[k]++ } END { for (k in a) { n=split(a[k],v," "); delete w; j=0; for(i=1;i<=n;i++)if(v[i]!="")w[++j]=v[i]; for(i=1;i<=j;i++)for(l=i+1;l<=j;l++)if(w[i]>w[l]){t=w[i];w[i]=w[l];w[l]=t}; split(k,p,SUBSEP); med=w[int((j+1)/2)]; if(j%2==0)med=(w[j/2]+w[j/2+1])/2; printf "| %s | %s | %s | %s | %s | %s | %d |\n",p[1],p[2],p[3],med,w[1],w[j],j } }' "$OUT/starts.csv" | sort
  echo
  echo '### Screen walk jank (gfxinfo)'
  echo '| Variant | Tab | Total frames | Janky frames | Janky percent | 50th | 90th | 95th | 99th |'
  echo '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
  for f in "$OUT"/gfxinfo/*.txt; do
    [[ -f "$f" ]] || continue; name=$(basename "$f" .txt); total=$(sed -n 's/.*Total frames rendered: \([0-9]*\).*/\1/p' "$f" | head -1); jank=$(sed -n 's/.*Janky frames: \([0-9]*\) (\([^)]*\)).*/\1|\2/p' "$f" | head -1); p50=$(sed -n 's/.*50th percentile: \(.*\)/\1/p' "$f" | head -1); p90=$(sed -n 's/.*90th percentile: \(.*\)/\1/p' "$f" | head -1); p95=$(sed -n 's/.*95th percentile: \(.*\)/\1/p' "$f" | head -1); p99=$(sed -n 's/.*99th percentile: \(.*\)/\1/p' "$f" | head -1); janky_frames=${jank%%|*}; janky_percent=${jank#*|}; [[ "$jank" == *'|'* ]] || { janky_frames=NA; janky_percent=NA; }; printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "${name%-*}" "${name##*-}" "${total:-NA}" "$janky_frames" "$janky_percent" "${p50:-NA}" "${p90:-NA}" "${p95:-NA}" "${p99:-NA}"; done
  echo
  echo '### Memory at 10 seconds after cold launch'
  echo '| Variant | TOTAL PSS | TOTAL RSS |'
  echo '| --- | ---: | ---: |'
  for f in "$OUT"/meminfo/*.txt; do [[ -f "$f" ]] || continue; total=$(sed -n 's/^.*TOTAL[[:space:]]*\([0-9]*\)[[:space:]]*\([0-9]*\).*/\1|\2/p' "$f" | tail -1); pss=${total%%|*}; rss=${total#*|}; [[ "$total" == *'|'* ]] || { pss=NA; rss=NA; }; printf '| %s | %s | %s |\n' "$(basename "$f" -10s.txt)" "$pss" "$rss"; done
  echo
  echo 'Raw am start output (including WaitTime/ThisTime), full per-variant logcat, Displayed-line extracts, screenshots, meminfo, gfxinfo, UI dumps, and trace attempts are downloadable in the artifact.'
} > "$SUMMARY"

exit 0
