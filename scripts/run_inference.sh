#!/bin/bash
# BlurBall 视频推理 (命令行, 非服务)
# 自包含: 仅依赖本仓库自身, 路径从脚本位置自动推导。
#
# 用法: bash scripts/run_inference.sh <input_video> [model_path] [step] [score_threshold]
#   input_video      必填, 输入视频路径 (.mp4/.avi 等, cv2 可解码)
#   model_path       可选, 权重路径 (默认自动探测 pretrained_weights/blurball_best)
#   step             可选, 推理步长 (默认 1; 1-step 最快, 配合 thr=0.7)
#   score_threshold  可选, 置信度阈值 (默认 0.7, README 对 1-step 的推荐值)
#
# 可选环境变量:
#   BLURBALL_ENV_DIR      虚拟环境路径 (默认见下方; 与 install.sh 一致)
#   BLURBALL_WEIGHTS_DIR  权重目录     (默认 <repo>/pretrained_weights)
#   GPU_ID                使用的 GPU 号 (默认 0)
#
# 输出: 在视频同目录下生成 frames_<name>/ (去重帧) 与 traj.csv (轨迹);
#       默认开启可视化 (runner.vis_result/vis_hm=True), 会另存 frames/ 与 hm/。
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_DIR="${BLURBALL_ENV_DIR:-/root/paddlejob/workspace/env_run/penghaotian/envs/blurball}"
WEIGHTS_DIR="${BLURBALL_WEIGHTS_DIR:-$REPO_ROOT/pretrained_weights}"
GPU_ID="${GPU_ID:-0}"

INPUT_VID="$1"
MODEL_PATH="$2"
STEP="${3:-1}"
SCORE_THRESHOLD="${4:-0.7}"

if [ -z "$INPUT_VID" ]; then
    echo "用法: bash scripts/run_inference.sh <input_video> [model_path] [step] [score_threshold]"
    exit 1
fi
if [ ! -f "$INPUT_VID" ]; then
    echo "[ERROR] 输入视频不存在: $INPUT_VID"; exit 1
fi

ACTIVATE="$ENV_DIR/bin/activate"
if [ ! -f "$ACTIVATE" ]; then
    echo "[ERROR] 虚拟环境不存在: $ENV_DIR"
    echo "        先运行 bash scripts/install.sh, 或设 BLURBALL_ENV_DIR 指向已有环境。"
    exit 1
fi

# 自动探测权重 (未显式传则找 pretrained_weights 下的 blurball*)
if [ -z "$MODEL_PATH" ]; then
    if [ -s "$WEIGHTS_DIR/blurball_best" ]; then
        MODEL_PATH="$WEIGHTS_DIR/blurball_best"
    else
        MODEL_PATH="$(ls -1 "$WEIGHTS_DIR"/blurball* 2>/dev/null | head -1 || true)"
    fi
fi
if [ -z "$MODEL_PATH" ] || [ ! -s "$MODEL_PATH" ]; then
    echo "[ERROR] 未找到 BlurBall 权重 (在 $WEIGHTS_DIR/)。"
    echo "        先运行 bash scripts/download_models.sh, 或显式传入权重路径:"
    echo "        bash scripts/run_inference.sh \"$INPUT_VID\" /path/to/blurball_best"
    exit 1
fi

# shellcheck disable=SC1090
source "$ACTIVATE"
cd "$REPO_ROOT"

echo "[run] GPU=$GPU_ID  step=$STEP  score_threshold=$SCORE_THRESHOLD"
echo "[run] video=$INPUT_VID"
echo "[run] model=$MODEL_PATH"

# runner.gpus=[0] + DataParallel; 用 CUDA_VISIBLE_DEVICES 把目标卡映射成逻辑 0。
CUDA_VISIBLE_DEVICES="$GPU_ID" python src/main.py \
    --config-name=inference_blurball \
    detector.model_path="$MODEL_PATH" \
    +input_vid="$INPUT_VID" \
    detector.step="$STEP" \
    detector.postprocessor.score_threshold="$SCORE_THRESHOLD"

VID_DIR="$(cd "$(dirname "$INPUT_VID")" && pwd)"
VID_NAME="$(basename "${INPUT_VID%.*}")"
echo
echo "[done] 轨迹: $VID_DIR/frames_$VID_NAME/traj.csv"
echo "[done] 去重帧目录: $VID_DIR/frames_$VID_NAME/"
