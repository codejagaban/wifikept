# WiFiKept

A native macOS Wi-Fi monitor inspired by [Wifilicious](https://wifilicious.app), with one big addition: **data usage tracking** — how much you download/upload over Wi-Fi today, this week, this month, and all time.

Everything is computed and stored locally. The only network traffic the app originates is the speed test itself (Cloudflare).

## Features

- **Overview** — network at a glance: SSID, quality, live throughput chart, link rate, latency, today's usage
- **Signal** — quality gauge, RSSI / noise floor / SNR meters, channel, width, standard, link rate, TX power, BSSID
- **Speed** — Cloudflare speed test (4 parallel streams, ~6 s each way, slow-start excluded — fast.com-style methodology) with download/upload gauges, latency, DNS timing
- **Trends** — signal, link rate, latency, noise & SNR, throughput and channel sampled every 30 s, kept 90 days (1H / 6H / 1D / 7D / All)
- **Usage** — daily/weekly/monthly/all-time byte totals with a stacked bar chart (24H / 7D / 30D / 12M / All), kept forever
- **Details** — IPv4, IPv6, BSSID, gateway, MAC, interface, security, band, country code, all copyable
- **Menu bar** — live metric next to the Wi-Fi icon (configurable in Settings) plus a popover dashboard
- **Apple Intelligence** — each tab ends with a short insight paragraph generated on-device (macOS 26+ with Apple Intelligence enabled; falls back to built-in summaries otherwise)

## Build

```bash
./build.sh          # builds build/WiFiKept.app
./build.sh --run    # builds and launches
```

Requires Xcode 26+ on macOS 26+. The app is assembled from a Swift Package (no `.xcodeproj`) and ad-hoc signed for local use.

## First launch

- macOS will ask for **Location** access — this is how macOS gates Wi-Fi identifiers (SSID/BSSID) for every third-party Wi-Fi app. Your location is never read.
- Turn on **Launch at login** in Settings (gear icon) so usage totals stay complete.
- For AI insights, enable **Apple Intelligence** in System Settings.

## Data

Samples live in `~/Library/Application Support/WiFiKept/store.sqlite`:
- `usage` — one row per minute of rx/tx byte deltas (kept forever; a year is a few MB)
- `trend` — one row per 30 s of signal/latency/throughput readings (pruned after 90 days)
