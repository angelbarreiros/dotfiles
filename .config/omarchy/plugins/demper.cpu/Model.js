function emptyStats() {
  return {
    model: "",
    total: 0,
    cores: [],
    memory: { used: 0, total: 0, percent: 0 },
    swap: { used: 0, total: 0, percent: 0 },
    temperatures: [],
    load: [0, 0, 0],
    uptime: 0,
    frequency: { driver: "", governor: "" },
    profile: { name: "" }
  }
}

function numberOr(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function parseStats(raw) {
  var parsed
  try {
    parsed = JSON.parse(String(raw || ""))
  } catch (error) {
    return null
  }

  if (!parsed || typeof parsed !== "object") return null

  var stats = emptyStats()
  stats.model = String(parsed.model || "")
  stats.total = numberOr(parsed.total, 0)
  stats.cores = Array.isArray(parsed.cores) ? parsed.cores : []
  stats.memory = parsed.memory || stats.memory
  stats.swap = parsed.swap || stats.swap
  stats.temperatures = Array.isArray(parsed.temperatures) ? parsed.temperatures : []
  stats.load = Array.isArray(parsed.load) ? parsed.load : stats.load
  stats.uptime = numberOr(parsed.uptime, 0)
  stats.frequency = parsed.frequency || stats.frequency
  stats.profile = parsed.profile || stats.profile
  return stats
}

function percent(value) {
  return Math.round(numberOr(value, 0)) + "%"
}

function gigabytes(value) {
  return numberOr(value, 0).toFixed(1) + " GB"
}

function frequency(value) {
  var mhz = numberOr(value, 0)
  if (mhz <= 0) return "—"
  return mhz >= 1000 ? (mhz / 1000).toFixed(2) + " GHz" : Math.round(mhz) + " MHz"
}

function temperature(value) {
  var celsius = numberOr(value, 0)
  return celsius > 0 ? celsius.toFixed(1) + " °C" : "—"
}

function uptime(value) {
  var seconds = Math.max(0, Math.floor(numberOr(value, 0)))
  var days = Math.floor(seconds / 86400)
  seconds %= 86400
  var hours = Math.floor(seconds / 3600)
  seconds %= 3600
  var minutes = Math.floor(seconds / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  return minutes + "m"
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyStats: emptyStats,
    parseStats: parseStats,
    percent: percent,
    gigabytes: gigabytes,
    frequency: frequency,
    temperature: temperature,
    uptime: uptime
  }
}
