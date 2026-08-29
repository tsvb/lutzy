# LUT corpus source audit

- Active renderable LUTs: 1876
- Exact transform duplicates skipped: 115
- Unsupported inputs retained outside the active root: 115

## Input profiles

- ARRI LogC: 7
- ARRI LogC4: 8
- Apple Log: 1
- Blackmagic Film: 28
- Blackmagic Film Gen 5: 2
- Canon C-Log: 20
- Canon C-Log 2: 40
- Canon C-Log 3: 41
- DJI D-Log: 27
- DJI D-Log M: 1
- Display / Rec.709: 303
- Fujifilm F-Log: 27
- Fujifilm F-Log2: 16
- GoPro GP-Log: 4
- GoPro Protune: 1
- Nikon N-Log: 12
- Panasonic STD: 8
- Panasonic V-Log: 105
- RED Log3G10: 9
- Sony S-Log: 24
- Sony S-Log2: 16
- Sony S-Log3: 61
- Unknown: 1115

## Visual clusters

- 中性平淡: 192
- 中性濃豔: 173
- 中性自然: 141
- 暖褐／咖啡: 217
- 紅暖: 28
- 紫洋紅: 92
- 藍冷: 314
- 青綠: 255
- 黃綠: 370
- 黑白: 94

## Sources

### Cine LUTs Free (`cine-luts-free`)

Cine LUTs Free 創意套件；隨附說明僅確認一般剪輯軟體使用方式，未指定 Input Profile 或可再散布授權。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### CINECOLOR downloaded collection (`cinecolor`)

來自 CINECOLOR.IO 的創意調色 LUT；保留原始套件／Look 名稱，輸入色彩空間未由隨附安裝文件明確指定。

- Reference: https://www.cinecolor.io
- License/status: Downloaded third-party assets; redistribution rights not established; do not publish

### Claude-generated LUTs (`claude-generated`)

Claude 產生；為 LUMIX S9 建立的 V-Log/V-Gamut 至 Rec.709/sRGB 完成色 LUT。

- Reference: local project: code_ground/claude lut
- License/status: Project-generated; publication status to be confirmed

### Documents LUT collection (`documents-collection`)

使用者本機 Documents/luts 收藏；原始作者、下載網址與再散布授權等待使用者補充，不在此階段猜測。

- Reference: Pending user-supplied reference
- License/status: Pending source-by-source review; do not publish

### Downloaded LUT pack (unresolved) (`downloaded-unresolved`)

下載集合中尚未能由隨附檔案確認製作者的套件；保留原資料夾名稱，不猜測作者、Input Profile 或授權。

- Reference: Pending user-supplied reference
- License/status: Pending source-by-source review; do not publish

### FilterGrade Free Film Tone LUTs (`filtergrade-film-tone`)

FilterGrade 免費 Film Tone 套件；來源由下載資料夾名稱明確標示，Input Profile 未明示。

- Reference: https://filtergrade.com
- License/status: Downloaded third-party assets; redistribution rights pending

### FilterGrade Free Cine LUTs Pack v2 (`filtergrade-free-cine-v2`)

FilterGrade Free Cine LUTs Pack v2；隨附支援文件指向 filtergrade.com，重複軟體格式只保留不同 transform。

- Reference: https://filtergrade.com
- License/status: Downloaded third-party assets; redistribution rights pending

### Free Warm Tone LUTs (`free-warm-tone`)

Free Warm Tone LUTs 創意暖調套件；來源網址、Input Profile 與再散布權利待補。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### FREEMIUM 14 (`freemium-14`)

FREEMIUM 14 創意 LUT 套件；名稱保留原始 Look，來源網址與 Input Profile 待補。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### G'MIC Film LUTs Collection (`gmic-film-luts`)

來自 GitHub 專案 YahiaAngelo/Film-Luts（G'MIC Film LUTs Collection）。上游以 MIT 提供，但 README 提醒個別 LUT 可能另有權利；發佈二進位 corpus 前仍需複核。

- Reference: https://github.com/YahiaAngelo/Film-Luts
- License/status: MIT repository; individual-LUT rights require review

### Hollywood LUT Color Pack (`hollywood-lut-color-pack`)

