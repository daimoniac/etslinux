# ETS5 under Wine with a RUDY-forwarded KNX licensing dongle

Runs KNX ETS5 under Wine on the workstation `workstation`, using the
physical ETS licensing stick that stays plugged into `dongle-host`. The stick is
re-exported over USB/IP by RUDY, integrated as a service in the existing
`compose-stack` Compose stack on `dongle-host`.

**Status:** the complete transport and Wine stack is built and verified.
ETS5 itself is **not yet installed** — the installer was not present on either
machine and must be supplied (see [Outstanding work](#outstanding-work)).

```
dongle-host (192.0.2.10)                        workstation
┌──────────────────────────────────┐        ┌──────────────────────────────────┐
│ compose-stack Compose project           │        │ ~/workspace/ets5-wine-rudy       │
│  └─ rudy-server (privileged)     │        │  └─ rudy-client (privileged)     │
│       usbip bind 2-2             │        │       usbip attach → vhci-hcd    │
│       usbipd :3240 ──────────────┼────────┼──> bus 005, usbhid, /dev/hidraw1 │
│  └─ mosquitto (self-heal topics) │◄───────┤       MQTT rudy/server/start     │
│                                  │        │                                  │
│ KNX License Stick 2a07:0102      │        │ Wine 11.19 (win64 prefix)        │
│   usbip-host, busid 2-2          │        │  └─ ETS5  [not yet installed]    │
└──────────────────────────────────┘        └──────────────────────────────────┘
```

---

## 1. System information

| | `workstation` (ETS runtime) | `dongle-host` (dongle host) |
|---|---|---|
| OS | Ubuntu 26.04.1 LTS (resolute) | Ubuntu 26.04.1 LTS (resolute) |
| Kernel | 7.0.0-38-generic | 7.0.0-38-generic |
| Arch | x86_64 (i7-13700H, 20 threads) | x86_64 |
| Docker | 29.0.4 | 29.0.4 |
| LAN | — | 192.0.2.10 / `dongle-host.example` |
| SSH | — | `ssh user@dongle-host.example` |
| Free disk | 419 GB on `/` | — |
| USB/IP role | client — `vhci-hcd` | server — `usbip-host` |

Both hosts run the same kernel, so the USB/IP protocol versions match.

## 2. Dongle identification

| Property | Value |
|---|---|
| VID:PID | `2a07:0102` |
| Manufacturer | KNX |
| Product | `License Stick KNX-STICK` |
| Serial | 12 characters, **redacted** — not needed in any config |
| Bus id on `dongle-host` | `2-2` (not pinned; moves on replug) |
| sysfs path | `/sys/devices/pci0000:00/0000:00:14.0/usb2/2-2` |
| Class | HID (vendor usage page `0xFF10`) |

`2a07:0102` is the **only** `2a07` device on `dongle-host`, so `VID:PID` identifies it
uniquely. No serial filter (`USBIP_DEVICE_IDS=VID:PID:SID`) and no
`USBIP_BUS_IDS` pinning is required — bus ids change across replug, device ids
do not.

The matching licence file is `ETS5 Lite-<id>-KNX-STICK.license`
(Google Drive → ``). The `KNX-STICK` in the
filename matches the stick's product string, so licence and dongle are a pair.
The licence tier is **ETS5 Lite**.

## 3. RUDY version

| | Image |
|---|---|
| Server | `ckware/rudy-server:2024-03-20-bookworm` <br> `sha256:2ce904479fb7dfd3809699e66fcf040752b0b1ff4e8958de9f5d227ef79d8b90` |
| Client | `ckware/rudy-client:2024-03-20-bookworm` <br> `sha256:2d0737d9d06fcf66d46273dbf54bc5813088dda25e75b7bf83bcf72655470307` |

`2024-03-20` is the newest RUDY release. Digest-pinned per the stack's existing
convention. Both publish `linux/amd64`, matching `dongle-host`.

## 4. Changes to the `compose-stack` stack on `dongle-host`

All changes are in the git repo `~/dongle-host` (branch `main`), **uncommitted** —
see [Committing](#committing).

### 4.1 `compose-stack/compose/home.yaml` — new `rudy-server` service

Appended to the existing `home.yaml` domain file (KNX is home-automation
hardware, alongside MQTT / Home Assistant). The root `docker-compose.yaml`
`include:` list, volumes, and networks are **unchanged**.

```yaml
  rudy-server:
    image: ckware/rudy-server:2024-03-20-bookworm@sha256:2ce9044...
    container_name: rudy-server
    init: true
    restart: unless-stopped
    privileged: true
    ports:
      - "192.0.2.10:3240:3240"
    env_file:
      - /home/user/.config/secrets/compose-stack/rudy-server.env
    environment:
      USBIP_DEVICE_IDS: "2a07:0102"
      MQTT_PUBLISH_TO_TOPIC: "rudy/server"
      MQTT_RELOAD_ON_TOPIC: "rudy/client/error/server"
      TZ: Europe/Berlin
    volumes:
      - /sys/bus/usb/drivers/usb:/sys/bus/usb/drivers/usb
      - /sys/bus/usb/drivers/usbip-host:/sys/bus/usb/drivers/usbip-host
      - /sys/devices:/sys/devices
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }
```

Three deliberate deviations from RUDY's published example are documented
inline in the file and explained in [section 8](#8-deviations-from-rudys-documented-example).

### 4.2 `compose-stack/etc-mosquitto/acl` — two new identities

```
user rudy-server
topic write rudy/server/#
topic read rudy/client/#

user rudy-client
topic write rudy/client/#
topic read rudy/server/#
```

Each side may only write its own branch and read the other's.

### 4.3 `compose-stack/scripts/test_compose_layout.py`

`rudy-server` added to the `home` group set, which the test asserts against.
Both project test suites pass:

```
python3 scripts/test_compose_layout.py     # OK (2 tests)
python3 scripts/test_paperless_network.py  # OK (3 tests)
```

### 4.4 Outside the repo

- **Broker credentials** — mosquitto users `rudy-server` and `rudy-client`
  added to `/home/user/.config/secrets/pi-gateway/passwords`
  (random 24-byte hex, PBKDF2).
- **Server MQTT options** — `/home/user/.config/secrets/compose-stack/rudy-server.env`,
  mode `600`. `mosquitto_pub`/`_sub` only accept the password inline (`-P`),
  so the entire option string is secret and must live in the vault, not in
  Compose.
- **Kernel module** — `/etc/modules-load.d/usbip.conf` containing `usbip-host`.
- **`passwords` file ownership** — changed from `600 user:user` to
  `640 user:1883`. This fixed a **pre-existing latent fault**, see
  [section 9](#9-incident-mosquitto-outage-during-setup).

### 4.5 Backups

`dongle-host:~/.local/share/ets5-rudy-backups/` (outside the repo, so `git status`
stays clean):

```
home.yaml.bak-<timestamp>
passwords.bak-<timestamp>
acl.bak-<timestamp>
```

## 5. Changes on the workstation

| Path | Purpose |
|---|---|
| `~/workspace/ets5-wine-rudy/docker-compose.yml` | `rudy-client` service |
| `~/workspace/ets5-wine-rudy/hidparent-probe.c` | ETS enumeration-chain probe |
| `~/.config/ets5-rudy/rudy-client.env` | MQTT options, mode `600` |
| `/etc/udev/rules.d/70-knx-ets-dongle.rules` | hidraw access for the dongle |
| `/etc/modules-load.d/vhci-hcd.conf` | loads `vhci-hcd` at boot |
| `/etc/apt/sources.list.d/winehq-resolute.sources` | WineHQ repo |
| `/etc/apt/keyrings/winehq-archive.gpg` | WineHQ signing key |
| `~/.local/share/wineprefixes/ets5` | dedicated Wine prefix |

### 5.1 udev rule — required

The forwarded stick arrives with a root-only `/dev/hidrawN`
(`crw------- root root`). Wine runs as `steve`, so **ETS5 would report no
dongle even though `lsusb` shows it**. `/etc/udev/rules.d/70-knx-ets-dongle.rules`:

```
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2a07", ATTRS{idProduct}=="0102", MODE="0660", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="2a07", ATTR{idProduct}=="0102", MODE="0660", GROUP="plugdev", TAG+="uaccess"
```

Scoped to this one VID:PID; no other USB or HID device is affected. Result:

```
crw-rw----+ 1 root plugdev 240, 1 /dev/hidraw1
user:steve:rw-                        # ACL from uaccess
```

`GROUP=plugdev` is the deterministic grant (`steve` is in `plugdev`, gid 46).
`uaccess` is belt-and-braces: the device hangs off
`/sys/devices/platform/vhci_hcd.0` and arrives tagged `seat` **without** an
`ID_SEAT`, so logind's ACL cannot be relied on alone.

### 5.2 Wine

| | |
|---|---|
| Package | `winehq-devel` `11.19~resolute-1` |
| Prefix | `~/.local/share/wineprefixes/ets5` |
| `WINEARCH` | `win64` (**forced**, see below) |
| Windows version | default (Wine 11 default, *not* XP) |
| mono/gecko | not yet installed — pending ETS5 |

**Why ≥ 11.11 is mandatory.** WineHQ bug
[59604](https://bugs.winehq.org/show_bug.cgi?id=59604), *"setupapi:
CM_Get_Parent stub breaks USB HID device identification"*, was filed against
**KNX ETS** and describes exactly this failure: `CM_Get_Parent` was a stub
returning `CR_NO_SUCH_DEVNODE`, so ETS could never walk from the HID interface
to its USB parent to read the VID/PID. Status `CLOSED/FIXED`, merged in
**Wine 11.10**. Ubuntu's archive only ships Wine 10.0, which still has the
stub — it cannot work.

**Why `win64` and not the historical 32-bit prefix.** The ETS 5.7.4 reports
(Wine 5.0.3, `WINEARCH=win32`, .NET 4.6.2, Windows XP mode) are not reproducible
here: WineHQ's `resolute` repo publishes **zero i386 packages**, and
`/opt/wine-devel/lib/wine/` contains `i386-windows` but no `i386-unix`. This is
a **new-WoW64** build, which runs 32-bit Windows binaries inside a 64-bit
prefix and cannot create a classic `win32` prefix at all. Verified working:
a 32-bit PE executes correctly under this prefix (section 6.3).

## 6. Verification

Each layer was verified separately so a later ETS5 failure can be attributed
precisely. **`lsusb` seeing the dongle was explicitly not treated as success.**

### 6.1 RUDY server — dongle exported

```
$ docker compose logs rudy-server
INFO : Resolved bus id 2-2 for device id '2a07:0102'
INFO : Binding 2-2
usbip: info: bind device on busid 2-2: complete
usbipd: info: exportable devices: 1
INFO :         2-2: unknown vendor : unknown product (2a07:0102)

$ docker exec rudy-server usbip list -r localhost
 - localhost
        2-2: ... (2a07:0102)
```

Exactly **one** device exported. Every other USB device on `dongle-host` kept its
driver (`btusb`, `uvcvideo`, `usb-storage`, hubs); only `2-2` moved from `usb`
to `usbip-host`.

### 6.2 Transport and local attach

```
$ usbip list -r dongle-host.example      # before any client
 - dongle-host.example
        2-2: ... (2a07:0102)

$ lsusb
Bus 005 Device 002: ID 2a07:0102 KNX License Stick KNX-STICK

$ lsusb -t
/:  Bus 005.Port 001: Dev 001, Class=root_hub, Driver=vhci_hcd/8p, 480M
    |__ Port 001: Dev 002, If 0, Class=Human Interface Device, Driver=usbhid, 12M
```

HID device `0003:2A07:0102.0002` and `/dev/hidraw1` are created on the **host**,
not merely inside the container.

### 6.3 Wine HID/PnP chain — the decisive test

Registry inference alone was not trusted. `hidparent-probe.c` is a 32-bit PE
(built with `i686-w64-mingw32-gcc`) replicating the exact sequence
`Knx.Falcon.UsbAccessWindows` uses:

```
$ WINEPREFIX=~/.local/share/wineprefixes/ets5 wine hidparent-probe.exe
Looking for USB parent VID_2A07&PID_0102

[0] HID  : HID\VID_2A07&PID_0102\2&14079D25&0&0000
     parent: USB\VID_2A07&PID_0102\513&REDACTED&0&0&0
     parsed: VID=2A07 PID=0102
     *** MATCH: this is the target dongle ***
     OPEN   : OK (\\?\hid#vid_2a07&pid_0102#...#{4d1e55b2-f16f-11cf-88cb-001111000030})

RESULT: dongle found via the full ETS enumeration chain
```

All five steps pass: `SetupDiGetClassDevs(GUID_DEVINTERFACE_HID)` →
`SetupDiEnumDeviceInterfaces` → **`CM_Get_Parent` returns the USB parent**
(not `CR_NO_SUCH_DEVNODE`) → `CM_Get_Device_ID` yields the right VID/PID →
`CreateFile` on the HID interface **succeeds**, which also proves the udev
permissions are correct.

Corroborated in the prefix registry:

```
HID\VID_2A07&PID_0102\2&14079d25&0&0000
  DEVPKEY_Device_Parent   = USB\VID_2A07&PID_0102\513&REDACTED&0&0&0
USB\VID_2A07&PID_0102\513&886b74f20913&0&0&0
  DEVPKEY_Device_Children = HID\VID_2A07&PID_0102\2&14079d25&0&0000
```

Rebuild and rerun:

```sh
cd ~/workspace/ets5-wine-rudy
i686-w64-mingw32-gcc -O1 -o hidparent-probe.exe hidparent-probe.c -lsetupapi -lcfgmgr32
WINEPREFIX=~/.local/share/wineprefixes/ets5 wine hidparent-probe.exe
```

### 6.4 Reconnection

| Scenario | Result |
|---|---|
| `docker compose restart rudy-server` (no MQTT) | **Broke.** Client kept a stale attachment, `lsusb` 0, probe failed |
| `docker exec rudy-client reload` | Recovered |
| `docker compose restart rudy-client` | Recovered |
| `docker compose restart rudy-server` (**with MQTT**) | **Self-healed in < 30 s, no manual action** |

The MQTT hook is the difference. Client log on self-heal:

```
INFO : Enabling reload hook on MQTT topic 'rudy/server/start'
INFO : Attached device 2-2 to port 0
```

Unrelated USB devices on the workstation (fingerprint reader, camera,
Bluetooth) were unaffected throughout.

## 7. Operating procedures

### Everyday checks

```sh
# workstation
lsusb | grep 2a07
sudo usbip port
docker logs --tail=30 rudy-client
WINEPREFIX=~/.local/share/wineprefixes/ets5 wine ~/workspace/ets5-wine-rudy/hidparent-probe.exe

# dongle-host
ssh user@dongle-host.example
cd ~/dongle-host/compose-stack
docker compose ps rudy-server
docker compose logs --tail=100 rudy-server
docker exec rudy-server usbip list -l
docker exec rudy-server usbip list -r localhost
```

### Manual reconnection

Normally unnecessary — MQTT self-heals. If needed, escalate in order:

```sh
docker exec rudy-client reload                  # 1. cheapest
docker compose restart rudy-client              # 2. (from ~/workspace/ets5-wine-rudy)
ssh user@dongle-host.example 'cd ~/dongle-host/compose-stack && docker compose restart rudy-server'
```

After physically replugging the stick on `dongle-host`, `rudy-server` rebinds by
`VID:PID`, so a changed bus id is handled automatically.

### Updating RUDY without touching other containers

Never run `docker compose down` on the stack. Update only this service:

```sh
ssh user@dongle-host.example
cd ~/dongle-host/compose-stack
cp -a compose/home.yaml ~/.local/share/ets5-rudy-backups/home.yaml.bak-$(date +%Y%m%d-%H%M%S)
# edit the rudy-server image digest in compose/home.yaml
docker compose config -q
python3 scripts/test_compose_layout.py
docker compose up -d --no-deps rudy-server      # --no-deps is essential
docker compose logs --tail=50 rudy-server
```

`--no-deps` plus naming the single service prevents Compose from recreating
any of the other 31 containers. Verify with `docker compose ps` that
`rudy-server` is the only recently-created container.

## 8. Deviations from RUDY's documented example

RUDY's published example is written for a Raspberry Pi and is wrong here in
three ways. Each was found empirically.

1. **`/sys/devices/platform` → `/sys/devices`.** The example mounts the
   platform subtree because a Pi's USB controller is a platform device. On this
   x86 host the stick is at `/sys/devices/pci0000:00/0000:00:14.0/usb2/2-2`;
   mounting the platform path would export nothing, and RUDY would start
   cleanly while never finding the stick. The in-container path must *equal*
   the host path because usbip resolves the sysfs symlink to it, but the Docker
   volume parser **rejects any bind path containing a colon**, even in long
   syntax:
   `invalid volume specification: '/sys/devices/pci0000:00:/sys/devices/pci0000:00:rw'`.
   `/sys/devices` is the narrowest colon-free ancestor — still narrower than
   the `/sys:/sys` RUDY's own README recommends.

2. **`usbip-host` must be loaded before the container's first start.**
   `/sys/bus/usb/drivers/usbip-host` does not exist until the module is loaded.
   Start the container first and Docker silently creates an *empty directory*
   at the bind source, after which binding can never work.

3. **`privileged: true` is genuinely required on the server, not only the
   client.** RUDY documents privileged mode for the client only. Here the
   documented server mounts are insufficient: the binds *are* `rw` and the
   container *is* root with the default capability set, yet writes fail with
   `Permission denied` and `usbip bind` dies at
   `error unbinding device 2-2 from driver`. The cause is AppArmor's
   `docker-default` profile, which denies `/sys/**` writes
   ([moby#22825](https://github.com/moby/moby/issues/22825)). Proven by a
   throwaway container: the identical write succeeds with
   `--security-opt apparmor=unconfined`.
   `security_opt: [apparmor=unconfined]` would be the narrower fix — it keeps
   the default capabilities, seccomp and device-cgroup limits — and
   `privileged: true` was chosen deliberately in preference to it.

## 9. Incident: mosquitto outage during setup

**Impact:** ~4.5 min of MQTT auth failures on `dongle-host`; Home Assistant needed a
restart. All services restored and verified.

**What happened.** After adding the two RUDY users, mosquitto was sent
`SIGHUP` to reload. It then logged
`Error: Unable to open pwfile "/mosquitto/secrets/passwords"` and denied every
client (`sma-em`, `onewire`, `gpio-mqtt`, `bsec-mqtt`, `ha`).

**Root cause — pre-existing, not caused by the edit.** Mosquitto opens its
password file as root at startup and then drops to uid 1883 (`mosquitto`). The
vaulted file was `600 user:user` (uid 1000), i.e. **unreadable by the
broker's own runtime uid**. Proven by testing the *backup* copy: it also failed
to read as `mosquitto`. The running broker had been serving from stale
in-memory credentials since 2026-10-11. **Any** restart or reload would have
triggered this; the SIGHUP merely exposed it. The password file itself was
never corrupted — all six original users remained byte-identical in hash
scheme and length.

Two theories were tested and rejected before the real cause was found: a
mangled password file (disproved by comparing users/hash formats against the
backup) and a stale single-file bind mount after `mosquitto_passwd` replaced
the inode (disproved — recreating the container did not help).

**Fix.** `chown user:1883` + `chmod 640` on the password file, then recreate
the container. The broker is now in a *better* state than before: it can
actually re-read its credentials, so future restarts are safe.

**Follow-up worth considering (not done):** `etc-mosquitto/acl` is
world-readable and mosquitto warns that future versions will refuse to load it.
Pre-existing and out of scope here.

## 10. Known limitations

- **ETS5 is not installed.** Everything beneath it is verified, but
  ETS5-specific behaviour — licence validation, Falcon USB access, .NET
  requirements — is untested. The probe proves the *platform* works, not
  that ETS5 is happy.
- **ETS5 needs .NET.** Neither `wine-mono` nor Microsoft .NET is installed yet.
  ETS 5.7 wants .NET Framework 4.6.2+. Installing real .NET in a new-WoW64
  prefix is less well-trodden than the old 32-bit route; `wine-mono` should be
  tried first.
- **No classic 32-bit prefix is possible** (section 5.2), so the historical
  ETS 5.7.4 recipe cannot be reproduced exactly.
- **`privileged: true` on both containers.** `apparmor=unconfined` would be
  narrower on the server.
- **The stick is unusable on `dongle-host` while bound** to `usbip-host`. That is
  inherent to USB/IP, and `dongle-host` has no use for it.
- **Single consumer.** USB/IP reservation is in the kernel; the stick cannot be
  attached by two clients at once. Do not run a native `usbip attach`
  alongside `rudy-client`.
- **No host-level autostart for `usbip port` state.** Host-side `usbip port`
  prints `libusbip: error: fopen` as non-root because `/run/vhci_hcd/port0` is
  `0700 root`. Cosmetic — use `sudo usbip port`.
- **USB/IP is unauthenticated and unencrypted.** Mitigated by binding to
  `192.0.2.10:3240` (LAN only, not all interfaces). Do not expose it beyond
  the LAN; tunnel over WireGuard if ever needed off-LAN.
- **MQTT credentials are stored in plaintext** in two `600` files, as
  `mosquitto_pub` accepts no other mechanism.

## 11. Rollback

### Workstation

```sh
cd ~/workspace/ets5-wine-rudy && docker compose down       # only rudy-client
sudo rm -f /etc/udev/rules.d/70-knx-ets-dongle.rules && sudo udevadm control --reload-rules
sudo rm -f /etc/modules-load.d/vhci-hcd.conf
sudo modprobe -r vhci_hcd                                  # detach first
rm -rf ~/.local/share/wineprefixes/ets5                    # prefix only; no others exist
sudo apt-get remove --purge winehq-devel wine-devel
sudo rm -f /etc/apt/sources.list.d/winehq-resolute.sources /etc/apt/keyrings/winehq-archive.gpg
sudo apt-get update
rm -f ~/.config/ets5-rudy/rudy-client.env
```

`docker compose down` here affects **only** this one-service project, never the
`compose-stack` stack.

### `dongle-host`

```sh
ssh user@dongle-host.example
cd ~/dongle-host/compose-stack

# 1. remove just this container
docker compose stop rudy-server && docker compose rm -f rudy-server

# 2. revert the tracked files
cd ~/dongle-host
git checkout -- compose-stack/compose/home.yaml compose-stack/etc-mosquitto/acl compose-stack/scripts/test_compose_layout.py
#    (or restore ~/.local/share/ets5-rudy-backups/home.yaml.bak-<ts>)

# 3. release the stick back to dongle-host
sudo modprobe -r usbip_host && sudo modprobe usbip-host     # or: usbip unbind -b 2-2
sudo rm -f /etc/modules-load.d/usbip.conf

# 4. drop the broker identities
cp -a ~/.local/share/ets5-rudy-backups/passwords.bak-<ts> \
      /home/user/.config/secrets/pi-gateway/passwords
rm -f /home/user/.config/secrets/compose-stack/rudy-server.env
docker compose up -d --no-deps --force-recreate mosquitto
```

**Do not** revert the password file to `600 user:user` — that restores the
latent fault from [section 9](#9-incident-mosquitto-outage-during-setup) and
the broker will fail on its next restart. Keep `640 user:1883`.

Never run `docker compose down` in `~/dongle-host/compose-stack`: it would stop all 32
containers. Do not delete Docker volumes or networks.

### Committing

The `dongle-host` changes are **uncommitted** on branch `main` of `~/dongle-host`. The
working tree also contains unrelated pre-existing modifications to
`compose-stack/etc-homeassistant/dashboards/energie.yaml`, which were left untouched —
stage selectively:

```sh
cd ~/dongle-host
git add compose-stack/compose/home.yaml compose-stack/etc-mosquitto/acl compose-stack/scripts/test_compose_layout.py
git commit -m "feat(compose-stack): export KNX ETS5 licence stick via RUDY USB/IP"
```

## Outstanding work

1. **Supply the ETS5 installer.** Not present on either machine; ETS5 is
   end-of-life and downloads require a my.knx.org login. The licence is
   **ETS5 Lite**, so a matching ETS5 installer is needed (ETS 5.7.x).
2. Install .NET support in the prefix (`wine-mono` first, then Microsoft .NET
   4.6.2 via winetricks if ETS5 refuses).
3. Install ETS5 into `~/.local/share/wineprefixes/ets5`, confirm it starts
   **without** licensing first.
4. Import the `.license` file and confirm ETS5 reads the dongle.
5. Re-verify after a Wine restart and after a RUDY reconnect.

If ETS5 still fails to see the stick once installed, the probe in section 6.3
already rules out RUDY, the USB/IP transport, Linux permissions and Wine's
HID/PnP enumeration — pointing at ETS5/Falcon or .NET, and the investigation
should start with `WINEDEBUG=+hid,+setupapi,+plugplay`.
