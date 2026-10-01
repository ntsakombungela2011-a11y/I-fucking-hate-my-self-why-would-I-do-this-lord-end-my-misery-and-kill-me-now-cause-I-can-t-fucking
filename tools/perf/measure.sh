#!/usr/bin/env bash
# Measurement-only Android emulator harness. It intentionally does not alter app source or data.
set +e

ARTIFACT_DIR=${1:-perf-artifacts/apks}
RUNS=${2:-5}
OUT=perf-artifacts
PACKAGE_DEBUG=org.lichess.mobileV2.debug
PACKAGE_PROFILE=org.lichess.mobileV2
PROFILE_ACTIVITY=
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
  local component="$package/$PROFILE_ACTIVITY" result
  note "Launching component: $component"
  result=$($ADB shell am start -W -n "$component" 2>&1)
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
  if [[ "$kind" == cold ]]; then extract_startup_trace "$variant" "$network" "$n" "$runlog"; fi
}

extract_startup_trace() {
  local variant=$1 network=$2 n=$3 runlog=$4 line label elapsed
  while IFS= read -r line; do
    if [[ $line =~ BPC_STARTUP[[:space:]]+(.+)[[:space:]]+([0-9]+)[[:space:]]*$ ]]; then
      label=${BASH_REMATCH[1]}
      elapsed=${BASH_REMATCH[2]}
      printf '%s,%s,%s,%s,%s\n' "$variant" "$network" "$n" "$label" "$elapsed" >> "$OUT/startup-trace.csv"
    fi
  done < <(rg 'BPC_STARTUP[[:space:]]+' "$runlog" || true)
}

screenshots_and_memory() {
  local variant=$1 package=$2
  $ADB logcat -c >>"$OUT/harness.log" 2>&1
  $ADB shell am force-stop "$package" >>"$OUT/harness.log" 2>&1
  local component="$package/$PROFILE_ACTIVITY"
  note "Launching component: $component"
  $ADB shell am start -W -n "$component" > "$OUT/starts/${variant}-screenshot-cold.txt" 2>&1
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
printf 'variant,network,run,label,elapsed_ms\n' > "$OUT/startup-trace.csv"
for base in app-profile.apk app-debug.apk; do
  apk="$ARTIFACT_DIR/$base"
  [[ -f "$apk" ]] || continue
  case "$base" in app-debug.apk) variant=debug; package=$PACKAGE_DEBUG;; app-profile.apk) variant=profile; package=$PACKAGE_PROFILE;; *) continue;; esac
  note "Installing $variant: $apk"
  $ADB install -r -g "$apk" >>"$OUT/harness.log" 2>&1 || { echo "$variant,install failed" >> "$OUT/install-status.csv"; continue; }
  if [[ "$variant" == profile ]]; then
    resolved=$($ADB shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$PACKAGE_PROFILE" 2>>"$OUT/harness.log" | tr -d '\r' | tail -1)
    if [[ "$resolved" != "$PACKAGE_PROFILE/"* ]]; then
      note "Unable to resolve profile launcher activity: ${resolved:-no result}"
      continue
    fi
    PROFILE_ACTIVITY=${resolved#*/}
    note "Resolved profile launcher activity: $PROFILE_ACTIVITY"
  fi
  if [[ -z "$PROFILE_ACTIVITY" ]]; then
    note 'Debug measurement skipped because the profile launcher activity was not resolved.'
    continue
  fi
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
  echo '### BPC startup trace (all cold runs)'
  echo '| Variant | Network | Run | Main start (ms) | First frame (ms) | Native splash removed (ms) | Home first build (ms) | Palette catalog load start (ms) | Palette catalog load end (ms) |'
  echo '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
  awk -F, '
    NR > 1 {
      run_key=$1 SUBSEP $2 SUBSEP $3
      sample_key=$1 SUBSEP $2 SUBSEP $4
      value[run_key SUBSEP $4]=$5
      samples[sample_key]=samples[sample_key] " " $5
      runs[run_key]=1
      groups[$1 SUBSEP $2]=1
    }
    function cell(key, label) { return ((key SUBSEP label) in value) ? value[key SUBSEP label] : "NA" }
    function median(values,    n,parts,i,j,t) {
      n=split(values, parts, " "); j=0
      for (i=1; i<=n; i++) if (parts[i] != "") parts[++j]=parts[i]
      if (!j) return "NA"
      for (i=1; i<=j; i++) for (n=i+1; n<=j; n++) if (parts[i] > parts[n]) { t=parts[i]; parts[i]=parts[n]; parts[n]=t }
      if (j % 2) return parts[(j + 1) / 2]
      return (parts[j / 2] + parts[j / 2 + 1]) / 2
    }
    function sample_median(group, label) { return median(samples[group SUBSEP label]) }
    END {
      split("main start|first frame|native splash removed|Home first build|palette catalog load start|palette catalog load end", labels, "|")
      for (key in runs) {
        split(key, part, SUBSEP)
        printf "| %s | %s | %s", part[1], part[2], part[3]
        for (i=1; i<=6; i++) printf " | %s", cell(key, labels[i])
        print " |"
      }
      for (group in groups) {
        split(group, part, SUBSEP)
        printf "| %s | %s | median", part[1], part[2]
        for (i=1; i<=6; i++) printf " | %s", sample_median(group, labels[i])
        print " |"
      }
    }
  ' "$OUT/startup-trace.csv" | sort -t '|' -k2,2 -k3,3 -k4,4V
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