以電影片名命名的 Hollywood LUT Color Pack；片名視為 Look 參考，不宣稱與片商或原作有官方關係。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### PremiumBeat Wanderlust (`premiumbeat-wanderlust`)

PremiumBeat Wanderlust 17 Free LUTs；隨附授權禁止轉售、轉移、分享或單獨提供原始 LUT。

- Reference: local package: Wanderlust License and Guide.pdf
- License/status: Local use only for this corpus; do not publish or redistribute

### Print Film Emulation LUTs (`print-film-emulation`)

Rec.709 輸入的 Kodak／Fujifilm print-film emulation LUT；品牌由檔名中的底片廠牌判定。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### SmallHD Movie Looks 2 (`smallhd-movie-looks-2`)

SmallHD Movie Looks 2 多相機套件；Look 名稱跨相機重複，Canon、Sony、Panasonic、ARRI 等資料夾作為 Input Profile 證據。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### Free LUTs for Super 8 Footage (`super8-footage`)

Super 8 Footage 日光／夜間創意套件；保留底片與時段標籤，Input Profile 未明示。

- Reference: Pending user-supplied reference
- License/status: Downloaded third-party assets; reference and redistribution rights pending

### V-Log Alchemy (`vlog-alchemy`)

來自 GitHub 專案 shenmintao/V-Log-Alchemy；將 V-Log/V-Gamut 轉為多家相機與底片方向的完成色 LUT。

- Reference: https://github.com/shenmintao/V-Log-Alchemy
- License/status: Apache-2.0

## Skipped duplicate paths

