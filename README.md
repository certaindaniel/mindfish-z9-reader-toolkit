# Mindfish Z9 Reader Toolkit

Tools and notes for adapting a Mindfish Z9 / Lamppa R9 e-reader for KOReader. This folder is organized as a standalone source package; the surrounding workspace is not part of the package.

## Project status

The changes below were made on one R9/Z9 running Android 4.4.2 (API 19), `armeabi-v7a`, KOReader 2021.01.1, Modificator E-Ink Launcher 0.1.8.3, and SarkBook 3.4.214. Other units may have different firmware or permissions; inspect each device before applying system-level changes.

| Area | What is included | Current evidence |
|---|---|---|
| KOReader OpenCC | Offline KOReader plugin for EPUB and UTF-8 TXT; OpenCC `s2twp` ARMv7 executable and dictionaries | Installed on the connected Z9; KOReader logged the plugin load. No book has been converted yet. |
| Launcher selection | UiAutomator source and its small `z9-home-default.jar`; launcher runbook | The HOME preference tool was used on the Z9. The separate framework change that survives reboot is device-specific; its OEM JARs are excluded. |
| Mac conversion fallback | `z9-opencc.py` for Mac files or ADB paths | Source and usage notes are included; it leaves the original book intact. |
| Firmware research | Launcher and firmware compatibility notes | No alternate OS was flashed. No R9-specific recovery image has been verified. |

SarkBook and its data were kept as a fallback. Six redundant reader apps were disabled without uninstalling them or clearing their data; the exact package list and restore command are in [`docs/Current-Changes.md`](docs/Current-Changes.md).

## Quick start

Install the KOReader OpenCC plugin over ADB, then restart KOReader:

```sh
bash install-opencc-koplugin.sh
```

If more than one Android device is connected, select the Z9 explicitly:

```sh
ANDROID_SERIAL=YOUR_DEVICE_SERIAL bash install-opencc-koplugin.sh
```

Open an EPUB or TXT book and use the book menu: **簡體轉台灣繁體** → **將目前的 EPUB／TXT 轉成台灣繁體副本**. The converted `.zh-TW` copy is saved beside the source; the source and any existing copy are preserved.

For the Mac-side converter, see [`README-OpenCC.md`](README-OpenCC.md). For launcher behavior and per-device checks, start with [`docs/Current-Changes.md`](docs/Current-Changes.md) and [`docs/Launcher-Runbook.md`](docs/Launcher-Runbook.md).

## Wi-Fi book transfer

The installed KOReader 2021.01.1 package includes its Calibre wireless client. The plugin is present in the device build, but wireless transfer has not yet been tested against a Calibre server on this unit.

To transfer books from a computer, connect the reader and computer to the same local Wi-Fi network. In Calibre, start **Wireless Device Connection** from **Connect/share**. In KOReader, choose **Calibre → Connect**; on first use, choose the inbox folder for received books. Then use Calibre's **Send to device** action. KOReader uses Calibre's Wireless Device Connection, not its Content Server. See the [KOReader Calibre guide](https://github.com/koreader/koreader/wiki/calibre).

If automatic discovery fails, use **Calibre → Wireless settings → Server address → Manual** in KOReader and enter the address and port shown by Calibre. The reader's Wi-Fi was off when this toolkit was prepared; joining a network remains a per-device setup step.

## Package map

- `opencc.koplugin/` — KOReader menu plugin, markup-aware EPUB conversion, native OpenCC executable, dictionaries, and license texts.
- `z9-opencc.py` — Mac/ADB conversion fallback.
- `SetLauncherDefaultBinderTest.java` and `z9-home-default.jar` — Android 4.4 UiAutomator helper for setting the HOME preference.
- `patch-services-launcher.py` — rebuilds the device-specific Launcher framework change from an exact-hash original JAR.
- `build-opencc-android.sh`, `install-opencc-koplugin.sh` — build and install helpers.
- `docs/` — current modification inventory, launcher runbook, and research.
- `backups/` — local-only device framework JARs; ignored and intentionally absent from a public checkout.

## Device-specific Launcher change

On this R9, Android's framework reset the HOME preference to SarkBook during boot. A firmware-specific `services.jar` change made the E-Ink Launcher survive ordinary reboot. The public package does **not** include either the original or modified OEM `services.jar`; both contain firmware-specific Android framework code. `patch-services-launcher.py` accepts only the exact known original SHA-256, verifies the target method, and rebuilds an unsigned JAR locally using user-supplied smali/baksmali tools. It does not install the result. A different hash is rejected and requires fresh firmware analysis. See the [launcher runbook](docs/Launcher-Runbook.md) for prerequisites and recovery steps.

## Supported conversion scope

- TXT must be UTF-8 for the KOReader plugin. The Mac fallback also recognizes BOM-marked UTF-16 and UTF-32 TXT.
- EPUB must be a standard single-disk ZIP archive. The plugin rejects ZIP64, encrypted entries, unsupported flags, invalid UTF-8, and files beyond its documented size limits.
- The plugin converts visible text in markup entries and keeps tags, attributes, scripts, CSS, images, fonts, and other binary content unchanged.

## License

The project is licensed under AGPL-3.0 because the EPUB ZIP writer is adapted from KOReader's AGPL-3.0 code. Third-party OpenCC, dictionary, and LuaRocks notices are included in `opencc.koplugin/licenses/` and [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
