# ETS on Linux

![ETS 5.7 on Ubuntu: the application menu, the panel icon, and an open project](docs/ets5-on-linux.png)

Run KNX ETS 5 or ETS 6 under Wine, with the license stick either plugged into
this machine or forwarded from another Linux host over USB/IP
([RUDY](https://github.com/ckware/rudy)).

This repository installs nothing from KNX. You bring `Ets5Setup.exe` or
`Ets6Setup.exe` and the physical license stick. The scripts download only the
Microsoft .NET redistributables they need, and they check those downloads.

Tested on Ubuntu 26.04 with Wine 11.19, ETS 5.7.7 (file version
5.7.1428.39779), and ETS 6.4.1 (file version 6.4.8718.0). Wine must be at
least 11.10. Older Wine cannot walk from the HID interface to the USB parent
device, so ETS never sees the stick
([WineHQ bug 59604](https://bugs.winehq.org/show_bug.cgi?id=59604)).

## Workstation

```sh
sudo apt-get install -y make
make host          # Wine, fonts, vhci-hcd, udev
make prefix        # ~/.local/share/wineprefixes/ets5
make dotnet        # .NET Framework 4.8
make mscoree       # native mscoree and COM registration
make fonts
make ets ETS_SETUP=/path/to/Ets5Setup.exe
make verify
make desktop       # optional application-menu entry
make launch
```

`make launch` starts ETS 5 in its own session. Closing the terminal must not
close ETS. The window is up for real when the status bar names the license
tier that belongs to the stick, for example `ETS5 Lite`. `lsusb` showing
`2a07:0102` is only the transport.

## ETS 6

ETS 6.4.1 is the same WiX Burn bundle and the same 32-bit .NET 4.8 program.
Give it its own prefix so it does not share the ETS 5 one:

```sh
export WINEPREFIX=~/.local/share/wineprefixes/ets6
make prefix dotnet mscoree fonts
make ets ETS_SETUP=/path/to/Ets6Setup.exe
make verify
```

The installer name selects the product directory (`ETS6` for `Ets6Setup.exe`).
Set `ETS_MAJOR=6` if the file has been renamed. `make launch` and
`make desktop` still start ETS 5.

Log out and back in once after `make host` if it added your user to `plugdev`.

## Dongle on another machine

On the machine the stick is plugged into:

```sh
cp .env.example .env
# set USBIP_BIND_ADDRESS to that machine's LAN address, not 0.0.0.0
make host-server
make server-up
```

On the workstation, set `USBIP_SERVER` in `.env` to that machine and run
`make client-up`. Load `usbip-host` before the first server start. The
script does this. Do not run a native `usbip attach` at the same time as
`rudy-client`.

`make server-down` and `make client-down` stop only this compose project.

MQTT is optional. Set `MQTT_OPTIONS` in each machine's own `.env` (different
broker users). Empty means USB/IP without self-heal: after a server restart
you then run `docker exec rudy-client reload` yourself.

## What success looks like

`make verify` checks Wine, the prefix, .NET 4.8, native `mscoree`, and a
32-bit CLR program. After ETS is installed:

```sh
make verify-cctor
```

prints `cctor OK`. Then `make launch`. The status bar is the license check.
A `.license` file, if you have one, is imported from the ETS UI. Do not
commit it.

## Project file hashes

ETS 5 and ETS 6 keep a `.ets5hash` next to each hashed file in a ProjectStore
directory. The suffix and the recipe are the same on both; ETS 6 still writes
`.ets5hash`. `scripts/ets5hash.py` recomputes it from `Proj/@Id` and
`ProjInfo/@Guid` in the plaintext `P` file. `check` compares. `write`
replaces the companion after the file itself has been edited. Close ETS
first. The `.store` file is a separate check and is left alone.

Checked by editing a project, re-signing it, and opening it again in
ETS 5.7.7 and in ETS 6.4.1.

```sh
scripts/ets5hash.py check ~/.local/share/wineprefixes/ets5/drive_c/ProgramData/KNX/ETS5/ProjectStore/P-XXXX
scripts/ets5hash.py check ~/.local/share/wineprefixes/ets6/drive_c/ProgramData/KNX/ETS6/ProjectStore/P-XXXX
scripts/ets5hash.py write ~/.local/share/wineprefixes/ets5/drive_c/ProgramData/KNX/ETS5/ProjectStore/P-XXXX
```

## Layout

| Path | Role |
|---|---|
| `scripts/00-host.sh` | Packages, WineHQ repo, kernel module, udev |
| `scripts/10-prefix.sh` | win64 prefix |
| `scripts/20-dotnet.sh` | .NET 4.8 |
| `scripts/30-mscoree.sh` | Microsoft `mscoree.dll` and COM keys |
| `scripts/40-fonts.sh` | WPF font fallback |
| `scripts/50-ets.sh` | ETS installer |
| `scripts/60-verify.sh` | Checkpoints |
| `bin/ets5` | Detached launcher |
| `compose/client` | `rudy-client` |
| `compose/server` | `rudy-server` |
| `probe/hidparent-probe.c` | HID parent-chain probe |
| `scripts/ets5hash.py` | Recompute ProjectStore `.ets5hash` files (ETS 5 and 6) |

`AGENTS.md` is the runbook for repeating this unattended, including the
failures that look like success.

## Removing it

```sh
make client-down          # workstation
make server-down          # dongle host
rm -rf ~/.local/share/wineprefixes/ets5
sudo rm -f /etc/udev/rules.d/70-knx-ets-dongle.rules
```

That does not remove Wine, and it does not stop any other Docker project.