- `Documents/luts/test/DJI/ZENMUSE_X9/DJI_ZENMUSE_X9_DLog_To_Rec709.cube` → `LUTs/DJI/Standard LUTs/D-Log to Rec.709 V1.cube`
- `Documents/luts/test/Fujifilm/F-Log2C_LUT_E_Ver.1.00/X-H2/XH2_FLog2C_FGamutC_to_FLog2C_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2C_LUT_E_Ver.1.00/GFX100II/GFX100II_FLog2C_FGamutC_to_FLog2C_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2C_LUT_E_Ver.1.00/X-H2/XH2_FLog2C_FGamutC_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2C_LUT_E_Ver.1.00/GFX100II/GFX100II_FLog2C_FGamutC_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2C_LUT_E_Ver.1.00/X-H2S/XH2S_FLog2C_FGamutC_to_FLog2C_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2C_LUT_E_Ver.1.00/GFX100II/GFX100II_FLog2C_FGamutC_to_FLog2C_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2C_LUT_E_Ver.1.00/X-H2S/XH2S_FLog2C_FGamutC_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2C_LUT_E_Ver.1.00/GFX100II/GFX100II_FLog2C_FGamutC_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100SII/GFX100SII_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100SII/GFX100SII_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100SII/GFX100SII_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100SII/GFX100SII_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2S/XH2S_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2S/XH2S_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-M5/XM5_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2S/XH2S_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-M5/XM5_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2S/XH2S_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-M5/XM5_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-M5/XM5_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-S20/XS20_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2S/XH2S_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-S20/XS20_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2S/XH2S_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-S20/XS20_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-S20/XS20_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T5/XT5_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T5/XT5_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T5/XT5_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T5/XT5_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T50/XT50_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T50/XT50_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T50/XT50_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-T50/XT50_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X100VI/X100VI_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X100VI/X100VI_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/X-H2/XH2_FLog2_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X100VI/X100VI_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_FLog2_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log2_LUT_E_Ver.1.07/X100VI/X100VI_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log2_LUT_E_Ver.1.07/GFX100II/GFX100II_FLog2_FGamut_to_WDR_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100II/GFX100II_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100II/GFX100II_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100S/GFX100S_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100S/GFX100S_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100S/GFX100S_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100S/GFX100S_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100SII/GFX100SII_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100II/GFX100II_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100SII/GFX100SII_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100II/GFX100II_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100SII/GFX100SII_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100SII/GFX100SII_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-E4/XE4_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-E4/XE4_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-E4/XE4_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2S/XH2S_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2S/XH2S_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-M5/XM5_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2S/XH2S_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-M5/XM5_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2S/XH2S_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-M5/XM5_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-M5/XM5_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-Pro3/XPro3_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-Pro3/XPro3_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-Pro3/XPro3_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S10/XS10_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-E4/XE4_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S10/XS10_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S10/XS10_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S10/XS10_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S20/XS20_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2S/XH2S_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S20/XS20_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2S/XH2S_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S20/XS20_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-S20/XS20_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T2/XT2_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H1/XH1_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T2/XT2_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H1/XH1_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T2/XT2_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H1/XH1_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T3/XT3_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T3/XT3_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T3/XT3_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30/XT30_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30/XT30_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30/XT30_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30II/XT30II_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-E4/XE4_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30II/XT30II_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30II/XT30II_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T30II/XT30II_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T4/XT4_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-E4/XE4_FLog_FGamut_to_ETERNA-BB_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T4/XT4_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T4/XT4_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T4/XT4_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T5/XT5_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T5/XT5_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T5/XT5_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T5/XT5_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T50/XT50_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T50/XT50_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T50/XT50_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X-T50/XT50_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100V/X100V_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100V/X100V_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100V/X100V_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100VI/X100VI_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_ETERNA-BB_BT.709_33gird_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100VI/X100VI_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/X-H2/XH2_FLog_FGamut_to_ETERNA_BT.709_33grid_V.1.00.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100VI/X100VI_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_FLog_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Fujifilm/F-Log_LUT_E_Ver.1.29/X100VI/X100VI_FLog_FGamut_to_WDR_BT.709_33grid_V.1.00.cube` → `LUTs/Fujifilm/F-Log_LUT_E_Ver.1.29/GFX100/GFX100_FLog_FGamut_to_WDR_BT.709_33grid_V.1.01.cube`
- `Documents/luts/test/Sony/Third-party LUTs from creators/Alister-Chapman-LUTs-Collection-V2/Blockbuster-LUTs/Camera LUT for FS7-F5-F55/Blockbuster-V2.cube` → `LUTs/Sony/Third-party LUTs from creators/Alister-Chapman-LUTs-Collection-V2/Blockbuster-LUTs/33x Grading (best compatibility)/Blockbuster-V2_0-Native.cube`
- `Documents/luts/test/Sony/venice s709 Monitor Look/s709Cubes/SL3SG3Ctos709.cube` → `LUTs/Sony/S-LOG 3 to standard color spaces/Slog3-S-Gamut3.Cine_To_s709_V200.cube`
- `Documents/luts/test/Sony/venice s709 Monitor Look/sP3Cubes/SL3SG3CtosP3D65.cube` → `LUTs/Sony/S-LOG 3 to standard color spaces/Slog3-S-Gamut3.Cine_To_sP3D65_V200.cube`
- `Documents/luts/test/Sony/venice s709 Monitor Look/sP3Cubes/SL3SG3CtosP3DCI.cube` → `LUTs/Sony/S-LOG 3 to standard color spaces/Slog3-S-Gamut3.Cine_To_sP3DCI_V200.cube`
- `Documents/luts/test/freshluts.com/BRUJERIA_LUT.cube` → `LUTs/FreshLUTs/b_over_lut.cube`
- `Documents/luts/test/freshluts.com/GreenSky.cube` → `LUTs/FreshLUTs/Black_Star.cube`
- `Downloaded Luts/lut unzip/hollywood-lut-color-pack/hollywood-lut-color-pack/LUT .cube Files/Avengers Endgame.cube` → `LUTs/FreshLUTs/Cinematic.cube`
- `Film-Luts/luts/bw/ilford_hps_800.cube` → `LUTs/G'MIC Film LUTs/bw/ilford_hp_5_plus_400.cube`
- `Film-Luts/luts/instant_pro/polaroid_669.cube` → `LUTs/G'MIC Film LUTs/colorslide/polaroid_669.cube`
- `Film-Luts/luts/instant_pro/polaroid_690.cube` → `LUTs/G'MIC Film LUTs/colorslide/polaroid_690.cube`
- `Film-Luts/luts/negative_new/kodak_tri-x_400.cube` → `LUTs/G'MIC Film LUTs/bw/kodak_tri-x_400.cube`
- `Film-Luts/luts/negative_old/fuji_neopan_1600.cube` → `LUTs/G'MIC Film LUTs/bw/fuji_neopan_1600.cube`
- `Film-Luts/luts/negative_old/ilford_delta_3200.cube` → `LUTs/G'MIC Film LUTs/bw/ilford_delta_3200.cube`
- `Film-Luts/luts/negative_old/kodak_portra_160_nc.cube` → `LUTs/G'MIC Film LUTs/negative_color/kodak_portra_160_nc.cube`
- `Film-Luts/luts/negative_old/kodak_portra_160_vc.cube` → `LUTs/G'MIC Film LUTs/negative_color/kodak_portra_160_vc.cube`
- `Film-Luts/luts/negative_old/kodak_portra_400_nc_+.cube` → `LUTs/G'MIC Film LUTs/negative_old/kodak_portra_160_nc_+.cube`
- `V-Log-Alchemy/Luts/Panasonic-Standard/Conversion/GH7S2V.cube` → `LUTs/Panasonic/V-Log Alchemy/Panasonic-Standard/Conversion/G9IIS2V.cube`
- `V-Log-Alchemy/Luts/Panasonic-Standard/Conversion/S5IIXS2V.cube` → `LUTs/Panasonic/V-Log Alchemy/Panasonic-Standard/Conversion/S5IIS2V.cube`

