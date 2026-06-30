#!/bin/bash
# 下载 BlurBall 及各 baseline 的预训练权重 (从作者公开 Nextcloud 分享)。
# 自包含: 权重落到本仓库 pretrained_weights/ 下 (与 src/setup_scripts/setup_weights.sh 约定一致)。
#
# 用法: bash scripts/download_models.sh [proxy]
#   proxy: baidu (默认) | aliyun
#
# 可选环境变量:
#   BLURBALL_WEIGHTS_DIR  权重目录 (默认 <repo>/pretrained_weights)
#
# 说明:
#   作者把权重放在 Nextcloud 公共分享 (无 license 门槛, 可 WebDAV 直链下载):
#     https://cloud.cs.uni-tuebingen.de/index.php/s/6Z8TpM3sXRKHzGC
#   本脚本自动列出分享内全部文件并逐个下载 (缺啥下啥, 已存在则跳过)。
#   主权重: blurball_best (BlurBall 模型)。其余为 WASB/TrackNetV2/DeepBall 等 baseline。
#   数据集 (含 license, 不在本脚本范围) 见: https://cloud.cs.uni-tuebingen.de/index.php/s/C3pJEPKWQAkono7
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WEIGHTS_DIR="${BLURBALL_WEIGHTS_DIR:-$REPO_ROOT/pretrained_weights}"
PROXY="${1:-baidu}"

if [ "$PROXY" = "aliyun" ]; then
    export https_proxy=http://njxg-banqian20230721-sousuo00230.njxg:3231/
    export http_proxy=http://njxg-banqian20230721-sousuo00230.njxg:3231/
else
    export https_proxy=http://agent.baidu.com:8188
    export http_proxy=http://agent.baidu.com:8188
fi

# Nextcloud 公共分享: share token 作为 WebDAV basic-auth 用户名, 密码空。
NC_HOST="https://cloud.cs.uni-tuebingen.de"
NC_TOKEN="6Z8TpM3sXRKHzGC"
NC_DAV="$NC_HOST/public.php/webdav"

echo "[proxy] $PROXY"
echo "[paths] WEIGHTS_DIR=$WEIGHTS_DIR"
echo "[source] Nextcloud share $NC_TOKEN"

command -v curl >/dev/null 2>&1 || { echo "[ERROR] 需要 curl"; exit 1; }
DL="wget"; command -v aria2c >/dev/null 2>&1 && DL="aria2c"
echo "[downloader] $DL"

mkdir -p "$WEIGHTS_DIR"

# ---- 列出分享内全部文件 (WebDAV PROPFIND) ----
echo "[list] 列举分享内文件 ..."
LIST_XML="$(curl -s -m 60 -X PROPFIND -u "$NC_TOKEN:" "$NC_DAV/" -H "Depth: 1" 2>/dev/null || true)"
# 取所有 href, 去掉根 (/public.php/webdav/), 提取文件名
FILES="$(echo "$LIST_XML" \
    | grep -oE "<d:href>[^<]*</d:href>" \
    | sed -E 's#</?d:href>##g' \
    | sed -E 's#^/public.php/webdav/?##' \
    | grep -vE '^$' || true)"

if [ -z "$FILES" ]; then
    echo "============================================================"
    echo " [!] 无法列出 Nextcloud 分享内容 (代理/网络不通?)"
    echo
    echo "   手动下载: $NC_HOST/index.php/s/$NC_TOKEN"
    echo "   把文件放到: $WEIGHTS_DIR/"
    echo "   (主权重文件名: blurball_best)"
    echo
    echo "   另: 各 baseline 权重也可用仓库自带脚本从 Google Drive 下 (需 gdown, 国内成功率低):"
    echo "     source $WEIGHTS_DIR/../<env>/bin/activate && cd src && bash setup_scripts/setup_weights.sh"
    echo "============================================================"
    exit 1
fi

echo "[list] 发现文件:"
echo "$FILES" | sed 's/^/    /'

# ---- 逐个下载 ----
dl_one() {  # $1=filename
    local name="$1"
    local dst="$WEIGHTS_DIR/$name"
    local url="$NC_DAV/$name"
    if [ -s "$dst" ]; then
        echo "[skip] $name 已存在 ($(du -h "$dst" | cut -f1))"
        return 0
    fi
    echo "[down] $name -> $dst"
    if [ "$DL" = "aria2c" ]; then
        aria2c -x 8 -s 8 -k 1M --file-allocation=none --console-log-level=warn \
               --http-user="$NC_TOKEN" --http-passwd="" \
               -d "$WEIGHTS_DIR" -o "$name" "$url" \
            || { echo "[ERROR] 下载失败: $name"; rm -f "$dst" "$dst.aria2"; return 1; }
    else
        wget -q --show-progress --user="$NC_TOKEN" --password="" \
             -O "$dst" "$url" \
            || { echo "[ERROR] 下载失败: $name"; rm -f "$dst"; return 1; }
    fi
}

FAIL=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    dl_one "$f" || FAIL=1
done <<< "$FILES"

echo
echo "[weights] 当前权重目录:"
find "$WEIGHTS_DIR" -maxdepth 1 -type f -printf '  %p  (%s bytes)\n' 2>/dev/null | sort

echo
if [ -s "$WEIGHTS_DIR/blurball_best" ]; then
    echo "[ok] 主权重 blurball_best 已就位 ✓"
    echo "     推理: bash scripts/run_inference.sh <video.mp4> $WEIGHTS_DIR/blurball_best"
else
    echo "[!] 主权重 blurball_best 未就位; 检查上面的下载日志或手动下:"
    echo "    $NC_HOST/index.php/s/$NC_TOKEN"
fi
[ "$FAIL" = "0" ] || echo "[warn] 部分文件下载失败, 重跑本脚本会自动续下缺失项。"
