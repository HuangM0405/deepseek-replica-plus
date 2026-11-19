#!/usr/bin/env bash
# 一键构建 DeepSeek 网页版复刻的 Android debug APK
# 用法: bash build-apk.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

RUNTIME="C:/Users/Chang/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies"
NODE="$RUNTIME/node/bin/node.exe"
PNPM_JS="$RUNTIME/pnpm/bin/pnpm.mjs"
SDK_WIN='C:\\Users\\Chang\\AppData\\Local\\Android\\Sdk'
SDK_MSYS='/c/Users/Chang/AppData/Local/Android/Sdk'
GRADLE_VERSION='9.7.1'
# Windows 上的 gradle 启动脚本无法处理含中文的安装路径，故放到用户主目录下的纯 ASCII 路径；
# 且必须以 MSYS 形式 (/c/...) 传给 gradle，否则脚本会拼出 C;\Users\... 的畸形 classpath。
# /tmp 在本机映射到 C:/Users/<user>/AppData/Local/Temp（纯 ASCII），gradle 启动脚本在该路径下工作正常；
# 放在用户目录 (/c/Users/...) 反而会被 cygpath 拼出 C;\Users... 的畸形路径，故固定用 /tmp。
TOOLS_ASCII="${DSH_BUILD_TOOLS:-/tmp/dsh-build-tools}"
GRADLE_DIR="$TOOLS_ASCII/gradle-$GRADLE_VERSION"
GRADLE_MIRROR="https://mirrors.cloud.tencent.com/gradle/gradle-$GRADLE_VERSION-bin.zip"

log() { printf '\n==> %s\n' "$*"; }

# 1. JDK 21
if [ ! -x "${JAVA_HOME:-/nonexistent}/bin/java.exe" ]; then
  for candidate in 'D:/Java/jdk-21.0.11' 'C:/Java/jdk-21.0.11'; do
    if [ -x "$candidate/bin/java.exe" ]; then export JAVA_HOME="$candidate"; break; fi
  done
fi

[ -n "${JAVA_HOME:-}" ] || { echo 'JAVA_HOME 未设置，请安装 JDK 21 并 export JAVA_HOME'; exit 1; }
log "JAVA_HOME=$JAVA_HOME"

# 2. pnpm（Android buildWeb 任务在 cmd 里调用 pnpm）
PNPM_BIN_DIR="$TOOLS_ASCII/bin"
mkdir -p "$PNPM_BIN_DIR"
# cmd 垫片必须自己生成并放在 PATH 最前面：printf 里 %* 要写成 %%*，
# 否则 cmd 会收到 "\\build" 这样的参数（曾导致 buildWeb 报 Command "\\build" not found）。
printf '@echo off\r\n"%s" "%s" %%*\r\n' "$NODE" "$PNPM_JS" > "$PNPM_BIN_DIR/pnpm.cmd"
export PATH="$PNPM_BIN_DIR:/c/Users/Chang/.dsh/bin:$PATH"
log "pnpm=$PNPM_BIN_DIR/pnpm.cmd"
"$NODE" "$PNPM_JS" --version

# 3. Gradle（官方 dist 在 GitHub 上很慢，用腾讯镜像）
if [ ! -x "$GRADLE_DIR/bin/gradle" ]; then
  mkdir -p "$TOOLS_ASCII"
  ZIP="$TOOLS_ASCII/gradle-$GRADLE_VERSION-bin.zip"
  [ -f "$ZIP" ] || { log '下载 Gradle 9.7.1 (腾讯镜像)'; curl -fL --retry 3 -o "$ZIP" "$GRADLE_MIRROR"; }
  log '解压 Gradle'
  ( cd "$TOOLS_ASCII" && "$JAVA_HOME/bin/jar" xf "$ZIP" )
fi
log "gradle=$GRADLE_DIR/bin/gradle"

# 4. Android SDK
export ANDROID_HOME="${ANDROID_HOME:-$SDK_MSYS}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
[ -d "$ANDROID_HOME/platforms/android-37" ] || [ -d "$ANDROID_HOME/platforms/android-37.0" ] || { echo "SDK 缺少 platform 37: $ANDROID_HOME"; exit 1; }
if [ ! -f "$ROOT/android/local.properties" ]; then
  printf 'sdk.dir=%s\n' "$SDK_WIN" > "$ROOT/android/local.properties"
fi

# 5. Web 资源
if [ ! -d "$ROOT/node_modules" ]; then
  log '安装前端依赖'
  "$NODE" "$PNPM_JS" install --frozen-lockfile
fi

# 6. 构建 APK（路径含中文，必须覆盖 AGP 的路径检查）
# 说明：不用 bin/gradle 启动脚本 —— 在 MSYS 下它会把 -jar 参数里的盘符冒号
# 错误地当成路径分隔符（C:/... 变成 C;/...），报 Unable to access jarfile。
# 直接调用 java -jar 启动 Gradle 的 CLI main，路径一律传 Windows 形式。
log 'Gradle assembleDebug'
GRADLE_LIB_W="$(cygpath -w "$GRADLE_DIR/lib")"
"$JAVA_HOME/bin/java" -Xmx64m -Xms64m \
  "-javaagent:$GRADLE_LIB_W/agents/gradle-instrumentation-agent-$GRADLE_VERSION.jar" \
  -Dorg.gradle.appname=gradle \
  -jar "$GRADLE_LIB_W/gradle-gradle-cli-main-$GRADLE_VERSION.jar" \
  -p "$ROOT/android" assembleDebug --no-daemon --console=plain -Pandroid.overridePathCheck=true

APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
[ -f "$APK" ] || { echo '未找到 APK 产物'; exit 1; }
cp "$APK" "$ROOT/DeepSeekReplica-0.4.0-debug.apk"
log "完成: $ROOT/DeepSeekReplica-0.4.0-debug.apk ($(wc -c < "$APK") 字节)"
