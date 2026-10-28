# Mindfish／Lamppa Z9（R9）韌體與救援路徑查證

調查日期：2026-10-28

## 結論

**找到可安全採用的 R9 exact image：否；目前無法驗證，不能刷。**

找到一套 NXP／Freescale 官方 Android 4.4.2 i.MX 6SoloLite EVK 參考板 BSP，且它與實機回報的 `evk_6sl_r9`、`imx6sl`、Freescale、Android 4.4.2 有明顯關聯；NXP 的 EVK 規格也列出 E Ink EPD 板。這證明實機很可能沿用 i.MX 6SoloLite EVK 平台設計，但**不證明 NXP 參考板映像等同 Lamppa/Mindfish 的 R9 產品韌體**。目前沒有找到公開的一手來源把 `R9`／`R9W`／`R9T`、2017 年產品 build `1.0.4-debug 20171011` 與特定韌體檔、雜湊或簽章連起來。

NXP 參考 BSP 是 2014 年的 `kk4.4.2_1.0.0-ga`。NXP 文件把它稱為 i.MX 6SoloLite **EVK 開發板**預載映像，並列出 U-Boot、boot、recovery、system 映像與 MFGTool 寫入方式；它不是 R9 出廠映像，也沒有 R9 的 e-ink 面板、觸控、儲存配置及產品 app 相容性保證。韌體錯刷的後果包括失去開機、顯示或觸控，以及覆寫產品原本的 bootloader／recovery。故不能把這份參考映像當成 R9 可安全刷入的映像。

## 實機比對資料

下列實機值由主工作階段的 ADB 讀回提供；本研究子任務沒有對裝置執行任何操作：

- `ro.product.model=R9`
- `ro.product.device=evk_6sl_r9`、`ro.product.name=evk_6sl_r9`
- `ro.board.platform=imx6sl`、`ro.product.board=EVK`、`ro.hardware=freescale`
- Android `4.4.2`／API 19
- `ro.build.fingerprint=Freescale/evk_6sl_r9/evk_6sl_r9:4.4.2/1.0.4-debug/20171011:user/dev-keys`
- 已安裝 `/system/app/OTAUpdate.apk`，套件 `com.fsl.android.ota`

`evk_6sl_r9` 名稱與 NXP 的 `evk_6sl` 參考板目標相近；型號尾碼 `r9` 及產品 build 卻沒有在找到的 NXP 參考資料中對應到已知映像。裝置上的 `com.fsl.android.ota` 只證明安裝了 OTA app；本次公開來源查證未找到它使用的伺服器、簽章金鑰、可用套件或 R9 專屬更新流程，不能由套件名稱推論可安全 OTA。

## 找到的官方參考 BSP

NXP Community 的 Freescale／NXP 發行說明列出 `IMX6SL_EVK_KK442_100_ANDROID_DEMO_BSP`，描述為 i.MX 6SoloLite EVK 的 Android KK 4.4.2 BSP binary demo files；文件也將 i.MX6SL EVK 列為目標硬體。這是可信的 SoC／EVK 參考軟體來源，但不是 R9 製造商發行記錄。[NXP／Freescale i.MX 6 Android 4.4.2 GA 發行頁](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX-6-D-Q-DL-S-SL-kk4-4-2-1-0-0-GA-release/ta-p/1103028)

Freescale 的 Android Quick Start Guide 列出映像包 `android_kk4.4.2_1.0.0-ga_core_image_6slevk.tar.gz`；其中 EVK SD 版本包含 `u-boot-mx6sl.bin`、`SD/boot.img`、`SD/recovery.img`、`SD/system.img`。文件稱下載方式為 MFGTool、工具僅支援 Windows，且 EVK 要切換 S1 boot mode 進入下載模式，再將 S1 與 SW3/SW4/SW5 切回 SD 開機。這是**EVK 參考板的救援／燒錄流程**，不是已驗證的 R9 流程。文件列出的步驟會寫入 bootloader 與 Android 分割區；若 R9 的板上開關、儲存拓樸或 MFGTool profile 不同，照抄可能造成無法開機。[Freescale Android Quick Start Guide（NXP Community 官方附件，Rev. kk4.4.2_1.0.0-ga）](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-processors/58859/1/Android_Quick_Start_Guide.pdf)

