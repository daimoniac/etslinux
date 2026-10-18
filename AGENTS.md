# Agent runbook

Reproduce this setup in order. Do not skip a checkpoint because a later
installer returned exit code 0. Several of them do that when they have not
installed anything.

Do not commit a `.license` file, a `.env` file, broker passwords, or a dongle
serial. Do not invent a license, a dongle emulator, or a registry patch whose
purpose is to skip the license check. The stick is the license.

Do not run `docker compose down` against a compose project this repository
did not create. `make client-down` and `make server-down` are the only stop
commands.

## Order

Run from the repository root. The prefix defaults to
`~/.local/share/wineprefixes/ets5`. Override with `WINEPREFIX`.

1. `make host` on the workstation. `make host-server` on the dongle host.
2. `make prefix`
3. `make dotnet`
4. `make mscoree`
5. `make fonts`
6. `make ets ETS_SETUP=/absolute/path/to/Ets5Setup.exe` (or `Ets6Setup.exe` in its own prefix)
6a. `make eibasc`, optional, only needed to download a device whose Application
    Program ships an ETS3-style Baggage plugin (see Pitfalls)
7. `make verify` and then `make verify-cctor`
8. Attach the stick (`make server-up` and `make client-up`, or plug it in).
9. `make launch`
10. Optional: `make desktop`, `make probe`

Each script is safe to re-run. They refuse to edit the prefix while
`ETS5N.exe` or `ETS6N.exe` is running. `ETS_REINSTALL=1` is required to run
the installer again once `ETS5.exe` or `ETS6.exe` exists. ETS 6 goes in
`~/.local/share/wineprefixes/ets6`; the default prefix stays the ETS 5 one.

## Versions

| Piece | Rule |
|---|---|
| Wine | `winehq-stable` when its candidate is >= 11.10, otherwise `winehq-devel`. 11.19 is the tested devel build. 11.0 is too old. |
| Prefix | `WINEARCH=win64` only. These WineHQ packages are new WoW64 and have no i386 debs. |
| .NET | 4.8 offline installer. Release value must be 528049 on both the native and Wow6432Node keys. |
| ETS | 5.7.7 (file version 5.7.1428.39779) and 6.4.1 (file version 6.4.8718.0). Both installers are WiX Burn bundles the user supplies. They are not downloaded and not checksummed. |
| RUDY | `ckware/rudy-server` and `ckware/rudy-client`, tag `2024-03-20-bookworm`, digest-pinned in the compose files. |
| Stick | USB VID:PID `2a07:0102`. Do not pin a bus id. Do not put the serial in a file. |

Microsoft download URLs and SHA-256 sums live in `scripts/lib.sh`. A mismatch
is a failed download, not a warning.

## Checkpoints

| After | Pass |
|---|---|
| `make host` | `wine --version` is >= 11.10. `lsmod` shows `vhci_hcd` on the workstation or `usbip_host` on the dongle host. |
| `make prefix` | `system.reg` contains `#arch=win64`. |
| `make dotnet` | Both Release values are >= 528049, and the prefix then reports Windows 10. |
| `make mscoree` | `file` on `system32/mscoree.dll` and `syswow64/mscoree.dll` does not say `for WINE`. `HKCU\Software\Wine\DllOverrides` has `mscoree=native`. Both InstallRoot values exist. |
| `make verify` | The line `ok  32-bit CLR` and the program prints `CLR OK`. |
| `make verify-cctor` | The line `cctor OK`. |
| `make eibasc` | `Common Files\EIBA sc\EIBA.Interop.EtecDOM.dll`, `ETS5\EtecRedirect.dll.manifest`, and `ETS5\EIBA.Interop.EtecDOM.dll` all exist. |
| `make probe` | Built with `i686-w64-mingw32-gcc`. Under the prefix it prints `RESULT: dongle found via the full ETS enumeration chain` and `OPEN   : OK`. |
| `make launch` | The ETS window is still mapped after the launching shell has exited. The status bar names the license tier. |

`lsusb` listing `2a07:0102` is not one of these.

## Pitfalls

**.NET 4.8 on Windows 10 returns success and installs nothing.** Wine reports
build 19045. The installer treats that as an OS that already contains 4.8.
`scripts/20-dotnet.sh` switches the prefix to Windows 7 first and checks the
Release key afterwards. If you run the installer by hand on Windows 10, a
zero exit code is not evidence.

