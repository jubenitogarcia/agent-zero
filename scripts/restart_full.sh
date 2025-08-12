#!/usr/bin/env bash
set -euo pipefail

# Restart Agent Zero (embedded) + Gateway WhatsApp
# Usage: ./scripts/restart_full.sh [--no-clean] [--no-gateway]

CLEAN_PROFILE=1
START_GATEWAY=1
for a in "$@"; do
  case "$a" in
    --no-clean) CLEAN_PROFILE=0 ;;
    --no-gateway) START_GATEWAY=0 ;;
  esac
  shift || true
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATEWAY_DIR="$ROOT_DIR/whatsapp-gateway"
LOG_DIR="$ROOT_DIR"

printf "[restart] Stopping old processes...\n"
pkill -f run_ui.py 2>/dev/null || true
pkill -f az_daemon.py 2>/dev/null || true
pkill -f webhook_server.py 2>/dev/null || true
pkill -f message_worker 2>/dev/null || true
pkill -f bot_com_api.js 2>/dev/null || true
pkill -f node 2>/dev/null || true

if [[ $CLEAN_PROFILE -eq 1 ]]; then
  printf "[restart] Cleaning Chrome temporary profiles...\n"
  rm -rf /tmp/chrome-user-data /private/tmp/chrome-user-data || true
fi

printf "[restart] Activating virtualenv (if exists)...\n"
if [[ -f "$ROOT_DIR/.venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.venv/bin/activate"
fi

# Guard: evitar arquivo queue.py local que quebra urllib3 (shadow da stdlib 'queue')
if [[ -f "$ROOT_DIR/queue.py" ]]; then
  TS="$(date +%s)"
  echo "[restart][guard] Encontrado $ROOT_DIR/queue.py (shadow da stdlib). Movendo para queue_shadowed.$TS.disabled"
  mv "$ROOT_DIR/queue.py" "$ROOT_DIR/queue_shadowed.$TS.disabled" || echo "[restart][guard] Falha ao mover, remova manualmente."
fi

export WEBHOOK_EMBEDDED=1
export QUEUE_BACKEND=redis
export REDIS_URL=${REDIS_URL:-redis://localhost:6379/1}
export DISABLE_WEBHOOK_API_KEY=1
export WHATSAPP_WEBHOOK_SECRET=${WHATSAPP_WEBHOOK_SECRET:-AGZ_SECRET_123}
export WHATSAPP_BASE_URL=${WHATSAPP_BASE_URL:-http://localhost:3001}
# Porta da UI Flask (Agent Zero host). Usar WEB_UI_PORT pois run_ui.py não lê AGENT_ZERO_PORT.
export WEB_UI_PORT=${WEB_UI_PORT:-50001}
AGENT_ZERO_PORT="$WEB_UI_PORT"  # manter variável para reutilizar no webhook URL

# Ativar integração direta WhatsApp -> Agent Zero
export AGZ_INTERNAL_ENABLE_DIRECT=1
export AGZ_INTERNAL_BASE="http://localhost:$WEB_UI_PORT"
export AUTH_LOGIN=${AUTH_LOGIN:-admin}
export AUTH_PASSWORD=${AUTH_PASSWORD:-admin}

printf "[restart] Starting Agent Zero (embedded) on port $AGENT_ZERO_PORT ...\n"
python "$ROOT_DIR/run_ui.py" --port "$WEB_UI_PORT" > "$LOG_DIR/ui_embed.out" 2>&1 &
UI_PID=$!

sleep 5
curl -sf "http://localhost:$WEB_UI_PORT/agent-zero/debug/ping" >/dev/null && echo "[restart] Agent Zero ping OK (port $WEB_UI_PORT)" || echo "[restart] WARN: Agent Zero ping failed on port $WEB_UI_PORT"

# Esperar readiness completo (init_a0 finalizado)
printf "[restart] Waiting for Agent Zero readiness (init) ...\n"
READY_WAIT=0
until curl -s "http://localhost:$WEB_UI_PORT/ready" | grep -q '"ready": *true'; do
  sleep 1
  READY_WAIT=$((READY_WAIT+1))
  if [ $READY_WAIT -ge 90 ]; then
    echo "[restart] WARN: readiness timeout após 90s (seguindo mesmo assim)"
    break
  fi
done
if [ $READY_WAIT -lt 90 ]; then
  echo "[restart] Agent Zero READY em ${READY_WAIT}s"
fi

if [[ $START_GATEWAY -eq 1 ]]; then
  printf "[restart] Starting WhatsApp Gateway...\n"
  export AGZ_WEBHOOK_URL="http://localhost:$WEB_UI_PORT/agent-zero/webhooks/whatsapp"
  export WHATSAPP_WEBHOOK_SECRET
  export AGZ_INTERNAL_ENABLE_DIRECT
  export AGZ_INTERNAL_BASE
  export AUTH_LOGIN
  export AUTH_PASSWORD
  ( cd "$GATEWAY_DIR" && node bot_com_api.js > "$LOG_DIR/gw.out" 2>&1 & )
  GW_PID=$!
  sleep 6
  curl -s http://localhost:3001/v1/webhooks | grep -q agent-zero && echo "[restart] Webhook registered (maybe)" || echo "[restart] Webhook not yet registered"
else
  echo "[restart] Skipped starting gateway (--no-gateway)"
fi

printf "[restart] PIDs -> UI:$UI_PID GW:${GW_PID:-skip}\n"

echo "[restart] Tail logs: tail -f ui_embed.out gw.out"
