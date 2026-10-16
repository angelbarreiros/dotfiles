#!/usr/bin/env bash

set -u

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]//g'
}

read_cpu_sample() {
  awk '$1 == "cpu" || $1 ~ /^cpu[0-9]+$/ {
    printf "%s", $1
    for (i = 2; i <= NF; i++) printf " %s", $i
    printf "\n"
  }' /proc/stat
}

mapfile -t first_sample < <(read_cpu_sample)
sleep 0.15
mapfile -t second_sample < <(read_cpu_sample)

model="$(awk -F: '/^model name[[:space:]]*:/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }' /proc/cpuinfo)"
model_json="$(json_escape "$model")"

cpu_total=0
cores_json=""
for ((i = 0; i < ${#second_sample[@]}; i++)); do
  first="${first_sample[$i]:-}"
  second="${second_sample[$i]:-}"
  read -r label u n s idle io irq softirq steal _guest _guest_nice <<< "$first"
  read -r _label u2 n2 s2 idle2 io2 irq2 softirq2 steal2 _guest2 _guest_nice2 <<< "$second"

  total1=$((u + n + s + idle + io + irq + softirq + steal))
  total2=$((u2 + n2 + s2 + idle2 + io2 + irq2 + softirq2 + steal2))
  active1=$((total1 - idle - io))
  active2=$((total2 - idle2 - io2))
  delta_total=$((total2 - total1))
  delta_active=$((active2 - active1))
  usage="$(awk -v active="$delta_active" -v total="$delta_total" 'BEGIN {
    if (total <= 0) printf "0.0";
    else { value = 100 * active / total; if (value < 0) value = 0; if (value > 100) value = 100; printf "%.1f", value }
  }')"

  if [[ "$label" == "cpu" ]]; then
    cpu_total="$usage"
    continue
  fi

  core_id="${label#cpu}"
  frequency="$(awk -v wanted="$core_id" '
    /^processor[[:space:]]*:/ { current = $3 }
    /^cpu MHz[[:space:]]*:/ && current == wanted { print $4; exit }
  ' /proc/cpuinfo)"
  [[ -n "$frequency" ]] || frequency="0"

  core_json="{\"id\":$core_id,\"usage\":$usage,\"frequency\":$frequency}"
  if [[ -n "$cores_json" ]]; then cores_json+=","; fi
  cores_json+="$core_json"
done

mem_total_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
mem_available_kb="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)"
mem_used_kb=$((mem_total_kb - mem_available_kb))
swap_total_kb="$(awk '/^SwapTotal:/ { print $2; exit }' /proc/meminfo)"
swap_free_kb="$(awk '/^SwapFree:/ { print $2; exit }' /proc/meminfo)"
swap_used_kb=$((swap_total_kb - swap_free_kb))

memory_json="$(awk -v used="$mem_used_kb" -v total="$mem_total_kb" 'BEGIN {
  percent = total > 0 ? used * 100 / total : 0
  printf "{\"used\":%.2f,\"total\":%.2f,\"percent\":%.1f}", used / 1048576, total / 1048576, percent
}')"
swap_json="$(awk -v used="$swap_used_kb" -v total="$swap_total_kb" 'BEGIN {
  percent = total > 0 ? used * 100 / total : 0
  printf "{\"used\":%.2f,\"total\":%.2f,\"percent\":%.1f}", used / 1048576, total / 1048576, percent
}')"

temperatures_json=""
for hwmon in /sys/class/hwmon/hwmon*; do
  [[ -r "$hwmon/name" ]] || continue
  sensor_name="$(cat "$hwmon/name" 2>/dev/null || true)"
  for input in "$hwmon"/temp*_input; do
    [[ -r "$input" ]] || continue
    raw="$(cat "$input" 2>/dev/null || true)"
    [[ "$raw" =~ ^[0-9]+$ ]] || continue
    sensor_label="$(cat "${input%_input}_label" 2>/dev/null || true)"
    [[ -n "$sensor_label" ]] || sensor_label="$(basename "$input" _input)"
    sensor_label="$(json_escape "$sensor_name $sensor_label")"
    temperature="$(awk -v value="$raw" 'BEGIN { printf "%.1f", value / 1000 }')"
    temp_json="{\"name\":\"$sensor_label\",\"value\":$temperature}"
    if [[ -n "$temperatures_json" ]]; then temperatures_json+=","; fi
    temperatures_json+="$temp_json"
  done
done

load_json="$(awk '{ printf "[%.2f,%.2f,%.2f]", $1, $2, $3 }' /proc/loadavg)"
uptime="$(awk '{ print $1 }' /proc/uptime)"
driver="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || true)"
governor="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)"
profile_json="{}"
profile_script="$HOME/.config/hypr/scripts/tuxedo-profile.sh"
if [[ -x "$profile_script" ]]; then
  candidate="$("$profile_script" active 2>/dev/null || true)"
  [[ "$candidate" == \{*\} ]] && profile_json="$candidate"
fi

printf '{"model":"%s","total":%s,"cores":[%s],"memory":%s,"swap":%s,"temperatures":[%s],"load":%s,"uptime":%s,"frequency":{"driver":"%s","governor":"%s"},"profile":%s}\n' \
  "$model_json" "$cpu_total" "$cores_json" "$memory_json" "$swap_json" "$temperatures_json" "$load_json" "$uptime" \
  "$(json_escape "$driver")" "$(json_escape "$governor")" "$profile_json"