**Wine's `mscoree.dll` is not .NET.** It is a builtin that says Wine Mono is
not installed. The ETS bootstrapper then plans no packages and still exits 0.
`scripts/30-mscoree.sh` copies Microsoft's DLL out of the .NET 4.0
`netfx_Core` MSIs (the 4.8 tree does not replace this file). The bytes
are in `netfx_Core.mzz`; the MSI Media table calls that cabinet
`netfx_core.mzz`, and msiextract only opens the table's spelling. The
script sets the `native` override and InstallRoot. Without InstallRoot, `csc.exe`
opens a dialog: "mscoree.dll could not be loaded... Please reinstall the
.NET Framework." That dialog is stale if the CLR check already printed
`CLR OK`.

**COM registration is a second, separate failure.** After native `mscoree`
is in place, `Knx.Ets.Ets5.App`'s static constructor throws
`REGDB_E_KEYMISSING` (0x80040152) and then, once `InprocServer32` has a
default, `REGDB_E_CLASSNOTREG` (0x80040154). The missing data is the .NET 4
class registration, in particular each class's `Server` value. The 4.8
installer does not write it. `scripts/import_dotnet40_com.py` imports the
missing rows from those same MSIs. Re-running `make verify-cctor` is the
test. Do not reinstall ETS to chase this.