## Unsupported inputs

- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_10-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_10-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_10-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_10-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_10-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_10-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_12-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_12-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_12-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_12-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_12-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_12-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_16-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_16-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_16-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_16-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_16-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-full-range/CanonLog_16-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-linear-range/CanonLog_10-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-linear-range/CanonLog_10-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-linear-range/CanonLog_12-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-linear-range/CanonLog_12-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog-to-gamma-1dlut/full-to-linear-range/CanonLog_16-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog-to-gamma-1dlut/full-to-linear-range/CanonLog_16-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-HLG_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-HLG_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-PQ_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-PQ_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_10-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-HLG_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-HLG_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-PQ_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-PQ_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_12-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-HLG_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-HLG_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-PQ_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-PQ_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-full-range/CanonLog2_16-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-linear-range/CanonLog2_10-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-linear-range/CanonLog2_10-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-linear-range/CanonLog2_12-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-linear-range/CanonLog2_12-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog2-to-gamma-1dlut/full-to-linear-range/CanonLog2_16-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog2-to-gamma-1dlut/full-to-linear-range/CanonLog2_16-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-HLG_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-HLG_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-PQ_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-PQ_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_10-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-HLG_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-HLG_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-PQ_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-PQ_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_12-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-Cineon_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-Cineon_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-DCI_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-DCI_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-HLG_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-HLG_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-PQ_FF_Ver.2.1.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-PQ_FF_Ver.2.1.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-WideDR_FF_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-full-range/CanonLog3_16-to-WideDR_FF_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-linear-range/CanonLog3_10-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-linear-range/CanonLog3_10-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-linear-range/CanonLog3_12-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-linear-range/CanonLog3_12-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Canon/1dlut/canonlog3-to-gamma-1dlut/full-to-linear-range/CanonLog3_16-to-Linear_FL_Ver.2.0.cube` → `Unsupported/Canon/Documents Collection/1dlut/canonlog3-to-gamma-1dlut/full-to-linear-range/CanonLog3_16-to-Linear_FL_Ver.2.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DJI/Phantom_3_Dlog_3DLUT/DJI_Phantom3_DLOG2sRGB.cube` → `Unsupported/DJI/Documents Collection/Phantom_3_Dlog_3DLUT/DJI_Phantom3_DLOG2sRGB.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DJI/Standard LUTs/Linear to D-Log.cube` → `Unsupported/DJI/Documents Collection/Standard LUTs/Linear to D-Log.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DJI/Standard LUTs/gamma18TosRGB.cube` → `Unsupported/DJI/Documents Collection/Standard LUTs/gamma18TosRGB.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DJI/Standard LUTs/gamma22TosRGB.cube` → `Unsupported/DJI/Documents Collection/Standard LUTs/gamma22TosRGB.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/ACES/LMT ACES v0.1.1.cube` → `Unsupported/DaVinci Resolve/Documents Collection/ACES/LMT ACES v0.1.1.cube`: invalidFormat("Expected 274625 entries, got 278720")
- `Documents/luts/test/DaVinci Resolve/Astrodesign/ALog to ARRI Log C.cube` → `Unsupported/Astrodesign/Documents Collection/DaVinci Resolve/Astrodesign/ALog to ARRI Log C.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/Gamma 1.0 to HLG.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/Gamma 1.0 to HLG.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/Gamma 2.2 to HLG.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/Gamma 2.2 to HLG.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/Gamma 2.4 to HLG.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/Gamma 2.4 to HLG.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/Gamma 2.6 to HLG.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/Gamma 2.6 to HLG.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/HLG to Gamma 1.0.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/HLG to Gamma 1.0.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/HLG to Gamma 2.2.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/HLG to Gamma 2.2.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/HLG to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/HLG to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR Hybrid Log-Gamma/HLG to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR Hybrid Log-Gamma/HLG to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.4 to HDR 1000 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.4 to HDR 1000 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.4 to HDR 2000 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.4 to HDR 2000 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.4 to HDR 300 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.4 to HDR 300 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.4 to HDR 4000 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.4 to HDR 4000 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.4 to HDR 500 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.4 to HDR 500 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.4 to HDR 800 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.4 to HDR 800 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.6 to HDR 1000 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.6 to HDR 1000 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.6 to HDR 2000 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.6 to HDR 2000 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.6 to HDR 300 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.6 to HDR 300 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.6 to HDR 4000 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.6 to HDR 4000 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.6 to HDR 500 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.6 to HDR 500 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/Gamma 2.6 to HDR 800 nits.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/Gamma 2.6 to HDR 800 nits.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 1000 nits to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 1000 nits to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 1000 nits to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 1000 nits to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 2000 nits to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 2000 nits to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 2000 nits to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 2000 nits to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 300 nits to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 300 nits to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 300 nits to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 300 nits to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 4000 nits to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 4000 nits to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 4000 nits to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 4000 nits to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 500 nits to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 500 nits to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 500 nits to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 500 nits to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 800 nits to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 800 nits to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/HDR ST 2084/HDR 800 nits to Gamma 2.6.cube` → `Unsupported/DaVinci Resolve/Documents Collection/HDR ST 2084/HDR 800 nits to Gamma 2.6.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/ARRI LogC to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/ARRI LogC to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/BMDFilm 4.6K to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/BMDFilm 4.6K to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/BMDFilm 4K to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/BMDFilm 4K to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/BMDFilm to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/BMDFilm to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Cineon Log to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Cineon Log to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/DCI to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/DCI to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Gamma 2.2 to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Gamma 2.2 to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Gamma 2.4 to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Gamma 2.4 to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to ARRI LogC.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to ARRI LogC.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to BMDFilm 4.6K.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to BMDFilm 4.6K.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to BMDFilm 4K.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to BMDFilm 4K.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to BMDFilm.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to BMDFilm.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to Cineon Log.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to Cineon Log.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to DCI.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to DCI.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to Gamma 2.2.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to Gamma 2.2.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to Gamma 2.4.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to Gamma 2.4.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to Rec.709.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to Rec.709.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to sLog2.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to sLog2.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Linear to sRGB.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Linear to sRGB.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/Rec.709 to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/Rec.709 to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/sLog2 to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/sLog2 to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/DaVinci Resolve/VFX IO/sRGB to Linear.cube` → `Unsupported/DaVinci Resolve/Documents Collection/VFX IO/sRGB to Linear.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve10RLFtoRG3V3FR.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve10RLFtoRG3V3FR.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve10RLFtoRG3V3_1D.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve10RLFtoRG3V3_1D.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve10RLFtoRG4_1D.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve10RLFtoRG4_1D.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve12RLFtoRG3V3FR.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve12RLFtoRG3V3FR.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve12RLFtoRG3V3_1D.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve12RLFtoRG3V3_1D.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve12RLFtoRG4_1D.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve12RLFtoRG4_1D.cube`: invalidFormat("LUT_3D_SIZE not found")
- `Documents/luts/test/Nikon/RED/Resolve16RLFtoRG3V3FR.cube` → `Unsupported/Nikon/Documents Collection/RED/Resolve16RLFtoRG3V3FR.cube`: invalidFormat("LUT_3D_SIZE not found")

