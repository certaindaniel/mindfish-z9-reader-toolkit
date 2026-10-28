# Mindfish Z9／Lamppa R9 Launcher 快速處理手冊

更新日期：2026-10-28

## 已驗證的裝置

- Android：4.4.2／API 19，CPU ABI `armeabi-v7a`
- 型號／裝置代號：`R9`／`evk_6sl_r9`
- Launcher：Modificator E-Ink Launcher，套件 `cn.modificator.launcher`，版本 0.1.8.3
- 原廠桌面：SarkBook，套件 `com.smart.arkbook`，版本 3.4.214
- KOReader：2021.01.1
- 已保留 SarkBook 與其資料；沒有停用或解除安裝。
- UiAutomator 已將 E-Ink Launcher 設為永久 HOME；這單獨設定無法阻止原廠 framework 在開機時重新指定 SarkBook。
- 這台的原始 `/system/framework/services.jar` SHA-256：`4cdbfb20a84956a93609f4740d8d114a13470085cc1fa92348517be619c13c7d`。

以上是單台裝置讀值。下一台先讀取型號、Android 版本、HOME 候選與 framework 雜湊，不要只根據外觀或 USB 燈號判定。

## 設定永久 HOME

請在專案目錄執行以下命令。先確認 ADB 目標、系統版本、Launcher 套件與 shell 權限：

```sh
adb devices -l
adb -s SERIAL shell getprop ro.product.model
adb -s SERIAL shell getprop ro.product.device
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.build.version.sdk
adb -s SERIAL shell pm list packages | grep -E 'cn.modificator.launcher|com.smart.arkbook'
adb -s SERIAL shell id
adb -s SERIAL shell dumpsys package com.android.shell | grep SET_PREFERRED_APPLICATIONS
```

確認目標是預期的 R9/Z9、Android 版本相容、已安裝 `cn.modificator.launcher`，而且 shell 有 `SET_PREFERRED_APPLICATIONS` 權限後，執行：

```sh
adb -s SERIAL push z9-home-default.jar /data/local/tmp/z9-home-default.jar
adb -s SERIAL shell uiautomator runtest z9-home-default.jar -c z9.SetLauncherDefaultBinderTest
```

工具會清除 SarkBook 的 HOME 預設，再即時查詢 HOME 候選並設定 E-Ink Launcher。它不清除 App 資料、不停用或解除安裝 SarkBook，也不安裝其他 App。若找不到 E-Ink 候選或發生權限錯誤，停止並檢查，不要假設已設定成功。

回讀 HOME 設定並按 Home 驗證：

```sh
adb -s SERIAL shell dumpsys package | sed -n '/Preferred Activities User 0:/,+12p'
adb -s SERIAL shell input keyevent 3
adb -s SERIAL shell dumpsys activity activities | grep 'mFocusedActivity'
adb -s SERIAL shell rm -f /data/local/tmp/z9-home-default.jar
```

確認 `cn.modificator.launcher/.Launcher` 有 `mAlways=true`，按 Home 後焦點 Activity 也是 E-Ink Launcher。這台曾保留舊的 `mAlways=false` 單次選擇記錄；永久記錄和實際焦點才是判斷依據。

## 開機時恢復 SarkBook 的原因

這台裝置的 `/system/framework/services.jar` 中，`ActivityManagerService.startHomeActivityLocked()` 會呼叫 `setDefaultLauncher()`。該方法把 `com.smart.arkbook` 和 `com.smart.sarkbook.MainActivity` 寫死，開機時清除既有 HOME 偏好並重新指定 SarkBook。因此，單靠清除 SarkBook 預設或設定 E-Ink Launcher，不能在這台韌體上跨重開機保留。

實機處理時，這兩個套件／Activity 字串被改成 `cn.modificator.launcher` 和 `cn.modificator.launcher.Launcher`，以 Android 4.4 相容的 DEX 035 重建 framework DEX，並替換 `services.jar`。重開機日誌、`dumpsys package`、Home Activity 與目前焦點都確認 E-Ink Launcher 成為 HOME。

## 針對單台裝置建立 framework 修改

**公開工具包不附原廠或修補後的 `services.jar`。** 兩者都含 OEM／Android framework 程式碼，僅保留在擁有者的本機備份。`patch-services-launcher.py` 只會接受本次已知原始 SHA-256，從使用者自己備份的 JAR 本機重建修補檔；它不會將檔案寫回裝置，也不是其他韌體可用的通用 patcher。

1. 從目標裝置備份原始 JAR，先保存到不會公開的位置，再記錄雜湊：

   ```sh
   mkdir -p backups
   adb -s SERIAL pull /system/framework/services.jar backups/services-original.jar
   shasum -a 256 backups/services-original.jar
   ```

   這台已知原始值為 `4cdbfb20a84956a93609f4740d8d114a13470085cc1fa92348517be619c13c7d`。值不同時，不要使用任何既有修改成果；先針對該機韌體重新分析。相同雜湊只表示原始檔案相同，仍需自行保留備份並核對復原方式。

