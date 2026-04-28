#!/usr/bin/env bash
# Bootstrap the AIMS app pod (L4): DeepStream + behavior analytics + foundational
# services + vss-agent + vss-ui + alert-bridge. VLM/LLM are remote on the NIM pod.
#
# Required env vars (set on the Runpod pod):
#   NGC_CLI_API_KEY  — for pulling vss-core / DeepStream images from nvcr.io
#   NIM_POD_HOST     — reachable host/IP of the NIM pod from this pod
# Optional:
#   NUM_SENSORS      — feed count (default 15)
#   AIMS_REPO_URL    — defaults to upstream NVIDIA blueprint
#   AIMS_REPO_REF    — defaults to main
set -euo pipefail

: "${NGC_CLI_API_KEY:?NGC_CLI_API_KEY must be set on the pod}"
: "${NIM_POD_HOST:?NIM_POD_HOST must be set (the NIM pod's reachable host/IP)}"
: "${NUM_SENSORS:=15}"
: "${AIMS_REPO_URL:=https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git}"
: "${AIMS_REPO_REF:=main}"

REPO_DIR=/workspace/video-search-and-summarization
HOST_IP=$(hostname -I | awk '{print $1}')

echo "==> Installing Docker + nvidia-container-toolkit"
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg git jq
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

echo "==> Waiting for NIM pod ($NIM_POD_HOST) to report ready"
for i in {1..120}; do
  vlm_ok=0; llm_ok=0
  curl -fs --max-time 5 "http://$NIM_POD_HOST:30082/v1/health/ready" >/dev/null 2>&1 && vlm_ok=1
  curl -fs --max-time 5 "http://$NIM_POD_HOST:30081/v1/health/ready" >/dev/null 2>&1 && llm_ok=1
  if [ "$vlm_ok" = "1" ] && [ "$llm_ok" = "1" ]; then
    echo "  NIM pod ready"
    break
  fi
  echo "  waiting... vlm=$vlm_ok llm=$llm_ok ($i/120)"
  sleep 15
done

echo "==> Logging into NGC for vss-core / DeepStream image pulls"
echo "$NGC_CLI_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin

echo "==> Writing aims app-pod env"
mkdir -p "$REPO_DIR/deployments/aims/app-pod"
DATA_DIR=/workspace/aims-data
mkdir -p "$DATA_DIR"

