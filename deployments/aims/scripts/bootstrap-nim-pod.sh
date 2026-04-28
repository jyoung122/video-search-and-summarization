#!/usr/bin/env bash
# Bootstrap the AIMS NIM pod (RTX PRO 6000 Blackwell, BF16 Cosmos-Reason2-8B + Nemotron-Nano-9B-v2).
# Required env vars (set on the Runpod pod):
#   NGC_CLI_API_KEY  — NGC API key for pulling NIM images and weights
# Optional:
#   AIMS_REPO_URL    — defaults to upstream NVIDIA blueprint
#   AIMS_REPO_REF    — defaults to main
set -euo pipefail

: "${NGC_CLI_API_KEY:?NGC_CLI_API_KEY must be set on the pod}"
: "${AIMS_REPO_URL:=https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git}"
: "${AIMS_REPO_REF:=main}"

REPO_DIR=/workspace/video-search-and-summarization

echo "==> Installing Docker + nvidia-container-toolkit"
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
service docker start || dockerd > /var/log/dockerd.log 2>&1 &
for i in {1..30}; do docker info >/dev/null 2>&1 && break; sleep 1; done

echo "==> Cloning $AIMS_REPO_URL@$AIMS_REPO_REF"
git clone --depth 1 -b "$AIMS_REPO_REF" "$AIMS_REPO_URL" "$REPO_DIR"

echo "==> Logging into NGC"
echo "$NGC_CLI_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

echo "==> Writing aims nim-pod compose + env"
mkdir -p "$REPO_DIR/deployments/aims/nim-pod"
cat > "$REPO_DIR/deployments/aims/nim-pod/compose.yml" <<'YAML'
include:
  - path: ${MDX_SAMPLE_APPS_DIR}/nim/cosmos-reason2-8b/compose.yml
  - path: ${MDX_SAMPLE_APPS_DIR}/nim/nvidia-nemotron-nano-9b-v2/compose.yml
YAML

cat > "$REPO_DIR/deployments/aims/nim-pod/.env" <<EOF
MDX_SAMPLE_APPS_DIR=$REPO_DIR/deployments
NGC_CLI_API_KEY=$NGC_CLI_API_KEY
HARDWARE_PROFILE=RTXPRO6000BW
SHARED_LLM_VLM_DEVICE_ID=0
LLM_DEVICE_ID=0
VLM_DEVICE_ID=0
LLM_NAME=nvidia/nvidia-nemotron-nano-9b-v2
LLM_NAME_SLUG=nvidia-nemotron-nano-9b-v2
VLM_NAME=nvidia/cosmos-reason2-8b
VLM_NAME_SLUG=cosmos-reason2-8b
LLM_MODE=local_shared
VLM_MODE=local_shared
LLM_PORT=30081
VLM_PORT=30082
VLM_NIM_KVCACHE_PERCENT=0.4
LLM_ENV_FILE=
VLM_ENV_FILE=
LLM_MODEL_TYPE=nim
VLM_MODEL_TYPE=nim
COMPOSE_PROFILES=vlm_local_shared_cosmos-reason2-8b,llm_local_shared_nvidia-nemotron-nano-9b-v2
COMPOSE_PROJECT_NAME=aims-nim
UID=0
GID=0
EOF

echo "==> Starting NIMs (first run pulls weights — expect 10–15 min)"
cd "$REPO_DIR/deployments/aims/nim-pod"
docker compose --env-file .env up -d
docker compose --env-file .env ps

echo "==> Done. Health endpoints:"
echo "  VLM: http://<pod-ip>:30082/v1/health/ready"
echo "  LLM: http://<pod-ip>:30081/v1/health/ready"
