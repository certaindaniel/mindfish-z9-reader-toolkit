# 目前修改項目與驗證狀態

整理日期：2026-10-28

## Launcher

- 原廠 SarkBook 的 HOME 預設在 Android 4.4 開機時會被 framework 再次指定。已清除 SarkBook 的偏好並以 Modificator E-Ink Launcher 作為 HOME。
- 另以 UiAutomator 呼叫 Android `IPackageManager` 設定永久 HOME。原始碼為 [`../SetLauncherDefaultBinderTest.java`](../SetLauncherDefaultBinderTest.java)，對應的輕量執行檔為 [`../z9-home-default.jar`](../z9-home-default.jar)。裝置 shell 必須具有 `SET_PREFERRED_APPLICATIONS` 權限；工具會檢查候選 Launcher 與回讀結果。
- 為了處理開機時 framework 重設 SarkBook 的情況，該台 R9 的 `/system/framework/services.jar` 也做了機型／韌體專用修改，並已跨一般重開機確認 E-Ink Launcher 仍是 HOME。
- [`../patch-services-launcher.py`](../patch-services-launcher.py) 可從 SHA-256 完全相符的原廠備份本機重建這項修改；它會拒絕不同版本、檢查目標方法及輸出 DEX，且不會自動安裝到裝置。執行時需另備 Java 與 smali/baksmali 工具 JAR。
- OEM 原始與修補後的 framework JAR，以及已移除的系統 App APK 復原副本，只留在本機 `backups/`，不納入公開檔案。文件中的 JAR 雜湊僅是該台裝置的比對參考，不是其他機器可直接套用的通用映像。

詳細前置檢查、回復方式與韌體相符條件見 [`Launcher-Runbook.md`](Launcher-Runbook.md)。

## KOReader 內建 OpenCC

- 新增 `opencc.koplugin`，在 KOReader 書內選單提供簡體轉台灣繁體功能，離線使用 OpenCC `s2twp`。
- 支援 EPUB 與 UTF-8 TXT。EPUB 只轉 XHTML、HTML、NCX、OPF、SVG、XML 內的可見文字；建立 `.zh-TW` 副本，不覆寫來源或已存在的輸出。
- OpenCC 1.4.2 已為該機的 Android API 19／ARMv7 編譯，並附上設定、必要詞庫及授權文字。
- 外掛與執行檔已安裝到該台 Z9，KOReader 日誌確認外掛載入；安裝檔案回讀校驗一致。**尚未用實際書籍執行轉換，因此轉換結果仍待首次使用確認。**

安裝與限制見 [`../opencc.koplugin/README.md`](../opencc.koplugin/README.md)。

## Mac 命令列備援

`z9-opencc.py` 可轉換 Mac 本機檔案，也可透過 ADB 拉回 Z9 的書、轉換、校驗後傳回新副本。TXT 支援 UTF-8 與有 BOM 的 UTF-16／UTF-32。詳細方式見 [`../README-OpenCC.md`](../README-OpenCC.md)。

## App 減量（這台實機）

依照「主要使用 KOReader」的需求，已停用下列 6 個替代閱讀 App。它們都是 `/data/app` 套件；只執行 `pm disable`，沒有解除安裝、清除資料或刪除書籍：

- ALReader：`com.neverland.alreader`
- 多看閱讀：`com.duokan.reader`
- 網文閱讀 App：`com.dragon.read`
- 微信讀書：`com.tencent.weread.eink`
- iReader：`com.chaozh.iReaderFree`
- 起點讀書：`com.qidian.QDReader`

已回讀 `dumpsys package` 確認這 6 個套件是 `enabled=2`，`pm list packages -d` 也列出相同清單。要恢復其中任一 App，執行 `adb -s SERIAL shell pm enable 套件名稱`。

## App 移除（這台實機）

以下使用者安裝 App 已以 `pm uninstall` 移除；重新開機後，`pm list packages -f` 不再列出這些套件：

- 無限重漫：`com.Comic888`，版本 4.6，原位於 `/data/app`。
- UC Browser：`com.UCMobile`，版本 12.8.4.1064，原位於 `/data/app`。
- EasyTouch：`com.shere.assistivetouch`，原位於 `/data/app`。
- 靜讀天下專業版／Moon+ Reader Pro：`com.flyersoft.moonreaderp`，版本 4.2.1，原位於 `/data/app`。

