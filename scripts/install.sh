#!/bin/bash
# BlurBall 一键安装 (虚拟环境 + 推理/训练依赖)
# 自包含: 仅依赖本仓库自身, 路径从脚本位置自动推导。
#
# 用法: bash scripts/install.sh [proxy]
#   proxy: baidu (默认, GIT/PIP 国内/torch 快) | aliyun
#
# 可选环境变量 (不设则用默认):
#   BLURBALL_ENV_DIR  虚拟环境路径 (默认见下方; 换机器/换人请改这里或设此变量)
#   CUDA_HOME         CUDA 安装路径 (默认 /usr/local/cuda)
#
# 装完后还需: (1) bash scripts/download_models.sh  下/补权重
#             (2) bash scripts/run_inference.sh <video>  跑推理
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# 默认指向本机现有环境; 别人换机器改这里或设 BLURBALL_ENV_DIR。
ENV_DIR="${BLURBALL_ENV_DIR:-/root/paddlejob/workspace/env_run/penghaotian/envs/blurball}"
PROXY="${1:-baidu}"

# 代理 (本环境专用; 换网络环境请改这里或自行 export http(s)_proxy)
if [ "$PROXY" = "aliyun" ]; then
    export https_proxy=http://njxg-banqian20230721-sousuo00230.njxg:3231/
    export http_proxy=http://njxg-banqian20230721-sousuo00230.njxg:3231/
    PIP_INDEX="https://mirrors.aliyun.com/pypi/simple/"
else
    export https_proxy=http://agent.baidu.com:8188
    export http_proxy=http://agent.baidu.com:8188
    PIP_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple/"
fi
echo "[proxy] $PROXY  PIP_INDEX=$PIP_INDEX"
echo "[paths] REPO_ROOT=$REPO_ROOT  ENV_DIR=$ENV_DIR"

# CUDA (torch 用 cu121 预编译 wheel, 这里仅保证 nvcc 可见)
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
echo "[cuda] CUDA_HOME=$CUDA_HOME"

command -v uv >/dev/null 2>&1 || { echo "[ERROR] 需要 uv, 先装: https://docs.astral.sh/uv/"; exit 1; }

echo "[1/6] 创建虚拟环境 (python 3.10)"
uv venv "$ENV_DIR" --python 3.10 2>/dev/null || true
PYTHON="$ENV_DIR/bin/python"
UV_INSTALL="uv pip install --python $PYTHON --link-mode=copy"

echo "[2/6] 基础构建工具 pip/wheel/setuptools"
$UV_INSTALL pip wheel "setuptools>=68.0" -i "$PIP_INDEX"

echo "[3/6] PyTorch 2.3.0 + torchvision 0.18.0 (cu121, 含 sm_90/Hopper, 以跑通为准)"
$UV_INSTALL torch==2.3.0 torchvision==0.18.0 --index-url https://download.pytorch.org/whl/cu121

echo "[4/6] 其余依赖 (来自 requirements.txt, 剔除 torch* 以保留上面的 cu121 版本)"
# requirements.txt 里钉死 torch==2.2.2/torchvision==0.17.2/torchaudio==2.2.2,
# 会把 torch 回退到旧 cuda; 这里过滤掉这三行, 其余照装。
REQ_TMP="$(mktemp)"
grep -v -E '^(torch|torchvision|torchaudio)==' "$REPO_ROOT/requirements.txt" > "$REQ_TMP"
$UV_INSTALL -i "$PIP_INDEX" -r "$REQ_TMP"
rm -f "$REQ_TMP"

echo "[5/6] 修正配置里的硬编码路径 WASB_ROOT (原作者路径 -> 本仓库根)"
# 仅用于 hydra 输出目录 ${WASB_ROOT}/outputs/...; 不改会写到不存在的路径。
# 幂等: 只在仍是旧路径时替换。
OLD_ROOT="/home/gossard/Git/blurball"
if grep -rl "WASB_ROOT: $OLD_ROOT" "$REPO_ROOT/src/configs" >/dev/null 2>&1; then
    grep -rl "WASB_ROOT: $OLD_ROOT" "$REPO_ROOT/src/configs" | while read -r f; do
        sed -i "s#WASB_ROOT: $OLD_ROOT#WASB_ROOT: $REPO_ROOT#g" "$f"
        echo "  patched $f"
    done
else
    echo "  WASB_ROOT 已是本仓库根 (或无需修改)"
fi

echo "[6/6] 配置 activate (PYTHONPATH 指向 src, 开启 HYDRA_FULL_ERROR)"
# 仓库无 setup.py, 不做 editable; 用 PYTHONPATH 让 python src/main.py 在任意目录可跑。
ACTIVATE="$ENV_DIR/bin/activate"
if ! grep -q "BlurBall env" "$ACTIVATE"; then
    {
        echo ""
        echo "# BlurBall env (PYTHONPATH 指向 src; hydra 全错误栈)"
        echo "export PYTHONPATH=\"$REPO_ROOT/src:\${PYTHONPATH:-}\""
        echo "export HYDRA_FULL_ERROR=1"
    } >> "$ACTIVATE"
fi

echo
echo "============================================================"
echo " 依赖安装完成"
echo " 虚拟环境: $ENV_DIR"
echo " 仓库根:   $REPO_ROOT (WASB_ROOT 已对齐)"
echo
echo " 下一步:"
echo "   1) 下/补权重: bash scripts/download_models.sh $PROXY"
echo "   2) 跑推理:    bash scripts/run_inference.sh <input_video.mp4>"
echo "      (默认 GPU 0, step=1, score_threshold=0.7; 详见 scripts/README.md)"
echo "============================================================"