NXP 現行 i.MX Android 支援頁仍列有 2014 年的 kk4.4.2 文件；其下載項目標示需要帳號。公開頁提供文件／軟體發行資訊，但此查證未取得可供 R9 比對的原廠映像檔、SHA-256、簽章或 R9 專屬安裝包。[NXP i.MX Android OS 支援頁](https://www.nxp.com/design/design-center/software/embedded-software/i-mx-software/android-os-for-i-mx-applications-processors%3AIMXANDROID?tab=Design_Tools_Tab)

NXP i.MX 6SoloLite EVK 規格列出 i.MX 6SoloLite、eMMC/eSD footprint、三個 SD/MMC 插槽、E Ink EPD 板、Micro USB OTG、JTAG 與 console UART。這些特徵與電子紙閱讀器及實機 `evk_6sl_r9` 屬性相符，支持「R9 可能以該 EVK 平台為基礎」的推論；規格沒有提到 Lamppa、Mindfish、R9 或 R9W/R9T，因此不能證明兩者 PCB、面板控制、開機開關或儲存配置相同。[NXP i.MX 6SoloLite EVK Fact Sheet](https://www.nxp.com/docs/en/fact-sheet/IMX6SLEVKFS.pdf)

## 型號與映像的相符程度

| 比對項目 | 官方 NXP EVK 參考資料 | 實機讀值 | 判斷 |
|---|---|---|---|
| SoC／平台 | i.MX 6SoloLite EVK | `imx6sl`、`EVK`、`freescale` | 高度相符 |
| Android | Android 4.4.2 KK GA，2014 | Android 4.4.2，build 2017 | Android 主版本相同；產品 build 不同 |
| 產品板目標 | `evk_6sl`／EVK SD | `evk_6sl_r9`／R9 | 名稱相近，但找不到官方 `r9` 映像對照 |
| 電子紙 | EVK 規格列有 E Ink EPD 板 | Mindfish Z9 電子紙閱讀器 | 類別相符，不足以證明面板與驅動一致 |
| 映像驗證 | 公開說明列包名，NXP 下載項需登入 | 無 R9 映像雜湊／簽章資料 | 無法建立檔案身分與適用型號 |
| 救援流程 | MFGTool + EVK 實體 boot switches + Windows | 目前僅見 Android／ADB USB；R9 開關位置未確認 | 無法證明可將 EVK 流程套用到產品 |

**推論：** R9 的 build target 名稱和硬體功能很可能源自 NXP 6SoloLite EVK，但產品 build 應包含廠商調整。若以 NXP generic BSP 重刷，即使 SoC 和大版本吻合，也可能移除原廠 e-ink、觸控或電源管理設定，以及 SarkBook／OTA 客製化。這項推論不等於已確認映像會失敗；它表示目前沒有足夠證據把風險降到可刷的程度。

## R9／Lamppa／Mindfish 一手來源搜尋範圍

公開搜尋的精確字詞包括：`Mindfish Lamppa Z9 firmware`、`Lamppa R9W firmware`、`Lamppa R9T firmware`、`evk_6sl_r9`、`site:community.nxp.com "evk_6sl_r9"`、`"IMX6SL_EVK_KK442_100_ANDROID_DEMO_BSP"`。另外檢查使用者提供的 Pixnet 桌面更換文章，並在該頁查找「韌體」、「Recovery」與「Android 4.4」等內容。

目前只找到第三方 Pixnet Launcher 教學，說明清 SarkBook 預設後透過 HOME 選擇 E-Ink Launcher；文章沒有韌體下載、救援或原廠支援資訊。該頁可作為操作流程線索，不能作為刷機檔案來源。[使用者提供的 Pixnet 教學](https://newguest88.pixnet.net/blog/posts/945618081727712042)

這些查詢沒有找到可驗證的 Lamppa／Mindfish 原廠 R9 韌體頁、原廠檔案伺服器、SHA-256、簽章指紋或 R9 刷機說明。這是「在已查詢的公開來源中未找到」；不代表廠商從未私下提供韌體、NXP 帳號下載頁不可能有其他檔案，或客服不持有映像。

## 刷寫決策

- **目前不刷任何映像。** 尚無 R9 exact image、對應簽章／雜湊及可驗證的 R9 救援流程。
- NXP `6slevk` BSP 可以留作硬體研究或將來在可還原的 SD 開機媒體上做實驗的候選，不得直接刷入 R9 的內部儲存裝置。
- NXP 參考流程要求 Windows MFGTool 與實體 boot mode／SD 開機開關；目前沒有來源確認 R9 具有相同可接觸開關、位置及設定。這也不能單靠目前 ADB 連線遠端完成。
- 若要重刷 R9，下一步應向 Lamppa/Mindfish 或產品賣家取得 R9/R9W/R9T 對應檔案、版本說明、checksum/signature、官方刷機步驟與復原程序；再比對裝置型號、PCB revision、面板、儲存分割區及 bootloader。若拿不到這些證據，保留目前系統，先用已安裝的 Launcher／閱讀 App 解決使用流程。

## 來源清單

1. [NXP／Freescale i.MX 6 Android kk4.4.2_1.0.0 GA 發行頁](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX-6-D-Q-DL-S-SL-kk4-4-2-1-0-0-GA-release/ta-p/1103028)
2. [Freescale Android Quick Start Guide，Rev. kk4.4.2_1.0.0-ga，2014-07](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-processors/58859/1/Android_Quick_Start_Guide.pdf)
3. [Freescale Android Release Notes，Rev. kk4.4.2_1.0.0-ga](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-processors/69051/1/Android_Release_Notes.pdf)
4. [NXP i.MX 6SoloLite EVK Fact Sheet](https://www.nxp.com/docs/en/fact-sheet/IMX6SLEVKFS.pdf)
5. [NXP i.MX Android OS 支援與下載頁](https://www.nxp.com/design/design-center/software/embedded-software/i-mx-software/android-os-for-i-mx-applications-processors%3AIMXANDROID?tab=Design_Tools_Tab)
6. [第三方 Pixnet Z9/R9W/R9T Launcher 教學（僅操作流程線索）](https://newguest88.pixnet.net/blog/posts/945618081727712042)
