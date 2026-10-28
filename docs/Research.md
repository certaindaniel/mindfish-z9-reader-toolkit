# Mindfish／Lamppa Z9：充電燈號與 Launcher 可行性查證

調查日期：2026-10-28

## 後續實機狀態（2026-10-28）

這份研究先完成公開資料查證，之後才接上實機。以下是後續讀回結果：

- 實機為 Mindfish／Lamppa R9（使用者稱 Z9），Android 4.4.2／API 19、`armeabi-v7a`；原先安裝 KOReader 2021.01.1、E-Ink Launcher 0.1.8.3 與 SarkBook 3.4.214，SarkBook APK 後依使用者要求移除。
- E-Ink Launcher 已成為開機後 HOME，跨一般重開機驗證成功。沒有刷入其他系統；後續依使用者需求已解除安裝指定 App、移除 SarkBook／SarkReader／Exchange 系統 APK，並將系統語系設為 `zh_TW`。SarkBook 等系統 APK 的本機復原副本不公開；完整套件狀態見[實機修改清單](Current-Changes.md)。
- KOReader OpenCC 外掛已安裝，日誌確認載入；尚未用實際書籍執行轉換。
- 原始與修補後的 OEM `services.jar` 只作本機備份，不會放進公開工具包。下一台可用專案 patcher 從自己的備份重建，但只接受本次已知原始檔 SHA-256；細節見 [Launcher 快速處理手冊](Launcher-Runbook.md)。

## 結論

- **充電燈號：未能查證。** 在可找到的資料中，沒有原廠手冊或其他可信的一手來源說明 Z9 綠燈閃爍、熄滅的含義。因此，使用者看到「綠燈閃一下、再熄一會兒」不能據此判定正在充電、已充滿或充電異常。
- **更換預設 Launcher：已在這台實機完成並跨重開機驗證。** 實機是 Android 4.4.2/API 19；原廠 framework 開機時硬編碼把 SarkBook 設為 HOME。已修補 `services.jar` 指向現有的 Modificator E-Ink Launcher；重開機後日誌、永久 HOME 記錄和目前焦點都確認是 E-Ink。這是對目前韌體系統分割區的修改，韌體更新或恢復原廠系統可能覆蓋它。
- **若實機是 Android 4.4/API 19：** Modificator 的 E-Ink Launcher 原始碼宣告最低 API 14，且註冊了 HOME intent filter，表面上符合安裝與成為 Home app 的條件；但專案版本較舊、維護狀態不明，不能只因最低 API 合適就保證在 Z9 上正常運作。
- **較新的 TaoZang EInkLauncher 不適用 Android 4.4。** 其專案原始碼宣告最低 Android 5.0/API 21。
- **若實機是 Android 4.4，可優先評估 BookLauncher + KOReader。** BookLauncher 標示支援 Android 4.4、最低 API 16，書架模式可列出 `/sdcard/Books` 的 EPUB/PDF 並呼叫 KOReader；但它使用 React Native，專案自己也列出常駐 Launcher 的記憶體／效能疑慮，所以要先在實機試用，不應直接設成永久預設。KOReader 的 F-Droid 版本支援 Android 4.3 以上，提供 `armeabi-v7a`、`arm64-v8a`、`x86` 等版本；安裝前仍須確認 Z9 的 CPU ABI，並檢視它的儲存空間、網路與系統設定權限。

## 裝置身分與版本

使用者提供的 Pixnet 文章將產品稱為 Lamppa Z9／Mindfish E-Ink 電子書閱讀器，並在 R9W／R9T 段落描述 Android、原廠 SarkBook Launcher 與更換 Home app 的步驟。這項早期判斷只依第三方教學文章；後續實機讀值已確認本次接上的裝置是 R9、Android 4.4.2/API 19。第三方文章仍不是原廠手冊，充電燈號含義尚未確認。

因此，處理其他裝置時仍應先讀取 Android release/API level、型號與可用的 HOME 活動，再決定安裝哪個 Launcher。先前曾辨識到的 Samsung Android 裝置不是這次確認的 Z9/R9。

## 綠燈閃爍

目前沒有找到 Z9 專屬的一手充電指示燈說明。其他電子書閱讀器常見的紅燈、綠燈或閃爍規則不能套用到這台裝置。此燈號的含義維持未知；可另外查看閱讀器螢幕上的電池充電圖示，並比較一段時間前後的電量百分比，但這只能驗證實際充電結果，不能證明綠燈本身的定義。

## Launcher 可行性

### Android 平台支援

Android 4.4 相容性文件說明平台包含預設 Launcher，也支援第三方應用程式取代 Home screen；該版本也要求提供使用者設定預設 Home app 的介面。Android 官方 SDK 對照表列出 Android 4.4 為 API 19。這表示若 Z9 實機確為 Android 4.4 且韌體保留標準 Home 設定，替換預設 Launcher 是合理且可回復的方向。

### Modificator E-Ink Launcher