以下預載系統 APK 已從 `/system/app` 實際移除；移除前的 APK 復原副本留在本機 `backups/removed-system-apks/`，由 `.gitignore` 排除，不會上傳：

- SarkBook：`com.smart.arkbook`，`SarkBook.apk`。
- SarkReader：`org.geometerplus.zlibrary.ui.android.reader`，`SarkReader.apk`。
- Exchange：`com.android.exchange`，`Exchange2.apk`。

三個套件都在重新開機後從套件清單消失；E-Ink Launcher 仍是 HOME，KOReader 仍已安裝。若要在這台裝置還原系統 APK，先確認 `adb shell id` 為 root，再執行：

```sh
adb shell mount -o remount,rw /system
adb push backups/removed-system-apks/SarkBook.apk /system/app/SarkBook.apk
adb push backups/removed-system-apks/SarkReader.apk /system/app/SarkReader.apk
adb push backups/removed-system-apks/Exchange2.apk /system/app/Exchange2.apk
adb shell chmod 644 /system/app/SarkBook.apk /system/app/SarkReader.apk /system/app/Exchange2.apk
adb reboot
```

Exchange 移除前會反覆崩潰；logcat 顯示它查詢 `content://com.android.email.provider` 時找不到 provider，而系統沒有安裝 `com.android.email`。移除 Exchange 並重開後，沒有再出現該套件的崩潰紀錄。

目前保留 KOReader、E-Ink Launcher、AOSP Browser、ES File Explorer、Onyx App Market、Shortcut Creator、時鐘與其他尚未指定移除的套件。下一台裝置應重新盤點，不要照搬本次套件清單。

## 系統語言

- 原始 locale 為 `zh_CN`；已將 Android 4.4 的 `persist.sys.language` 設為 `zh`、`persist.sys.country` 設為 `TW`，並重新開機。
- 開機後 `ActivityManager` 設定回讀為 `zh_TW`；Settings 畫面確認顯示「設定」、「無線與網路」、「語言與輸入設定」等繁體中文。
- 個別 App 若沒有繁體中文資源，App 自己的名稱或畫面仍可能顯示簡體字。
- 要還原系統原本的簡體 locale，可執行 `adb shell setprop persist.sys.language zh`、`adb shell setprop persist.sys.country CN` 後重新開機。

## 系統與 App 狀態

- 沒有刷入其他 Android 系統或 NXP EVK 映像；公開研究尚未找到能確認適用 R9 的原廠救援映像與流程。
- 上列 6 個替代閱讀 App 只停用；指定的使用者 App 已解除安裝，SarkBook、SarkReader 與 Exchange 系統 APK 已移除。
- 充電燈號含義尚未取得可靠的一手資料，綠燈閃爍不能單獨作為充電狀態判斷。
- 這台是 Android 4.4.2／API 19；官方 scrcpy 要求至少 Android 5.0／API 21，因此不支援。`--legacy-paste` 不會改變系統版本門檻；操作使用 ADB／UiAutomator。[scrcpy 官方需求](https://github.com/Genymobile/scrcpy)

## 下一台 Z9 的建議順序

1. 用 `adb devices -l` 確認目標，再讀回型號、Android 版本、API、CPU ABI、Launcher 套件與原始 `services.jar` SHA-256。
2. 先安裝／確認 KOReader 與 E-Ink Launcher；只有確認 shell 權限後，才使用 UiAutomator HOME 工具。
3. 若只是設定預設 Launcher，先按 Home 與重新開機驗證。若 framework 會改回 SarkBook，停止套用通用設定，先比對該台韌體。
4. 只有原始 framework 雜湊完全相符、備份與還原方式明確時，才考慮 firmware-specific 修改。公開工具包不含原廠或修補後的 `services.jar`；從目標裝置自己的備份執行 patcher，雜湊不符就停止並重新分析。
5. 安裝 OpenCC 外掛後重啟 KOReader，再先對可丟棄的測試書副本確認 EPUB／TXT 轉換結果。

## 公開範圍

可分享的原始碼、KOReader 外掛、OpenCC 執行檔與詞庫、Launcher 輔助工具、framework patcher、研究與操作文件都放在這個專案目錄。`backups/` 內的 framework JAR 與移除系統 App 的 APK 只供本機復原，不應上傳或散布；公開版只包含從使用者本機備份重建的程式碼。
