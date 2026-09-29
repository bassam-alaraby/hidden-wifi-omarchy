# hidden-wifi

A tiny interactive Bash script that connects to a **hidden Wi-Fi network** (non-broadcast SSID) using NetworkManager.

Made for [Omarchy](https://omarchy.org) (Quattro / NetworkManager-based releases), where the built-in Wi-Fi panel only lists networks it can scan, so a hidden SSID never shows up.

It asks for the SSID, password and security type, creates the profile, connects, and explains what went wrong if it fails.

## Requirements

- NetworkManager (`nmcli`). Omarchy versions that use `iwd`/`impala` are not supported; `impala` v0.7.0+ and `iwctl station <device> connect-hidden "<ssid>"` cover that case.
- A Wi-Fi network using WPA/WPA2 Personal or WPA3 Personal. Enterprise (802.1X) and open networks are not handled.

## Install

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/bassam-alaraby/hidden-wifi/main/hidden-wifi -o ~/.local/bin/hidden-wifi
chmod +x ~/.local/bin/hidden-wifi
```

If `hidden-wifi` is not found afterwards, add this to `~/.bashrc` and run `source ~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```
$ hidden-wifi
Network name (SSID): MyHiddenNetwork
Password: ********
Security [wpa2/wpa3] (Enter = wpa2):
Connected to MyHiddenNetwork.
```

You only need to do this once per network. The profile is saved with autoconnect enabled, so the machine reconnects on its own whenever the network is in range.

## What it does

1. Finds your Wi-Fi device automatically.
2. Deletes any old saved profile with the same name, so re-running it with a corrected password just works.
3. Creates a profile with `wifi.hidden yes`.
4. Brings the connection up.
5. If that fails, deletes the profile it just created so no broken profile is left behind, and prints a hint.

It is a wrapper around a plain `nmcli` command, roughly:

```bash
nmcli connection add type wifi ifname <device> con-name "<ssid>" ssid "<ssid>" \
  wifi.hidden yes wifi-sec.key-mgmt wpa-psk wifi-sec.psk "<password>"
nmcli connection up "<ssid>"
```

## Why not `nmcli device wifi connect ... hidden yes`?

That command first looks for the SSID in the scan results, and a hidden network is not there, so it can fail with `No network with SSID '...' found` even when everything you typed is correct. Creating the profile explicitly avoids the scan lookup.

## Troubleshooting

| Message | Likely cause |
|---|---|
| `wrong password, or wrong security type` | Typo in the password (check `@` vs `&`, `0` vs `O`, `l` vs `1`), or the router uses WPA3, so try `wpa3` |
| `network not found` | Wrong SSID (case and spaces matter) or out of range |
| `no Wi-Fi device found` | Wi-Fi is off or the driver is missing; try `nmcli radio wifi on` |

For details, watch the log while connecting:

```bash
journalctl -u NetworkManager -f
```

A line like `psk mismatch reported by supplicant` means the network was found and the password was rejected.

## Notes

- The password is shown on screen as you type, on purpose, so you can catch typos.
- It is passed to `nmcli` as an argument, so it is briefly visible in the process list on the local machine. Fine on a personal laptop, but keep it in mind on shared systems.
- If it fails and you pressed `Ctrl+C` early, just run it again.

## Status of native support

There is an open pull request adding a "Join hidden network" form to Omarchy's Wi-Fi panel: [omacom/omarchy#7828](https://github.com/omacom/omarchy/pull/7828). Once that lands, this script will no longer be needed.

## License

MIT