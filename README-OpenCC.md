# Z9 EPUB／TXT 簡轉台灣繁體

Z9 上的 KOReader 可安裝 OpenCC 外掛，在書內選單直接轉換 EPUB 或 TXT。外掛會離線建立 `.zh-TW.epub`／`.zh-TW.txt` 副本，保留原書，也不會覆寫已存在的副本。詳見 [`opencc.koplugin/README.md`](opencc.koplugin/README.md)。

安裝已連線的 Z9：

```sh
bash install-opencc-koplugin.sh
```

安裝後重新啟動 KOReader，再從書內選單選「簡體轉台灣繁體」。

Mac 命令列工具仍可用於電腦上的檔案或透過 ADB 轉換裝置上的書：

`z9-opencc.py` 使用 Mac 上的 OpenCC `s2twp` 設定，產生台灣繁體副本。支援 EPUB 與 TXT；來源檔會保留，已有同名副本時會停止而不覆寫。

## 安裝需求

```sh
brew install opencc android-platform-tools
```

## 轉換 Mac 上的檔案

```sh
python3 z9-opencc.py "/path/to/book.epub"
python3 z9-opencc.py "/path/to/book.txt"
```

輸出會放在原檔旁，例如 `book.zh-TW.epub`。

## 轉換已連線 Z9 上的書

```sh
python3 z9-opencc.py --device "/storage/emulated/0/Books/book.epub"
python3 z9-opencc.py --device "/storage/emulated/0/Books/book.txt"
```

若同時連著多台 Android 裝置，加入 `--serial DEVICE_SERIAL`。腳本會先拉回 Mac 轉換，再將副本傳回原目錄；回讀校驗碼相符後才改成正式檔名。

## 範圍與限制

- EPUB 只轉換 XHTML、HTML、NCX、OPF、SVG 與 XML 的文字內容；標籤、屬性、圖片、字型、CSS、程式碼及原書其他資料會保留。
- EPUB 會重新打包，並確保 `mimetype` 是第一個且未壓縮；完成後會檢查 ZIP 內容完整性。
- TXT 支援 UTF-8，以及附 BOM 的 UTF-16／UTF-32。無法判定編碼時會停止，不猜測轉碼。
- KOReader 外掛只支援 UTF-8 TXT 與標準單磁碟 EPUB ZIP；ZIP64、加密 EPUB、非 UTF-8 文字或超過裝置限制的書籍會停止轉換。
- 有 DRM、加密或損毀的 EPUB 可能無法讀取；失敗時不會發布輸出副本。
