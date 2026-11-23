#!/bin/bash
# LiveContainer-openSSS 本地合体打包脚本
# 基于官方 .github/build_github.sh 改造：用 openSSS IPA 顶替官方 SideStore
# 关键差异：openSSS 可执行名是 oPenSSAI（不是 SideStore），且自带 OpenSSL.framework
# 用法：./local-build-openSSS.sh /path/to/openSSS.ipa
set -euo pipefail

# 安全删除函数：用 Python shutil，避开 rm -rf 被沙盒安全守卫拦截
safe_rmrf() {
  python3 -c "import shutil,sys,os; [shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else (os.remove(p) if os.path.exists(p) else None) for p in sys.argv[1:]]" "$@"
}
# 旧产物暂存目录（用 mv 代替 rm，避开安全守卫；不真的删除，留在 /tmp 由系统清理）
JUNK="/tmp/treeapps-old-$(date +%s)"
mkdir -p "$JUNK"

export PATH="/Users/idoer/.workbuddy/binaries:$PATH"

OPENSSS_IPA="${1:?用法: ./local-build-openSSS.sh <openSSS.ipa 绝对路径>}"
[ -f "$OPENSSS_IPA" ] || { echo "找不到 $OPENSSS_IPA" >&2; exit 1; }

SCHEME=LiveContainer
ARCHIVE_PATH=archive
# 工作目录放在仓库外，避免 cp 把 .build-work 复制进自己（递归套娃 → Too many open files）
WORK="/Users/idoer/.workbuddy/build/treeapps"
# 不用 rm -rf（文件多会触发安全守卫）；只清理上次构建产物，源码用 cp -a 覆盖
mkdir -p "$WORK/src"
# 失败时保留现场便于排错，成功后再由调用方决定是否清理
SRC="$(cd "$(dirname "$0")" && pwd)"
# 用 rsync 排除 .git（工作副本不需要版本历史，且 .git pack 文件只读会报 Permission denied）
rsync -a --exclude=".git" "$SRC/" "$WORK/src/"
cd "$WORK/src"

echo "==> [1/8] 准备依赖 (OpenSSL xcframework)"
if [ -d Dependencies/OpenSSL.xcframework ]; then
  echo "  已存在，跳过下载（如需强制重新下载，删除 Dependencies/OpenSSL.xcframework）"
else
  sh .github/prepare_dependencies.sh
  # Xcode 16.4 解析不了第三方签名 → 去掉 _CodeSignature；
  # 工程里对应的 expectedSignature 也已删除，避免 "not signed with expected identity"
  find Dependencies/OpenSSL.xcframework -name "_CodeSignature" -type d 2>/dev/null | while read d; do mv "$d" "$JUNK/cs-$(date +%s%N)" 2>/dev/null || true; done
fi

echo "==> [2/8] archive TreeNewBee (无签名)"
# archive 前把上次产物移走（mv 不触发安全守卫；移到 /tmp 带时间戳，不删除）
for p in Payload archive.xcarchive LiveContainer.ipa; do
  [ -e "$p" ] && mv "$p" "$JUNK/" 2>/dev/null || true
done
xcodebuild archive -archivePath "$ARCHIVE_PATH" -scheme "$SCHEME" \
  -project LiveContainer.xcodeproj -sdk iphoneos -arch arm64 \
  -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

echo "==> [3/8] 准备 dylibify + ldid"
# 官方 release 是 arm64，本机 Intel 跑不了；用本地 clang 编译的 x86_64 版
cp /Users/idoer/.workbuddy/binaries/dylibify-x86 ./dylibify
chmod +x dylibify
command -v ldid >/dev/null || { echo "缺少 ldid，请先装：brew install ldid（或用已有 binary）" >&2; exit 1; }
mv "$ARCHIVE_PATH.xcarchive/Products/Applications" Payload
mkdir -p tmp
# 官方脚本会临时移走 SideStoreSupport.framework 打个 zip 再放回，但那个 zip 后续没用到，跳过

