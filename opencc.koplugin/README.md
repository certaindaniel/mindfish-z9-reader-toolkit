# Z9 KOReader OpenCC plugin

The plugin adds **簡體轉台灣繁體** to KOReader's book menu. It converts EPUB and UTF-8 TXT books offline with OpenCC `s2twp`, writes a `.zh-TW.epub` or `.zh-TW.txt` copy beside the original, and can open that copy when finished. It never overwrites the source or an existing converted copy.

## Install on the Z9

Connect the reader with USB debugging enabled, then run:

```sh
bash install-opencc-koplugin.sh
```

If more than one Android device is connected, set `ANDROID_SERIAL` to the target device serial. Restart KOReader after installation. Open a supported book, open the book menu, and choose **簡體轉台灣繁體** → **將目前的 EPUB／TXT 轉成台灣繁體副本**.

## EPUB handling

- Converts visible text in XHTML, HTML, NCX, OPF, SVG, and XML entries. It leaves tags, attributes, CSS, scripts, images, fonts, and other binary resources unchanged.
- Keeps the EPUB `mimetype` entry first and uncompressed.
- Verifies entry sizes and CRCs before and after repacking, then extracts the finished archive and verifies its contents before publishing the copy.
- Uses a private temporary directory, removes it after the conversion, and preserves the original book.
- Supports standard single-disk ZIP archives with stored or DEFLATE entries. ZIP64, encrypted EPUBs, unsupported ZIP flags, invalid UTF-8, and unusually large books are rejected with an error instead of being rewritten.
- Text documents must be valid UTF-8; UTF-16/UTF-32 EPUB text and TXT files are not supported.

Current limits are 64 MiB per ZIP entry, 32 MiB per EPUB text document, 512 MiB total expanded content, and 1 GiB for the source archive.

## Rebuild the native OpenCC executable

The checked-in executable targets Android API 19 and the Z9's `armeabi-v7a` processor. To rebuild it on macOS, install Android NDK r24 and OpenCC 1.4.2 with Homebrew, then run:

```sh
ANDROID_NDK_HOME="/path/to/android-ndk-r24" bash build-opencc-android.sh
```

The plugin code uses KOReader's AGPL-3.0 ZIP writer, derived in part from LuaRocks' MIT-licensed ZIP implementation. OpenCC and bundled dependency license texts are in `licenses/`.