該專案的 Android build 檔宣告 minSdkVersion 14；Manifest 將主 Launcher 註冊為 MAIN／HOME／DEFAULT。API 19 高於其最低安裝門檻，因此在 Android 4.4 上有安裝資格，但仍需在 Z9 實機驗證畫面、觸控、書籍閱讀 App 啟動與重新開機後的預設狀態。

其公開專案版本較舊：GitHub Releases 頁面可見的版本為 v0.1.8.3，發布於 2020-04-25；專案頁面亦提到舊版本支援已結束。其 Manifest 還要求網路、外部儲存、Wi-Fi 變更、喚醒鎖定、關機與重新啟動等權限。這些資料不足以推薦直接安裝未知來源 APK；後續若考慮此方案，應先核對 APK 來源、簽章、權限與可回復方式。

### TaoZang EInkLauncher

這個較新的 E-Ink Launcher 專案主打黑白靜態介面、無動畫與自選主畫面 App；專案說明也指出它不呼叫特定廠商的電子墨水刷新 SDK，因此不能保證控制 Z9 的局部／全螢幕刷新。其 build 檔最低版本是 Android 5.0/API 21；若 Z9 實機是 Android 4.4/API 19，系統會因版本門檻而不相容。

### BookLauncher 與 KOReader

BookLauncher 專為電子墨水裝置設計，提供列出 `/sdcard/Books` 內 EPUB/PDF 的書架模式，並可呼叫 KOReader 開書；專案 README 自述支援 Android 4.4，Android build 設定最低 API 16。這讓它成為舊版 Z9 的候選方案，但 README 也明確列出 React Native 常駐 Launcher 可能較耗記憶體、需要效能優化。它沒有公開 Release，專案規模也小，因此安裝前應先檢查 APK 來源與簽章，並在不改預設值的情況下驗證啟動速度、刷新與回復原 Launcher 的方法。

KOReader 的 F-Droid 條目列出 Android 4.3 以上需求，並提供 ARMv7、ARM64 與 x86 組件；它支援 EPUB、PDF、DjVu、CBZ、FB2、TXT 等格式，適合作為閱讀 App 候選。F-Droid 條目同時列出讀寫共用儲存空間、網路與修改系統設定等權限；要先核對 Z9 的 CPU ABI 和權限，再安裝。即使只安裝 KOReader，也可先保留 SarkBook 作為預設 Launcher，單獨驗證閱讀功能。

## 開機時重設預設 Launcher 的原因與修正

**根因已在實機 framework 中確認：** `/system/framework/services.jar` 的 `ActivityManagerService.startHomeActivityLocked()` 會呼叫 `setDefaultLauncher()`；後者硬編碼 `com.smart.arkbook` 和 `com.smart.sarkbook.MainActivity`，開機時清除 HOME 偏好並重新指定 SarkBook。只清除 SarkBook 預設或透過套件管理器設定 E-Ink，無法阻止這段 framework 程式再次覆寫。

已將這兩個字串改為 `cn.modificator.launcher` 和 `cn.modificator.launcher.Launcher`，以 Android 4.4 相容的 DEX 035 重建 `services.jar`。重開機後，ActivityManager 日誌記錄 `default packageName = cn.modificator.launcher` 及新增 E-Ink preferred activity；`dumpsys package` 的 E-Ink 項目有 `mAlways=true`，視窗焦點與目前 Home Activity 均為 E-Ink Launcher。這證明 framework 開機覆寫已改成 E-Ink。

原始 JAR SHA-256：`4cdbfb20a84956a93609f4740d8d114a13470085cc1fa92348517be619c13c7d`；本機修補 JAR SHA-256：`d5d68ad8a62f2c0fe81f58aae196844b5ca113245ee27d89009229eaaaa24fc7`。兩個檔案都只在裝置擁有者的本機備份；公開工具包不含 OEM 原始或修補後 JAR。下一台先比對自己的原始 `services.jar`；雜湊不同就重新分析，不可套用本次結果。若雜湊相同，可用專案 patcher 從自己的備份產生本機修補檔；工具與回復條件見 [Launcher 快速處理手冊](Launcher-Runbook.md)。

## 建議處理順序

1. 確認連上的確是 Mindfish／Lamppa 閱讀器；讀取實機 Android 版本、API level、型號和現有 HOME app。
2. 在其他裝置上，先保留 SarkBook 作回復桌面，直到替代 Launcher 已跨重開機確認。這台後續依使用者要求移除了 SarkBook APK，復原副本只留在本機。
3. 依實際 API level 選擇相容 Launcher。若走系統選擇器，選定後設定為「一律使用」，再測試按 Home 與重新開機後是否仍保留。
4. 若同型機開機後又回 SarkBook，先比對該機 `services.jar` 的 SHA-256。只有與本次原版完全相同才可用專案 patcher 從該機自己的備份重建；雜湊不同就重新分析，不要直接覆寫。公開版不附 OEM JAR。
5. 燈號仍以實機電池圖示／電量變化與原廠或賣家確認為準；目前沒有可引用的 Z9 燈號表。

