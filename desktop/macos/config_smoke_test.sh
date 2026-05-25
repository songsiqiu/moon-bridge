#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/config.yml" <<'YAML'
mode: "Transform"

log:
  level: "info"
  format: "text"

server:
  addr: "127.0.0.1:38440"

persistence:
  active_provider: "db_sqlite"

extensions:
  deepseek_v4:
    config:
      reinforce_instructions: true
  visual:
    config:
      provider: "kimi"
      model: "kimi-for-coding"
      max_rounds: 4
      max_tokens: 2048
  db_sqlite:
    enabled: true
    config:
      path: "./data/moonbridge.db"
      wal: true
      busy_timeout_ms: 5000
      max_open_conns: 1
  metrics:
    enabled: true
    config:
      default_limit: 100
      max_limit: 1000

cache:
  mode: "explicit"
  ttl: "5m"
  prompt_caching: true
  automatic_prompt_cache: false
  explicit_cache_breakpoints: true
  allow_retention_downgrade: false
  max_breakpoints: 4
  min_cache_tokens: 1024
  expected_reuse: 2
  minimum_value_score: 2048
  min_breakpoint_tokens: 1024

trace:
  enabled: false

defaults:
  model: "moonbridge"
  max_tokens: 4096

models:
  "deepseek-v4-pro":
    context_window: 1000000
    max_output_tokens: 384000
    display_name: "deepseek-v4-pro"
    default_reasoning_level: "high"
    supported_reasoning_levels:
      - effort: "high"
        description: "High reasoning effort"
      - effort: "xhigh"
        description: "Extra high reasoning effort"
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"
    extensions:
      deepseek_v4:
        enabled: true
      visual:
        enabled: false

providers:
  "deepseek":
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "smoke-test-key"
    version: "2023-06-01"
    user_agent: "moonbridge/desktop"
    offers:
      - model: "deepseek-v4-pro"

routes:
  "moonbridge":
    model: "deepseek-v4-pro"
    provider: "deepseek"
YAML

mkdir -p "${TMP_DIR}/data"
(
  cd "${TMP_DIR}"
  "${ROOT_DIR}/dist/macos/Moon Bridge.app/Contents/Resources/moonbridge" -config "${TMP_DIR}/config.yml" -print-addr
  "${ROOT_DIR}/dist/macos/Moon Bridge.app/Contents/Resources/moonbridge" -config "${TMP_DIR}/config.yml" -print-default-model
)

cat > "${TMP_DIR}/same-provider-visual.yml" <<'YAML'
mode: "Transform"
server:
  addr: "127.0.0.1:38440"
persistence:
  active_provider: "db_sqlite"
extensions:
  deepseek_v4:
    config:
      reinforce_instructions: true
  visual:
    config:
      provider: "deepseek"
      model: "deepseek-v4-flash"
      max_rounds: 4
      max_tokens: 2048
  db_sqlite:
    enabled: true
    config:
      path: "./data/moonbridge.db"
models:
  "deepseek-v4-pro":
    context_window: 1000000
    max_output_tokens: 384000
    extensions:
      deepseek_v4:
        enabled: true
      visual:
        enabled: true
  "deepseek-v4-flash":
    context_window: 1000000
    max_output_tokens: 384000
providers:
  "deepseek":
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "smoke-test-key"
    version: "2023-06-01"
    offers:
      - model: "deepseek-v4-pro"
      - model: "deepseek-v4-flash"
routes:
  "moonbridge":
    model: "deepseek-v4-pro"
    provider: "deepseek"
defaults:
  model: "moonbridge"
  max_tokens: 4096
YAML

"${ROOT_DIR}/dist/macos/Moon Bridge.app/Contents/Resources/moonbridge" -config "${TMP_DIR}/same-provider-visual.yml" -print-default-model >/dev/null
