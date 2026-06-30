# BlurBall 安装与推理 — 脚本说明 (scripts/)

本目录提供 BlurBall **一键安装 + 权重下载 + 视频推理**的脚本。
三个脚本**自包含**(只依赖本仓库自身, 路径从脚本位置自动推导)。仿 GVHMR `scripts/` 风格。

BlurBall = 乒乓球检测 + 运动模糊联合估计 (HRNet 多帧 MIMO)。输入视频 → 逐帧检测球位置/模糊方向/模糊长度 → 输出轨迹 csv。

---

## 本机环境快照 (已验证可跑)

| 项 | 值 |
| --- | --- |
| OS | Linux (kernel 5.15.0) |
| GPU | NVIDIA H800 80GB ×8 (推理默认用单卡) |
| Python | 3.10.12 |
| PyTorch | 2.3.0+cu121 (含 sm_90/Hopper; requirements 原写 2.2.2, 这里以跑通为准对齐 GVHMR) |
| nvcc | 12.9 (仅需可见; torch 用 cu121 预编译 wheel) |
| uv | 0.11.7 |
| 虚拟环境 | `/root/paddlejob/workspace/env_run/penghaotian/envs/blurball` |

已验证: `torch.cuda.is_available()=True`、BlurBall 全模块可导入、HRNet 模型在 GPU 上前向通过 (1.49M 参数, 输入 9ch×288×512 → 输出 3×288×512)。

---

## 前置条件 (新人必读)

- **机器**: Linux + NVIDIA GPU, CUDA 12.x。
- **uv**: 建虚拟环境与装包用。先装: https://docs.astral.sh/uv/ (脚本会检查, 缺则报错)。
- **aria2c / wget**: 下权重用 (脚本优先 aria2c, 退化到 wget)。
- **权重**: 作者放在公开 Nextcloud 分享, 无 license 门槛, `download_models.sh` 自动下 (含主权重 `blurball_best` 及各 baseline)。
- **数据集 (可选, 仅评测/训练)**: 含 license, 需手动到
  https://cloud.cs.uni-tuebingen.de/index.php/s/C3pJEPKWQAkono7 下, 并改
  `src/configs/dataset/tabletennis.yaml` 的 `root_dir`。单纯跑视频推理**不需要**数据集。

---

## 三步流程

```bash
# (1) 安装: 建 env(py3.10) + torch2.3.0/cu121 + requirements 其余依赖
#     同时把 src/configs 里硬编码的 WASB_ROOT 改成本仓库根, 并配置 activate(PYTHONPATH/HYDRA)
#     proxy 可选 baidu(默认) | aliyun
bash scripts/install.sh baidu

# (2) 下权重: 从 Nextcloud 分享拉全部权重到 pretrained_weights/ (缺啥下啥, 已有则跳过)
bash scripts/download_models.sh baidu

# (3) 跑推理: 对一段视频做检测, 默认 step=1 / score_threshold=0.7 (1-step 推荐配置)
bash scripts/run_inference.sh <input_video.mp4>
```

推理输出 (在视频同目录):
- `frames_<name>/traj.csv` — 每帧球位置/模糊轨迹
- `frames_<name>/` — ssim 去重后的帧 (BlurBall 对重复帧敏感, 自动去重)
- `frames/`、`hm/` — 可视化帧与热力图 (runner 默认开启 `vis_result`/`vis_hm`)

---

## 换机器/换人要改的地方

脚本路径自动推导, 但有几处**本机专属默认值**, 别人复用时改这里(或用环境变量覆盖):

| 文件 | 项 | 当前默认值 | 覆盖方式 |
| --- | --- | --- | --- |
| 三个脚本 | `ENV_DIR` | `/root/paddlejob/.../envs/blurball` | 设 `BLURBALL_ENV_DIR=/your/env` |
| 三个脚本 | 代理 URL | 百度/阿里内网代理 | 第 1 个参数 `baidu`/`aliyun`, 或改脚本内 `http(s)_proxy` 段 |
| download/run | `WEIGHTS_DIR` | `<repo>/pretrained_weights` | 设 `BLURBALL_WEIGHTS_DIR=/your/weights` |
| run_inference | GPU 号 | `0` | 设 `GPU_ID=2` |

> 注: `install.sh` 会就地修改 `src/configs/*.yaml` 里的 `WASB_ROOT`
> (原作者路径 `/home/gossard/Git/blurball` → 本仓库根)。该操作幂等, 重复跑无副作用。

---

## 推理参数 (run_inference.sh)

```bash
bash scripts/run_inference.sh <input_video> [model_path] [step] [score_threshold]
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `input_video` | (必填) | 输入视频 (.mp4/.avi 等, cv2 可解码) |
| `model_path` | 自动探测 `pretrained_weights/blurball_best` | BlurBall 权重路径 |
| `step` | `1` | 推理步长; 1=最快 (MIMO 一次出 3 帧), 3=更稳但慢 |
| `score_threshold` | `0.7` | 置信度阈值; README 对 1-step 推荐 0.7 |

等价的底层命令 (脚本封装的就是这条):
```bash
CUDA_VISIBLE_DEVICES=0 python src/main.py --config-name=inference_blurball \
    detector.model_path=<weights> +input_vid=<video> \
    detector.step=1 detector.postprocessor.score_threshold=0.7
```

**其他模型**: 仓库还支持 WASB/TrackNetV2/DeepBall/Monotrack/BallSeg 等, 换
`--config-name=inference_<model>` + 对应权重即可 (见根目录 `README.md`)。本脚本默认走 BlurBall。

---

## 目录内容

| 文件 | 作用 |
| --- | --- |
| `install.sh` | 一键装 env + torch/cu121 + 依赖; 修正 WASB_ROOT; 配置 activate |
| `download_models.sh` | 从 Nextcloud 分享下全部权重到 `pretrained_weights/` (主权重 `blurball_best`) |
| `run_inference.sh` | 对视频跑 BlurBall 推理 (默认 GPU 0 / step 1 / 阈值 0.7) |

相关代码 (在仓库其他位置): `src/runners/inference.py` (推理实现)、
`src/setup_scripts/setup_weights.sh` (从 Google Drive 下 baseline 权重的旧脚本, 国内成功率低, 一般无需用)。