2. 安裝 Java 執行環境，並另外取得官方 [smali/baksmali](https://github.com/JesusFreke/smali) 2.5.x 工具 JAR；專案不包含這些第三方工具。設定兩個工具 JAR 的本機路徑，再從專案根目錄執行：

   ```sh
   BAKSMALI_JAR="/path/to/baksmali-2.5.2.jar"
   SMALI_JAR="/path/to/smali-2.5.2.jar"
   python3 patch-services-launcher.py \
     backups/services-original.jar \
     /tmp/services-r9-eink-local.jar \
     --baksmali-jar "$BAKSMALI_JAR" \
     --smali-jar "$SMALI_JAR"
   ```

   Patcher 會再次核對原始 SHA-256 和 JAR 項目，反組譯後只修改同時含兩個 SarkBook 字串的 `setDefaultLauncher()`，以 API 19／DEX 035 重建，再反組譯輸出檢查新字串。若 hash、方法或字串數量不符會停止。輸出只含新的 `classes.dex`，因原始 DEX 已改動，原廠 JAR 簽章檔不會保留；程式只在本機產檔，不會推送或安裝。選擇一個尚不存在的輸出路徑。

3. 將本機產出的 JAR 設為 `PATCHED_SERVICES_JAR`，確認它能解壓、內含預期 DEX，並與原始備份分開保存。確認 `adb shell id` 有 root 權限，且本機原始備份可讀、來源和雜湊都已確認；否則不要寫入 `/system`。例如：

   ```sh
   PATCHED_SERVICES_JAR="/path/to/services-r9-local.jar"
   ```

4. 先把原始檔與本機產出的修補檔都推到裝置暫存位置，再原子替換。以下的 `PATCHED_SERVICES_JAR` 請指向本機自行產出的檔案：

   ```sh
   adb -s SERIAL shell mkdir -p /data/local/tmp/z9-recovery
   adb -s SERIAL push backups/services-original.jar /data/local/tmp/z9-recovery/services-original.jar
   adb -s SERIAL push "$PATCHED_SERVICES_JAR" /data/local/tmp/z9-recovery/services-patched.jar
   adb -s SERIAL shell mount -o remount,rw /system
   adb -s SERIAL shell cp /data/local/tmp/z9-recovery/services-patched.jar /system/framework/services.jar.new
   adb -s SERIAL shell chmod 644 /system/framework/services.jar.new
   adb -s SERIAL shell mv /system/framework/services.jar.new /system/framework/services.jar
   adb -s SERIAL shell rm -f /data/dalvik-cache/system@framework@services.jar@classes.dex
   adb -s SERIAL shell sync
   adb -s SERIAL reboot
   ```

5. 等待 `sys.boot_completed=1`，再確認沒有開機錯誤、framework 日誌指定正確 Launcher、HOME 永久偏好存在且 Home 焦點正確。首次重開可能重新最佳化 framework 相依 App，畫面會暫時顯示「Android 正在升級…」。若無法正常開機，使用該台自己的原始備份還原。

## 還原目標裝置自己的原始 framework

還原前必須確認 `/data/local/tmp/z9-recovery/services-original.jar` 是從**同一台裝置**備份而來。不要依賴公開 repo 中不存在的 OEM JAR：

```sh
adb -s SERIAL shell mount -o remount,rw /system
adb -s SERIAL shell cp /data/local/tmp/z9-recovery/services-original.jar /system/framework/services.jar.rollback
adb -s SERIAL shell chmod 644 /system/framework/services.jar.rollback
adb -s SERIAL shell mv /system/framework/services.jar.rollback /system/framework/services.jar
adb -s SERIAL shell rm -f /data/dalvik-cache/system@framework@services.jar@classes.dex
adb -s SERIAL shell sync
adb -s SERIAL reboot
```

如果裝置暫存備份不存在，先從該台裝置或自己的離線備份還原；無法確認備份來源與版本時，不要覆寫 framework。

## 本專案提供的 Launcher 輔助工具

- UiAutomator 原始碼：[../SetLauncherDefaultBinderTest.java](../SetLauncherDefaultBinderTest.java)
- Android 4.4 DEX JAR：[../z9-home-default.jar](../z9-home-default.jar)，SHA-256：`1f75c883abc8eabfb89f7d64c2b14a8ac6870a805cbc910545fe0a136a68391b`
- 這個小型工具是本專案程式碼，不包含 OEM framework 實作。它已在本次 R9 執行並回讀驗證。