cat > "$REPO_DIR/deployments/aims/app-pod/.env" <<EOF
MDX_SAMPLE_APPS_DIR=$REPO_DIR/deployments
MDX_DATA_DIR=$DATA_DIR
HOST_IP=$HOST_IP
EXTERNAL_IP=$HOST_IP
NIM_POD_HOST=$NIM_POD_HOST
NGC_CLI_API_KEY=$NGC_CLI_API_KEY
NVIDIA_API_KEY=
MODE=2d_cv
BP_PROFILE=bp_developer_alerts
HARDWARE_PROFILE=L40S
RESERVED_DEVICE_IDS=0
FIXED_SHARED_DEVICE_IDS=
RT_CV_DEVICE_ID=0
RT_VLM_DEVICE_ID=0
LLM_DEVICE_ID=0
VLM_DEVICE_ID=0
LLM_MODE=remote
VLM_MODE=remote
LLM_NAME=nvidia/nvidia-nemotron-nano-9b-v2
LLM_NAME_SLUG=nvidia-nemotron-nano-9b-v2
LLM_BASE_URL=http://$NIM_POD_HOST:30081/v1
LLM_MODEL_TYPE=nim
LLM_ENV_FILE=
VLM_NAME=nvidia/cosmos-reason2-8b
VLM_NAME_SLUG=cosmos-reason2-8b
VLM_BASE_URL=http://$NIM_POD_HOST:30082/v1
VLM_MODEL_TYPE=nim
VLM_ENV_FILE=
RTVI_VLM_ENDPOINT=http://$NIM_POD_HOST:30082/v1
PROXY_MODE=no_proxy
COMPOSE_PROFILES=bp_developer_alerts_2d_cv,bp_developer_alerts_2d_cv_L40S,bp_developer_alerts_2d_cv_no_proxy,llm_remote_nvidia-nemotron-nano-9b-v2,vlm_remote_cosmos-reason2-8b
COMPOSE_PROJECT_NAME=aims-app
STREAM_TYPE=kafka
MODEL_TYPE=cnn
MODEL_NAME_2D=GDINO
PERCEPTION_IMAGE=nvcr.io/nvidia/vss-core/vss-rt-cv
PERCEPTION_TAG=3.1.0
PERCEPTION_DOCKERFILE_PREFIX=
NUM_SENSORS=$NUM_SENSORS
ELASTICSEARCH_ILM_MIN_AGE=4h
ELASTICSEARCH_CONNECTION_MAX_ATTEMPTS=20
NVSTREAMER_INSTALL_ADDITIONAL_PACKAGES=true
NVSTREAMER_HTTP_PORT=31000
VST_PORT=30888
VST_EXTERNAL_URL=http://$HOST_IP:30888
VST_INTERNAL_URL=http://$HOST_IP:30888
VST_MCP_PORT=8001
VST_MCP_URL=http://$HOST_IP:8001
VST_ADAPTOR=vst_rtsp
VST_MCP_IMAGE_TAG=3.1.0
VST_STREAM_PROCESSOR_IMAGE_TAG=3.1.0
VST_SENSOR_IMAGE_TAG=3.1.0
NVSTREAMER_IMAGE_TAG=3.1.0
VLM_AS_VERIFIER_CONFIG_FILE_PREFIX=
VLM_AS_VERIFIER_CONFIG_FILE=$REPO_DIR/deployments/developer-workflow/dev-profile-alerts/vlm-as-verifier/configs/config.yml
VLM_AS_VERIFIER_ALERT_TYPE_CONFIG_FILE=$REPO_DIR/deployments/developer-workflow/dev-profile-alerts/vlm-as-verifier/configs/alert_type_config.json
LLM_PORT=30081
VLM_PORT=30082
VLM_NIM_KVCACHE_PERCENT=0.4
VSS_AGENT_VERSION=3.1.0
VSS_AGENT_CONFIG_FILE=./deployments/developer-workflow/dev-profile-alerts/vss-agent/configs/config.yml
VSS_AGENT_HOST=0.0.0.0
VSS_AGENT_PORT=8000
STREAM_MODE=other
VIDEO_ANALYSIS_MCP_URL=http://$HOST_IP:9901
VSS_VA_MCP_CONFIG_FILE=./deployments/developer-workflow/dev-profile-alerts/vss-agent/configs/va_mcp_server_config.yml
VSS_VA_MCP_PORT=9901
VSS_AGENT_TEMPLATE_PATH=./deployments/developer-workflow/dev-profile-alerts/vss-agent/templates
VSS_AGENT_TEMPLATE_NAME=incident_report_template.md
MDX_PORT=8081
RTVI_VLM_IMAGE_TAG=3.1.0
RTVI_VLM_BASE_URL=http://$HOST_IP:8018
RTVI_VLM_OPENAI_MODEL_DEPLOYMENT_NAME=nvidia/cosmos-reason2-8b
RTVI_VLM_MODEL_TO_USE=openai-compat
RTVI_VLLM_GPU_MEMORY_UTILIZATION=
RTVI_VLM_MODEL_PATH=ngc:nim/nvidia/cosmos-reason2-8b:hf-1208
RTVI_VLM_KAFKA_BOOTSTRAP_SERVERS=localhost:9092
RTVI_VLM_KAFKA_INCIDENT_TOPIC=mdx-vlm-incidents
VSS_ES_PORT=9200
VSS_AGENT_OBJECT_STORE_TYPE=local_object_store
VSS_AGENT_REPORTS_BASE_URL=http://$HOST_IP:8000/static/
VSS_AGENT_EXTERNAL_URL=http://$HOST_IP:8000
PHOENIX_ENDPOINT=http://$HOST_IP:6006
NEXT_PUBLIC_APP_TITLE=AIMS
NEXT_PUBLIC_APP_SUBTITLE=Traffic Accident Monitoring
NEXT_PUBLIC_WORKFLOW=VSS Agent
NEXT_PUBLIC_ENABLE_CHAT_TAB=true
NEXT_PUBLIC_CHAT_UPLOAD_FILE_ENABLE=false
NEXT_PUBLIC_ENABLE_ALERTS_TAB=true
NEXT_PUBLIC_ALERTS_TAB_VERIFIED_FLAG_DEFAULT=true
NEXT_PUBLIC_ENABLE_DASHBOARD_TAB=false
NEXT_PUBLIC_ENABLE_MAP_TAB=false
NEXT_PUBLIC_ENABLE_VIDEO_MANAGEMENT_TAB=true
NEXT_PUBLIC_VIDEO_MANAGEMENT_TAB_ADD_RTSP_ENABLE=true
NEXT_PUBLIC_VIDEO_MANAGEMENT_VIDEO_UPLOAD_ENABLE=false
NEXT_PUBLIC_ENABLE_SEARCH_TAB=false
UID=0
GID=0
EOF

cat > "$REPO_DIR/deployments/aims/app-pod/compose.yml" <<'YAML'
include:
  - path: ${MDX_SAMPLE_APPS_DIR}/developer-workflow/dev-profile-alerts/compose.yml
YAML

echo "==> Starting AIMS app stack"
cd "$REPO_DIR/deployments/aims/app-pod"
docker compose --env-file .env up -d
docker compose --env-file .env ps

echo "==> Done. UI: http://$HOST_IP:8000  VST: http://$HOST_IP:30888"