若要評估較完整的閱讀器工作流程，可另外試用 BookLauncher + KOReader；目前這台以 E-Ink Launcher 為開機預設，並已依使用者要求移除 SarkBook APK（本機留有復原副本）。任何替代 Launcher 都要先確認與該台 Android 版本及韌體相容，且不要把本次的 framework JAR 套用到不同雜湊的系統版本。

## 實機接上與處理結果（2026-10-28）

- USB 裝置顯示 Freescale R9（VID `18D1`、PID `4E42`）；ADB 與 Android 屬性都回報型號 R9、裝置代號 `evk_6sl_r9`，與使用者所說的 Z9／R9 閱讀器相符，不是先前辨識到的 Samsung 裝置。
- 實機系統是 Android 4.4.2/API 19，CPU ABI 是 `armeabi-v7a`。
- 電池服務回報 USB 供電中、電量 100%、狀態為已充滿。這能確認當下系統讀到 USB 供電和滿電狀態，仍不能定義綠燈閃爍的意思。
- 初次盤點時已安裝 Modificator E-Ink Launcher 0.1.8.3、KOReader v2021.01.1 與 SarkBook 3.4.214，沒有必要先下載新 Launcher 或閱讀 App。
- 原先 HOME 預設為 SarkBook。已透過應用資訊只清除 SarkBook 的預設 HOME 指派；沒有清除 App 資料、停用或移除 SarkBook。
- Android 4.4 的選擇器經 ADB 點選 E-Ink 列時只會啟動一次，且 `Always` 按鈕仍是停用狀態。UiAutomator 的 Android `IPackageManager.addPreferredActivity` 可將 E-Ink 設為永久 HOME；讀回 `dumpsys package` 可見 `mAlways=true`，按 Home 的焦點 Activity 是 `cn.modificator.launcher/.Launcher`。
- 初次更換預設後，重開機會把 HOME 改回 SarkBook。檢查 `services.jar` 的 DEX 後，確認是 `ActivityManagerService.setDefaultLauncher()` 硬編碼造成。
- 已備份原始 framework JAR、重建並安裝指向 E-Ink 的 JAR。開機日誌確認 framework 指派 E-Ink，`dumpsys package` 顯示 `mAlways=true`，Home Activity 與畫面焦點都是 `cn.modificator.launcher/.Launcher`。
- 替換後首次啟動會重新最佳化 framework 相依 App，畫面短暫顯示 Android「正在升級…」；約數分鐘完成，`sys.boot_completed=1`，Launcher 正常顯示。
- 本次修改跨一般重開機生效；系統更新、恢復原廠或重刷系統可能還原原本的 SarkBook 指派。原始與修補 JAR、雜湊、套用條件及還原流程都已記錄在 [Z9 Launcher 快速處理手冊](Launcher-Runbook.md)。
- 設定 Launcher 時沒有清除 SarkBook 資料、停用或移除；後續依使用者要求從 `/system/app` 移除了 SarkBook APK，復原副本保留於本機忽略目錄。

## 來源

- [Android 4.4 Compatibility Definition：Default App Settings 與 Launcher（AOSP）](https://source.android.com/docs/compatibility/4.4/android-4.4-cdd.pdf)
- [Android SDK 平台版本與 API level 對照（Android Developers）](https://developer.android.com/guide/topics/manifest/uses-sdk-element)
- [Modificator E-Ink Launcher：master build.gradle](https://raw.githubusercontent.com/Modificator/E-Ink-Launcher/master/app/build.gradle)
- [Modificator E-Ink Launcher：master AndroidManifest.xml](https://raw.githubusercontent.com/Modificator/E-Ink-Launcher/master/app/src/main/AndroidManifest.xml)
- [Modificator E-Ink Launcher：v0.x build.gradle.kts](https://raw.githubusercontent.com/Modificator/E-Ink-Launcher/v0.x/app/build.gradle.kts)
- [Modificator E-Ink Launcher：GitHub Releases](https://github.com/Modificator/E-Ink-Launcher/releases/tag/v0.1.8.3)
- [TaoZang EInkLauncher 專案說明與相容範圍](https://github.com/TaoZang/EInkLauncher)
- [TaoZang EInkLauncher：Android build 設定](https://raw.githubusercontent.com/TaoZang/EInkLauncher/master/app/build.gradle.kts)
- [BookLauncher 專案說明（功能、Android 4.4 支援聲明與效能待辦）](https://github.com/number317/BookLauncher)
- [BookLauncher：Android build 設定（minSdkVersion）](https://raw.githubusercontent.com/number317/BookLauncher/master/android/build.gradle)
- [KOReader：F-Droid Android 相容版本、架構與權限](https://f-droid.org/packages/org.koreader.launcher.fdroid/)
- [KOReader 官方 GitHub Releases](https://github.com/koreader/koreader/releases)
- [使用者提供的 Z9／R9W／R9T 介紹文章（第三方來源）](https://newguest88.pixnet.net/blog/posts/945618081727712042)
