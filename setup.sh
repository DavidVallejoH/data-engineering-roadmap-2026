#!/usr/bin/env bash
# Setup: Postgres + pgcli + pgAdmin (replica del video, sección "SETUP DEL ENTORNO")
# Ejecutar desde la raíz del repo, en la terminal del Codespace, DESPUÉS de que
# docker-compose.yml y config/ ya estén copiados ahí.
set -e

echo "== 1. Estructura de carpetas (nivel-0) =="
mkdir -p nivel-0/notebooks nivel-0/sql nivel-0/data
echo "Carpetas creadas: nivel-0/{notebooks,sql,data}"

echo ""
echo "== 2. Instalar pgcli a nivel de sistema =="
sudo apt update && sudo apt install -y pgcli
pgcli --version

echo ""
echo "== 3. Levantar Postgres (solo ese servicio) =="
docker compose up -d postgres-2
sleep 5
docker ps

echo ""
echo "== 4. Verificar que Postgres responde =="
docker exec -it postgres-container psql -U postgres -d postgres -c "SELECT version();"

echo ""
echo "== 5. Levantar pgAdmin =="
docker compose up -d pgadmin
sleep 3
docker ps

echo ""
echo "=================================================="
echo " Listo. Resumen de acceso:"
echo "  - pgcli:   pgcli -h localhost -U postgres -d postgres   (password: changeme1234)"
echo "  - pgAdmin: http://localhost:5050"
echo "             login: pgadmin4@pgadmin.org / admin"
echo "             Al registrar el servidor Postgres dentro de pgAdmin usa:"
echo "               Host: postgres-container"
echo "               Port: 5432"
echo "               Maintenance DB: postgres"
echo "               Username: postgres"
echo "               Password: changeme1234"
echo "=================================================="