**A device download fails with "The type initializer for 'wx' threw an
exception" and the ETS log blames EtecRedirection with
`Resource name not found (0x80070716)`.** The Application Program for that
device ships an ETS3-style "Baggage" plugin (for example `FastDownload.dll`,
visible only as `BFastDownload.dll` under the ProjectStore and briefly as
plain `FastDownload.dll` under
`AppData\Local\Temp\KNX\CvNext\<guid>\<manufacturer>\Baggages\`). Loading it
needs `EIBA.Interop.EtecDOM` (and `EtecFwk`/`EtecHawk`), the .NET side of
ETS's ETS3 compatibility layer, which the ETS5 Burn bundle carries as its own
MSI, "KNX ETS5 Compatibility Components"
(`{070C17B5-D0DB-443A-9504-0AF04FE91F1E}`, built from WiX merge modules,
cached under `drive_c/windows/Installer/*.msi`). That MSI registers itself
as installed, but nothing it owns actually lands on disk.
`wine msiexec /i` against the cached MSI also "succeeds" and still writes
nothing — its `InstallExecuteSequence` runs under Wine's own `msi.dll`
without placing a single file. `scripts/35-eibasc.sh` pulls the files out
of the cabinet with `msiextract` instead. That alone is not enough. The
0x80070716 comes from `CreateActCtx` inside
`EtecRedirection`'s static constructor: it asks `EtecRedirect.dll` for
manifest resource 1, the DLL only contains resource 2, and the sidecar
`EtecRedirect.dll.manifest` (the fallback both Windows and Wine use for
resource 1) was never installed. The script writes that sidecar so the
context resolves `EtecFwk`, `EtecDom`, `Hawk`, `EtecCtrl` and `Falcon`.
Fusion then loads `EIBA.Interop.EtecDOM` 1.0.3135.0 by strong name from
the ETS application directory, not from `Common Files\EIBA sc`, so the
script copies the Interop assemblies there too. The ETS log is
`AppData\Local\KNX\ETS5\Log\ETS5.log`. Without this, ETS never gets as
far as the device's application. The next failure, once the plugin itself
loads, is inside `ConstructEtecDomObjectModel`: it CoCreates `DomRoot`
(`{6039BD3D-A8AC-11D4-B36F-00104B091E6B}`) and then `EagleDomPersist`
(`{4C846FA7-1BC6-4023-9CAC-EE57191A9B11}`) out of `EtecDOM.dll`. That DLL's
`DllGetClassObject` returns `E_UNEXPECTED` (0x8000FFFF) because its ATL
object map stays at `cbSize == 0`. Wine loads the mixed DLL through
`mscoree!_CorDllMain` and never runs the native C++ static constructors
that would fill the map. The download then dies with
`Value cannot be null. Parameter name: type` from `Activator.CreateInstance`.
`scripts/35-eibasc.sh` patches this exact `EtecDOM.dll` (ETS 5.7.1428) so
the class lookup initializes the map on first use. A different ETS build
does not match the patched bytes and the script refuses to touch the DLL.

**Menus and tooltips are black rectangles.** Two separate causes, both
fixed by `make fonts`. Plain Win32 layered windows (classic tooltips,
`TrackPopupMenu`) come out solid black under a compositor (this
machine's KDE session, through XWayland) because of Wine's XShape-based
layering; setting `ShapeLayeredWindows` to `N` under
`HKCU\Software\Wine\X11 Driver` fixes those. ETS5's own menus and
tooltips are WPF `Popup` controls, which render through a completely
different path (Avalon's Direct3D-backed compositing) and are
unaffected by that setting — they stay black until WPF's hardware
acceleration is disabled with `DisableHWAcceleration` (REG_DWORD, `1`)
under `HKCU\Software\Microsoft\Avalon.Graphics`, which forces WPF onto
its CPU software rasterizer (Wine bug 49055). The prefix has to be
restarted before an already-running ETS sees either change.

**Text is too small and soft.** With fractional scaling on KDE Wayland
(this laptop: 1.2), XWayland clients are expected to scale themselves,
and the desktop publishes the factor as `Xft.dpi` (115 here). Wine
ignores that and stays at 96 DPI. `bin/ets5` copies `Xft.dpi` into
`LogPixels` under `HKCU\Control Panel\Desktop` on every start
(`ETS5_DPI` overrides it). The prefix's desktop process keeps the DPI it
was started with, so after a change the launcher waits for the
wineserver to exit before it starts ETS; without that the first start
still comes up small. `make fonts` also switches font smoothing to
ClearType, because WPF's grayscale smoothing makes small labels look
blurry at 1.2. Bitmap icons stay slightly soft at any non-integer
factor; that is not fixable from the prefix.

**The panel shows a blank page for ETS.** The window class is `ets5n.exe`.
Wine's menu entry says `ets5.exe`, so the panel has no icon to use, and the
SVG alone is not used at panel size. `make desktop` copies Wine's extracted
PNGs to `ets5.png`, points both entries at `ets5n.exe`, and adds a
`NoDisplay` file named `ets5n.exe.desktop` for the Wayland app id.

**The window flashes and the process is gone.** WPF calls
`Environment.FailFast` from `TypefaceMap.MapUnresolvedCharacters` when font
fallback names Segoe UI and the face is not installed. `make fonts` points
those names at Carlito, Liberation Sans, and Droid Sans Fallback. Separately,
`wine ETS5.exe` dies when its parent shell hangs up. `bin/ets5` uses
`setsid`. Do not "fix" a flash by killing `wineserver` while an installer
is still running; that aborts the installer. `wineserver -k` is only for
after `winecfg -v`, which leaves `winedevice` holding the server open.

**USB/IP.** `privileged: true` is required. AppArmor's `docker-default`
profile denies `/sys` writes even as root in the container, and that write
is how the device is bound. Compose rejects a bind path that contains a
colon, so the server mounts `/sys/devices` rather than the PCI path of the
stick. Load `usbip-host` before the first `make server-up`. Publish port
3240 on a LAN address from `.env`, never on `0.0.0.0`. The udev rule is
what lets the desktop user open `/dev/hidraw`; without it ETS says there
is no dongle.

**Do not attach the stick twice.** `rudy-client` owns the vhci port. A
native `usbip attach` beside it will fight over the same device.

**Installer scope.** `make ets` is a quiet Burn install. Confirm
`drive_c/Program Files (x86)/ETS5/ETS5.exe` exists. The log is
`drive_c/ets5-install.log` inside the prefix.

## HID probe

```sh
sudo apt-get install -y gcc-mingw-w64-i686
make probe
WINEPREFIX=~/.local/share/wineprefixes/ets5 wine probe/hidparent-probe.exe
```

The program is a 32-bit PE, like `ETS5.exe`. `winegcc` is the wrong
compiler here: it does not see `windows.h` in this layout. A parent id of
`USB\VID_2A07&PID_0102\...` plus `OPEN : OK` means the kernel, udev, and
Wine PnP path are fine. A later ETS failure is then COM, .NET, or the
license UI, not USB.

## MQTT

Leave `MQTT_OPTIONS` empty unless a broker already exists. The value is the
full `mosquitto_pub` option string, password included, so it stays in
`.env`. The workstation and the dongle host use different users. Topic
names are in `compose/*/mqtt.yml` and are selected automatically when
`MQTT_OPTIONS` is non-empty. Without MQTT, restarting `rudy-server` leaves
the client holding a dead attachment until `docker exec rudy-client reload`.