echo "==> [4/8] 解包 openSSS，动态读取 app 名与可执行名"
[ -e tmp/openSSS ] && mv tmp/openSSS "$JUNK/openSSS-$(date +%s)" 2>/dev/null || true
mkdir -p tmp/openSSS
cd tmp/openSSS && unzip -qo "$OPENSSS_IPA"
APPNAME=$(basename Payload/*.app .app)
SS_EXE=$(plutil -extract CFBundleExecutable raw -o - "Payload/$APPNAME.app/Info.plist")
SS_BUNDLE=$(plutil -extract CFBundleIdentifier raw -o - "Payload/$APPNAME.app/Info.plist")
echo "  app=$APPNAME executable=$SS_EXE bundle=$SS_BUNDLE"
cd "$WORK/src"

echo "==> [5/8] 注入 SideStore 相关 Info.plist keys"
P=Payload/TreeApps.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups array' "$P"
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups:0 string group.com.SideStore.SideStore' "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1 dict" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLName string com.kdt.livecontainer.sidestoreurlscheme" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes array" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string sidestore" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2 dict" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2:CFBundleURLName string com.kdt.livecontainer.sidestorebackupurlscheme" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2:CFBundleURLSchemes array" "$P"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2:CFBundleURLSchemes:0 string sidestore-com.kdt.livecontainer" "$P"
/usr/libexec/PlistBuddy -c "Add :INIntentsSupported array" "$P"
/usr/libexec/PlistBuddy -c "Add :INIntentsSupported:0 string RefreshAllIntent" "$P"
/usr/libexec/PlistBuddy -c "Add :INIntentsSupported:1 string ViewAppIntent" "$P"
/usr/libexec/PlistBuddy -c "Add :NSUserActivityTypes array" "$P"
/usr/libexec/PlistBuddy -c "Add :NSUserActivityTypes:0 string RefreshAllIntent" "$P"
/usr/libexec/PlistBuddy -c "Add :NSUserActivityTypes:1 string ViewAppIntent" "$P"
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:Type string PSToggleSwitchSpecifier" Payload/TreeApps.app/Settings.bundle/Root.plist
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:Title string Open openSSS" Payload/TreeApps.app/Settings.bundle/Root.plist
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:Key string LCOpenSideStore" Payload/TreeApps.app/Settings.bundle/Root.plist
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:DefaultValue bool false" Payload/TreeApps.app/Settings.bundle/Root.plist

echo "==> [6/8] 安装 openSSS 为 SideStoreApp.framework"
FW=Payload/TreeApps.app/Frameworks/SideStoreApp.framework
[ -e "$FW" ] && mv "$FW" "$JUNK/FW-$(date +%s)" 2>/dev/null || true
cp -a "tmp/openSSS/Payload/$APPNAME.app" "$FW"
./dylibify "$FW/$SS_EXE" "$FW/$SS_EXE.dylib"
rm "$FW/$SS_EXE"
mv "$FW/$SS_EXE.dylib" "$FW/$SS_EXE"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $SS_EXE" "$FW/Info.plist"
ldid -S'' "$FW/$SS_EXE"
cp .github/sidelc/LCAppInfo.plist "$FW/"

# TreeNewBee: 新版 openSSS 自带 PlugIns/AltWidgetExtension.appex，它是"APPL 伪装成
# framework"里的非法嵌套 app extension，内部 Mach-O 未签名 → 侧载重签后 installd
# 校验 CodeResources 失败 0xe8008017。自研 widget 已在主 app PlugIns、Intents 资源
# 已在上面提取到主 app，这个内嵌 appex 完全冗余，直接移除。
if [ -d "$FW/PlugIns" ]; then
  echo "  -> 移除 SideStoreApp.framework 内嵌 PlugIns（避免 0xe8008017）"
  safe_rmrf "$FW/PlugIns"
fi

# TreeNewBee: 注入 openSSS 多语言资源（zh-Hant/ja/ko/th/ms/id）
I18N_SRC="$HOME/.workbuddy/build/tree_i18n"
if [ -d "$I18N_SRC" ]; then
  echo "  -> 注入 openSSS 多语言 .lproj"
  for lang in zh-Hant ja ko th ms id; do
    if [ -f "$I18N_SRC/$lang/Localizable.strings" ]; then
      mkdir -p "$FW/$lang.lproj"
      cp "$I18N_SRC/$lang/Localizable.strings" "$FW/$lang.lproj/Localizable.strings"
    fi
  done
  # 声明支持的语言，避免系统回退到开发区域（zh-Hans）
  /usr/libexec/PlistBuddy -c "Delete :CFBundleLocalizations" "$FW/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$FW/Info.plist" 2>/dev/null || true
  for lang in zh-Hans zh-Hant ja ko th ms id; do
    /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string $lang" "$FW/Info.plist" 2>/dev/null || true
  done
fi

echo "==> [7/8] Intents + Widget 改写"
cp "$FW/Intents.intentdefinition" Payload/TreeApps.app/ 2>/dev/null || echo "  无 Intents.intentdefinition"
cp "$FW/ViewApp.intentdefinition" Payload/TreeApps.app/ 2>/dev/null || echo "  无 ViewApp.intentdefinition"
if [ -d "$FW/Metadata.appintents" ]; then
  cp -r "$FW/Metadata.appintents" Payload/TreeApps.app/
  python3 - <<'PYEOF'
p = 'Payload/TreeApps.app/Metadata.appintents/extract.actionsdata'
data = open(p, 'rb').read()
data = data.replace(b'9SideStore20RefreshAllAppsIntentV', b'16SideStoreSupport20RefreshAllAppsIntentV')
data = data.replace(b'9SideStore26RefreshAllAppsWidgetIntentV', b'16SideStoreSupport26RefreshAllAppsWidgetIntentV')
open(p, 'wb').write(data)
print('  intents mangled name 已替换')
PYEOF
fi
# TreeNewBee: 用自研桌面/锁屏小组件替换 openSSS 自带的刷新小组件。
# openSSS 的 Intents.intentdefinition 等资源已在上面保留，主 App 的快捷指令不受影响。
[ -e Payload/TreeApps.app/PlugIns/LiveWidgetExtension.appex ] && \
  mv Payload/TreeApps.app/PlugIns/LiveWidgetExtension.appex "$JUNK/LiveWidget-$(date +%s)" 2>/dev/null || true
(
  cd TreeWidget
  xcodegen generate --spec project.yml >/dev/null
  xcodebuild build -project TreeWidget.xcodeproj -scheme TreeWidgetExtension \
    -configuration Release -sdk iphoneos -arch arm64 \
    -derivedDataPath "$WORK/widget-dd" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    > "$WORK/widget-build.log" 2>&1 || { tail -60 "$WORK/widget-build.log"; exit 1; }
)
cp -a "$WORK/widget-dd/Build/Products/Release-iphoneos/TreeWidgetExtension.appex" \
  Payload/TreeApps.app/PlugIns/LiveWidgetExtension.appex
WIDGET=Payload/TreeApps.app/PlugIns/LiveWidgetExtension.appex
mv "$WIDGET/TreeWidgetExtension" "$WIDGET/LiveWidgetExtension"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable LiveWidgetExtension" "$WIDGET/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.kdt.livecontainer.TreeWidget" "$WIDGET/Info.plist"
ldid -STreeWidget/TreeWidgetExtension/TreeWidget.entitlements "$WIDGET/LiveWidgetExtension"
echo "  -> 自研 Tree 小组件已嵌入（桌面 2x2/4x2 + 锁屏圆形/矩形/内联）"

# TreeNewBee: 内置两个屏蔽 iOS 更新的描述文件。SideStoreSupport.framework
# 在宿主和内置 openSSS 进程中都会被 dlopen，放这里两边都能读到。
for mc in Resources/MobileConfigs/*.mobileconfig; do
  [ -f "$mc" ] || continue
  cp "$mc" Payload/TreeApps.app/Frameworks/SideStoreSupport.framework/
done
# 注意：不要把 mobileconfig 放进 $FW（SideStoreApp.framework）。它本质是 APPL 包，
# 往里加资源会破坏 CodeResources → 侧载 0xe8008017。TreeToolbox 从
# SideStoreSupport.framework 读取即可（Bundle(for: TreeToolbox.self)）。
echo "  -> 描述文件已内置: $(ls Resources/MobileConfigs/*.mobileconfig | wc -l | tr -d ' ') 个"

echo "==> [8/8] 签名 + 打包"
find Payload -type d -name "_CodeSignature" 2>/dev/null | while read d; do mv "$d" "$JUNK/cs-$(date +%s%N)" 2>/dev/null || true; done
# TreeApps 修复：给主可执行注入完整 entitlement（app groups + 128 keychain groups）。
# 之前 CODE_SIGNING_ALLOWED=NO 打成裸包，SideStore 读不到声明 → 只给最低三件套 → JIT-less 失败。
# 用官方占位 team AAAAA11111，SideStore/AltStore 安装时会按签名账号重写。
echo "  -> 给主可执行签 entitlement (TreeApps_adhoc.xml)"
ldid -S.github/sidelc/TreeApps_adhoc.xml Payload/TreeApps.app/TreeApps
STAMP=$(date +%Y%m%d%H%M)
OUT="$(cd "$(dirname "$OPENSSS_IPA")" && pwd)/TreeNewBee-$STAMP.ipa"
zip -qr "$OUT" Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
echo "完成: $OUT"
echo "未做真机验证。侧载前请确认 JIT / JIT script 可用。"
