#!/usr/bin/env bash
# revive.sh — reprende todo lo necesario tras un timeout/resume del Codespace.
# Uso: bash revive.sh   (desde cualquier carpeta del repo, se auto-ubica en la raíz)
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "== 1. Levantar contenedores (Postgres + pgAdmin) =="
docker compose up -d
sleep 3
docker ps

echo ""
echo "== 2. Reaplicar regla de red (DOCKER-USER) si falta =="
sudo iptables-legacy -C DOCKER-USER -s 172.16.0.0/12 -d 172.16.0.0/12 -j ACCEPT 2>/dev/null \
  && echo "Regla ya existía." \
  || { sudo iptables-legacy -I DOCKER-USER -s 172.16.0.0/12 -d 172.16.0.0/12 -j ACCEPT; echo "Regla agregada."; }

echo ""
echo "== 3. Levantar Jupyter Lab (si no está corriendo) =="
if pgrep -f "jupyter-lab" > /dev/null; then
  echo "Jupyter Lab ya está corriendo."
else
  cd nivel-0
  nohup jupyter-lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' > /tmp/jupyter.log 2>&1 &
  disown
  sleep 3
  cd "$REPO_ROOT"
  echo "Jupyter Lab iniciado (log en /tmp/jupyter.log)."
fi

echo ""
echo "=================================================="
echo " Listo. Accesos:"
echo "  - pgcli:    pgcli -h localhost -U postgres -d ny_taxi   (pass: changeme1234)"
echo "  - pgAdmin:  http://localhost:5050"
echo "  - Jupyter:  http://localhost:8888/lab"
echo "  (abre los puertos 5050 / 8888 desde la pestaña PORTS del Codespace)"
echo "=================================================="
