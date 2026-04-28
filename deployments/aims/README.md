# AIMS — Accident Incident Monitoring Stack

Two-pod deployment of the VSS Alert Verification workflow, tuned for traffic-accident
detection.

## Topology

| Pod | GPU | Components |
|-----|-----|------------|
| `app-pod` | 1× L4 (24 GB) | DeepStream perception + tracker + GDINO, behavior analytics, Kafka, Redis, Elasticsearch, VST/nvstreamer, vss-agent, vss-ui, alert-bridge |
| `nim-pod` | 1× RTX PRO 6000 Blackwell (96 GB) | Cosmos-Reason2-8B (VLM, BF16) + Nemotron-Nano-9B-v2 (LLM, BF16), co-resident on GPU 0 |

The app-pod calls the NIM pod over the private network. Latency budget per alert is
≤ 30 s end-to-end, so a few-ms intra-region hop is fine.

## Prerequisites

- Both pods on the same private network / VPC. Set `NIM_POD_HOST` to the NIM pod's
  reachable hostname or IP from the app-pod.
- `NGC_CLI_API_KEY` set on the NIM pod (model pulls from NGC).
- Both pods must have `MDX_SAMPLE_APPS_DIR` pointing at the cloned repo's
  `deployments/` directory.

## Launch order

1. **NIM pod first** — VLM/LLM cold-start (first run) pulls weights from NGC and
   warms the engines. Allow ~10–15 min on first boot.
   ```bash
   cd deployments/aims/nim-pod
   docker compose --env-file .env up -d
   # wait for health
   curl http://localhost:30082/v1/health/ready   # VLM
   curl http://localhost:30081/v1/health/ready   # LLM
   ```

2. **App pod second** — once the NIM pod reports ready.
   ```bash
   cd deployments/aims/app-pod
   docker compose --env-file .env up -d
   ```

## Cross-pod routing

The app-pod's `.env` sets:

```
LLM_MODE=remote
VLM_MODE=remote
LLM_BASE_URL=http://${NIM_POD_HOST}:30081/v1
VLM_BASE_URL=http://${NIM_POD_HOST}:30082/v1
```

These flow through to `vss-agent`, `alert-bridge` (vlm-as-verifier), and the
RTVI VLM endpoint via `RTVI_VLM_ENDPOINT`.

## Tuning for traffic accidents

Beyond what's set in `.env`, you'll want to edit:

- `deployments/developer-workflow/dev-profile-alerts/deepstream/configs/` —
  Grounding-DINO prompts. Add classes like:
  `"vehicle collision"`, `"overturned vehicle"`, `"stopped vehicle in lane"`,
  `"debris on road"`, `"pedestrian on road"`.
- `deployments/developer-workflow/dev-profile-alerts/vss-behavior-analytics/configs/` —
  speed-drop thresholds, stationary-in-lane timers, trajectory-deviation rules.
- `deployments/developer-workflow/dev-profile-alerts/vlm-as-verifier/configs/config.yml` —
  verifier prompt. Ask explicitly: *"Is there a traffic accident visible? Categorize
  as: collision, single-vehicle, stalled, debris, none."*

## Sizing notes

- L4 (24 GB) covers ~15–30 RTSP feeds at 1080p with the cnn (RT-DETR) perception
  path. Bump `NUM_SENSORS` to your real feed count.
- RTX PRO 6000 BW with both NIMs in BF16 uses ~56 GB of 96 GB. The remaining
  ~40 GB absorbs KV cache growth during alert bursts.
- VLM only fires on candidate events from behavior analytics, so steady-state
  load on the NIM pod stays low even at 30 feeds.
