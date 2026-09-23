# Nivel 0 completo: Setup + Fases 1-4 (NYC Yellow Taxi)

Transcripción verificada del video "Data Engineering LEVEL-1", desde el setup del
entorno (min ~43) hasta el cierre de Fase 4 (min ~201, fin del video).

> Nota de alcance: el video **no incluye DBeaver ni DAX/PowerQuery**. Termina en
> Fase 4 (OLAP Prep) con vistas y materialized views sobre Postgres.

---

## 0. Setup del entorno (Postgres + pgcli + pgAdmin)

Todo esto se ejecuta en la terminal del Codespace, desde la raíz del repo
(`/workspaces/<tu-repo>`), salvo que se indique otra cosa.

### 0.1 Estructura de carpetas

```bash
mkdir -p nivel-0/notebooks nivel-0/sql nivel-0/data
```

### 0.2 Archivos de configuración

Crea `docker-compose.yml` en la raíz del repo:

```yaml
services:
  postgres-2:
    image: postgres:13
    restart: always
    container_name: postgres-container
    env_file:
      - ./config/postgres.env
    volumes:
      - postgres-db-volume:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 10s
      retries: 5
      start_period: 5s

  pgadmin:
    image: dpage/pgadmin4
    restart: always
    container_name: pgadmin-container
    env_file:
      - ./config/pgadmin.env
    ports:
      - "5050:80"
    depends_on:
      - postgres-2

volumes:
  postgres-db-volume:
```

Y `config/postgres.env`:

```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=changeme1234
POSTGRES_DB=postgres
```

Y `config/pgadmin.env` (los `PGADMIN_CONFIG_*` no están en el video — se agregaron
para arreglar un bug real de la imagen `dpage/pgadmin4` en Codespaces, ver 0.6):

```
PGADMIN_DEFAULT_EMAIL=pgadmin4@pgadmin.org
PGADMIN_DEFAULT_PASSWORD=admin
PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION=False
PGADMIN_CONFIG_PROXY_X_HOST_COUNT=1
PGADMIN_CONFIG_PROXY_X_PREFIX_COUNT=1
PGADMIN_CONFIG_WTF_CSRF_CHECK_DEFAULT=False
PGADMIN_CONFIG_WTF_CSRF_ENABLED=False
PGADMIN_CONFIG_SESSION_COOKIE_SAMESITE='None'
PGADMIN_CONFIG_SESSION_COOKIE_SECURE=True
```

### 0.3 Instalar pgcli

```bash
sudo apt update && sudo apt install -y pgcli
pgcli --version
```

### 0.4 Levantar Postgres y verificar

```bash
docker compose up -d postgres-2
docker ps
docker exec -it postgres-container psql -U postgres -d postgres -c "SELECT version();"
```

`docker ps` debe mostrar `postgres-container` como `Up ... (healthy)`.

### 0.5 pgcli en acción

```bash
pgcli -h localhost -U postgres -d postgres
```

Password: `changeme1234`. Comandos útiles: `\l` (bases), `\dt` (tablas), `\d <tabla>`
(describe), `\dn` (schemas), `\q` (salir).

### 0.6 Levantar pgAdmin, login y registrar el servidor

```bash
docker compose up -d pgadmin
docker ps
```

Abre **http://localhost:5050** (pestaña PORTS del Codespace → puerto 5050 → Open in
Browser). Login: `pgadmin4@pgadmin.org` / `admin`.

Clic derecho en "Servers" → **Register → Server**:

| Pestaña | Campo | Valor |
|---|---|---|
| General | Name | `Postgres` |
| Connection | Host name/address | `postgres-container` (nombre del contenedor, **no** `localhost`) |
| Connection | Port | `5432` |
| Connection | Maintenance database | `postgres` |
| Connection | Username | `postgres` |
| Connection | Password | `changeme1234` |

Prueba con Query Tool → `SELECT version();`.

**Problemas reales encontrados y su fix** (por si reaparecen):

- *pgAdmin carga en blanco, consola muestra 401 en `preferences/get_all`,
  `misc/bgprocess`, `llm/status` justo después del login.* Bug conocido de la imagen
  `dpage/pgadmin4` en este stack (python3.14/gunicorn 23). Fix: las variables
  `PGADMIN_CONFIG_*` del bloque 0.2 (proxy headers + cookies/CSRF relajados).
- *pgAdmin → Register Server → "connection timeout expired".* No es typo, es la
  red: el host bloquea por defecto el tráfico entre la red bridge personalizada de
  Compose (`iptables-legacy`, chain `FORWARD`, policy `DROP`). Fix:
  ```bash
  sudo iptables-legacy -I DOCKER-USER -s 172.16.0.0/12 -d 172.16.0.0/12 -j ACCEPT
  ```
  **Esta regla no persiste tras reiniciar el Codespace** — si vuelve el timeout,
  reaplícala.
- *pgAdmin → "Unauthorised access, permission denied." al conectar.* Revisa que la
  password tenga los 12 caracteres de `changeme1234` (a veces el campo se ve con
  menos puntos por autocompletado). Si persiste, resetea el volumen (pierdes los
  datos): `docker compose down -v && docker compose up -d`.

### 0.7 Jupyter Lab (para los notebooks de las Fases 1-4)

```bash
which jupyter-lab || pip install jupyterlab -q
pip install pandas psycopg2-binary sqlalchemy jupysql -q
```

Levantarlo sin token (para abrirlo directo desde el navegador del Codespace):

```bash
cd nivel-0
nohup jupyter-lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' > /tmp/jupyter.log 2>&1 &
sleep 3
cat /tmp/jupyter.log
```

Abre el puerto **8888** desde la pestaña PORTS (Open in Browser) → debe abrir
directo en `/lab` sin pedir token.

### 0.8 Si reinicias el Codespace (o vuelve a fallar la conexión)

El timeout por inactividad (default 30 min) **detiene** el Codespace, no lo borra
ni lo reconstruye: el código, los paquetes instalados y los datos en disco
persisten. Lo que se pierde son los procesos en memoria — contenedores Docker
internos, la regla de iptables, el proceso de Jupyter Lab.

En vez de repetir los comandos a mano, corre el script `revive.sh` (en la raíz
del repo, creado y commiteado junto con `docker-compose.yml`):

```bash
cd /workspaces/<tu-repo>
bash revive.sh
```

Levanta Postgres+pgAdmin, reaplica la regla de red si falta, y arranca Jupyter
Lab si no está corriendo — todo en un solo paso, sin duplicar información con
el resto de esta sección.

> Nota: esto **no** es un `postStartCommand` de `devcontainer.json` (eso solo se
> activa con un *rebuild* del contenedor, y como Docker corre dentro del mismo
> contenedor de este Codespace, un rebuild probablemente borraría el volumen de
> Postgres). `revive.sh` es manual pero seguro: un comando, cero riesgo de perder
> datos.

---

## FASE 0.5 — Crear la base `ny_taxi` y cargar el CSV

### 1. Crear la base de datos

El contenedor de Postgres ya corre desde el setup, pero la base por defecto es
`postgres`. Creamos una dedicada:

```bash
pgcli -h localhost -U postgres -d postgres
```

```sql
CREATE DATABASE ny_taxi;
\l
```

Si ves `ny_taxi` en la lista, salimos con `\q` y reconectamos apuntando a esa base:

```bash
pgcli -h localhost -U postgres -d ny_taxi
```

> A partir de aquí, todas las fases se conectan a `ny_taxi`, no a `postgres`.

### 2. Descargar el CSV del NYC Yellow Taxi

El CSV directo devuelve 403 (CloudFront bloquea el acceso), pero el Parquet sí está
disponible. Lo convertimos con Python:

```bash
cd nivel-0
cd data
pip install pandas pyarrow -q
python3 -c "
import pandas as pd
df = pd.read_parquet('https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet')
df.to_csv('yellow_tripdata_2024-01.csv', index=False)
print(f'Filas: {len(df)}, Tamaño: {round(df.memory_usage(deep=True).sum()/1024/1024)} MB')
"
ls -lh yellow_tripdata_2024-01.csv
```

Salida esperada: `Filas: 2964624, Tamaño: 533 MB`, archivo de ~367 MB en disco.

> El proceso usa ~900 MB de RAM momentáneamente. Asegúrate de tener 2 GB libres.

---

## FASE 1 — RAW (datos crudos, todo como TEXT)

### 1. Crear el notebook

```bash
cd nivel-0
python3 -c "import json; json.dump({'cells':[],'metadata':{},'nbformat':4,'nbformat_minor':5}, open('notebooks/20-fase-1-raw.ipynb','w'))"
```

Abre `nivel-0/notebooks/20-fase-1-raw.ipynb` en el editor (Jupyter Lab en el puerto
8888, se abre igual que pgAdmin: pestaña PORTS → 8888 → Open in Browser).

### Celda 0 — Conectar JupySQL

```python
%load_ext sql
%sql postgresql://postgres:changeme1234@localhost:5432/ny_taxi
```

### Celda 1 — Crear el schema raw

```sql
%%sql
CREATE SCHEMA IF NOT EXISTS raw;
```

Un schema es como una carpeta dentro de la base. Siempre se crea antes que la tabla.

### Celda 2 — Crear la tabla raw (todas las columnas como TEXT)

```sql
%%sql
DROP TABLE IF EXISTS raw.yellow_taxi_raw;
CREATE TABLE raw.yellow_taxi_raw (
    vendor_id TEXT,
    pickup_datetime TEXT,
    dropoff_datetime TEXT,
    passenger_count TEXT,
    trip_distance TEXT,
    ratecode_id TEXT,
    store_and_fwd_flag TEXT,
    pulocation_id TEXT,
    dolocation_id TEXT,
    payment_type TEXT,
    fare_amount TEXT,
    extra TEXT,
    mta_tax TEXT,
    tip_amount TEXT,
    tolls_amount TEXT,
    improvement_surcharge TEXT,
    total_amount TEXT,
    congestion_surcharge TEXT,
    airport_fee TEXT
);
```

Todo como TEXT a propósito: es la capa "sin tocar", refleja el CSV tal cual llega.

### Celda 3 — Cargar el CSV a la tabla raw

```bash
%%bash
psql postgresql://postgres:changeme1234@localhost:5432/ny_taxi -c "\copy raw.yellow_taxi_raw FROM '/workspaces/data-engineering-roadmap-2026/nivel-0/data/yellow_tripdata_2024-01.csv' CSV HEADER;"
```

> Ojo: debe ir en **una sola línea**. Si se parte con `\` + salto de línea dentro de
> las comillas dobles, bash interpreta eso como continuación de línea y se come el
> backslash — el `\copy` (cliente, lee el archivo del Codespace) se convierte en
> `copy` (servidor, `COPY`), que busca el archivo dentro del contenedor y falla con
> `No such file or directory`.

Salida esperada: `COPY 2964624` (debe coincidir con las filas leídas por pandas).

### 4. Validar con pgcli o pgAdmin (paso importante)

Desde **otra terminal** del Codespace (no la de Jupyter):

```bash
pgcli -h localhost -U postgres -d ny_taxi
```

```sql
\dt raw.*
SELECT COUNT(*) FROM raw.yellow_taxi_raw;
SELECT * FROM raw.yellow_taxi_raw LIMIT 5;
```

El `COUNT(*)` debe ser exactamente `2964624`.

### 5. Verificar la calidad del raw

```sql
SELECT
    pickup_datetime,
    passenger_count,
    trip_distance,
    total_amount
FROM raw.yellow_taxi_raw
LIMIT 5;
```

Todo sale como texto — esto motiva la Fase 2 (tipos correctos).

---

## FASE 2 — CURATED (tipos correctos + clave primaria)

TL;DR: tomamos RAW, casteamos a tipos correctos, agregamos PK, cargamos en
`curated.trip`. Regla general de casteo: **TEXT → NUMERIC → INTEGER** (nunca
TEXT → INTEGER directo si puede haber decimales como `"1.0"`).

### 1. Crear el notebook

```bash
cd nivel-0
python3 -c "import json; json.dump({'cells':[],'metadata':{},'nbformat':4,'nbformat_minor':5}, open('notebooks/21-fase-2-curated.ipynb','w'))"
```

Celda 0 igual que antes (conectar JupySQL).

### 2. Crear el schema y la tabla curated

```sql
%%sql
CREATE SCHEMA IF NOT EXISTS curated;

CREATE TABLE IF NOT EXISTS curated.trip (
    trip_id SERIAL PRIMARY KEY,
    vendor_id INTEGER,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    passenger_count INTEGER,
    trip_distance NUMERIC,
    fare_amount NUMERIC,
    total_amount NUMERIC,
    pulocation_id INTEGER,
    dolocation_id INTEGER
);
```

> Esta definición se infiere de la lista de columnas del INSERT que viene abajo
> (no se capturó el DDL exacto en video, pero coincide 1:1 con los tipos usados).

### 3. El error a propósito: casteo directo falla

```sql
%%sql
INSERT INTO curated.trip (
    vendor_id, pickup_datetime, dropoff_datetime, passenger_count,
    trip_distance, fare_amount, total_amount, pulocation_id, dolocation_id
)
SELECT
    vendor_id::INTEGER,
    pickup_datetime::TIMESTAMP,
    dropoff_datetime::TIMESTAMP,
    passenger_count::INTEGER,      -- ← esto falla
    trip_distance::NUMERIC,
    fare_amount::NUMERIC,
    total_amount::NUMERIC,
    pulocation_id::INTEGER,
    dolocation_id::INTEGER
FROM raw.yellow_taxi_raw;
```

Error esperado: `psycopg2.errors.InvalidTextRepresentation: invalid input syntax
for type integer: "1.0"`. Es intencional — el motor te protege de datos sucios.

| Input (texto) | `::INTEGER` directo | `::NUMERIC::INTEGER` |
|---|---|---|
| `"1"` | ✅ funciona | ✅ funciona |
| `"1.0"` | ❌ falla | ✅ funciona |
| `"abc"` | ❌ falla | ❌ falla |
| `NULL` | ✅ (NULL→NULL) | ✅ (NULL→NULL) |

### 4. Diagnóstico: detectar valores problemáticos (opcional pero útil)

```sql
%%sql
SELECT DISTINCT passenger_count
FROM raw.yellow_taxi_raw
WHERE passenger_count !~ '^[0-9]+(\.0)?$'
ORDER BY passenger_count
LIMIT 20;
```

El patrón regex `^[0-9]+(\.0)?$` acepta solo enteros o enteros con `.0` al final;
`!~` significa "no coincide con este patrón" (trae los valores fuera de ese formato).

### 5. El fix correcto: `::NUMERIC::INTEGER`

```sql
%%sql
INSERT INTO curated.trip (
    vendor_id, pickup_datetime, dropoff_datetime, passenger_count,
    trip_distance, fare_amount, total_amount, pulocation_id, dolocation_id
)
SELECT
    vendor_id::INTEGER,
    pickup_datetime::TIMESTAMP,
    dropoff_datetime::TIMESTAMP,
    passenger_count::NUMERIC::INTEGER,   -- ← fix
    trip_distance::NUMERIC,
    fare_amount::NUMERIC,
    total_amount::NUMERIC,
    pulocation_id::INTEGER,
    dolocation_id::INTEGER
FROM raw.yellow_taxi_raw;
```

Salida esperada: `INSERT 0 2964624` (tarda ~30s, normal).

### 6. Validar con pgcli o pgAdmin

```sql
\dt curated.*
SELECT COUNT(*) FROM curated.trip;                        -- debe ser 2964624
SELECT MIN(trip_id), MAX(trip_id) FROM curated.trip;
SELECT MIN(pickup_datetime), MAX(pickup_datetime) FROM curated.trip;
SELECT passenger_count, COUNT(*) AS n
FROM curated.trip GROUP BY passenger_count ORDER BY passenger_count LIMIT 10;
```

> `MIN(trip_id)`/`MAX(trip_id)` casi seguro **no** van a salir `1` y `2964624`
> exactos (en la práctica salió `3` y `2964626`). Es normal: la secuencia
> `SERIAL` avanza aunque el INSERT falle y haga rollback — el contador **no** se
> revierte, solo las filas. El primer INSERT (el que falla a propósito en el
> paso 3) ya consumió algunos valores de la secuencia antes de fallar. No hay
> filas perdidas ni duplicadas mientras el `COUNT(*)` sea exactamente
> `2964624` — solo quedan huecos en los IDs.
>
> Nota práctica de pgcli: si pegas varias queries de golpe, a veces el
> resultado de alguna se "pierde" visualmente en la terminal. Si algo no
> aparece, vuelve a correr esa query sola.

---

## FASE 3 — ANALYTICS (EDA, outliers, EXPLAIN ANALYZE, índices)

### 1. Crear el notebook

```bash
python3 -c "import json; json.dump({'cells':[],'metadata':{},'nbformat':4,'nbformat_minor':5}, open('notebooks/22-fase-3-analytics.ipynb','w'))"
```

### 2. EDA: contar y encontrar outliers

```sql
%%sql
SELECT
    COUNT(*) AS total_trips,
    MIN(pickup_datetime) AS min_pickup,
    MAX(pickup_datetime) AS max_pickup
FROM curated.trip;
```

Hallazgo esperado: aunque el CSV es de enero 2024, `min_pickup` sale como
`2002-12-31` — hay fechas corruptas heredadas de la fuente.

```sql
SELECT COUNT(*) AS outliers_before_2024
FROM curated.trip
WHERE pickup_datetime < '2024-01-01';
```

Salida verificada: `15` filas outlier (no 13 — número corregido tras ejecutarlo
en vivo).

### 3. Ingresos por día

```sql
%%sql
SELECT
    DATE(pickup_datetime) AS day,
    SUM(total_amount) AS revenue,
    COUNT(*) AS trips
FROM curated.trip
GROUP BY day
ORDER BY day
LIMIT 10;
```

### 4. Crear un índice

```sql
%%sql
CREATE INDEX idx_trip_pickup_datetime
ON curated.trip (pickup_datetime);
```

Convención de nombre: `idx_<tabla>_<columna>`.

### 5. EXPLAIN ANALYZE — cuándo el índice ayuda y cuándo no

```sql
%%sql
EXPLAIN ANALYZE
SELECT * FROM curated.trip
WHERE pickup_datetime >= '2024-01-15';   -- ~50% de las filas → Seq Scan
```

```sql
%%sql
EXPLAIN ANALYZE
SELECT * FROM curated.trip
WHERE pickup_datetime = '2024-01-15 08:00:00';   -- filtro puntual → Index Scan
```

- `EXPLAIN` solo estima (rápido, sin ejecutar). `EXPLAIN ANALYZE` ejecuta y mide
  tiempos reales (más lento, más preciso). En producción usar solo `EXPLAIN`.
- Postgres usa el índice cuando el filtro es muy selectivo (pocas filas de
  muchas); si el filtro devuelve ~50% de la tabla, prefiere `Seq Scan`.

### 6. Validar índices

> Los meta-comandos `\di`/`\dv`/`\dm`/`\dt` funcionan en **pgcli/psql**, pero no
> dentro de una celda de Jupyter (JupySQL los pasa a Python y da
> `SyntaxError`). En notebooks, usa el catálogo `pg_indexes` en su lugar:

```sql
%%sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'curated' AND tablename = 'trip';
```

Debe listar `trip_pkey` (PK, btree) y `idx_trip_pickup_datetime` (btree). (Desde
pgcli, en cambio, sí puedes usar `\di curated.*` directamente.)

> Lección macro: el SQL es portable, pero el modelo de ejecución no. En
> Snowflake/BigQuery/Redshift no hay índices tradicionales — usan pruning
> (micro-partitions, clustering). El criterio de "leer el plan del motor"
> sí es transferible.

---

## FASE 4 — OLAP PREP (dimensiones scaffolding, vistas, materialized view)

TL;DR: construimos dimensiones "andamio" (`zone`, `vendor`) — no son dimensiones
reales de modelado dimensional (eso se hace con dbt en Nivel-4) — más una vista
denormalizada y una materialized view con agregados precomputados.

### 1. Crear el notebook

```bash
python3 -c "import json; json.dump({'cells':[],'metadata':{},'nbformat':4,'nbformat_minor':5}, open('notebooks/24-fase-4-views.ipynb','w'))"
```

### 2. Cargar `taxi_zone_lookup.csv` a raw

```bash
cd nivel-0/data
wget https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv
```

```bash
%%bash
psql postgresql://postgres:changeme1234@localhost:5432/ny_taxi << 'EOF'
DROP TABLE IF EXISTS raw.taxi_zone_lookup;
CREATE TABLE raw.taxi_zone_lookup (
    location_id TEXT,
    borough TEXT,
    zone TEXT,
    service_zone TEXT
);
\copy raw.taxi_zone_lookup FROM '/workspaces/data-engineering-roadmap-2026/nivel-0/data/taxi_zone_lookup.csv' CSV HEADER;
EOF
```

> Usa heredoc (`<< 'EOF' ... EOF`) en vez de `-c "\` + salto de línea: con `-c` y
> comillas dobles, bash se come el backslash de continuación y convierte `\copy`
> en `copy` (ver el mismo bug explicado en la Celda 3 de Fase 1).

### 3. View `curated.zone`

```sql
%%sql
CREATE OR REPLACE VIEW curated.zone AS
SELECT
    location_id::INTEGER AS location_id,
    zone AS zone_name,
    borough,
    service_zone
FROM raw.taxi_zone_lookup;
```

### 4. View sintética `curated.vendor`

El CSV no trae tabla de vendors, solo IDs. Se interpreta a mano:

```sql
%%sql
CREATE OR REPLACE VIEW curated.vendor AS
SELECT DISTINCT
    vendor_id,
    CASE vendor_id
        WHEN 1 THEN 'Creative Mobile Technologies'
        WHEN 2 THEN 'VeriFone Inc.'
        WHEN 4 THEN 'Unknown / Other'
        ELSE 'Vendor ' || vendor_id::TEXT
    END AS vendor_name
FROM curated.trip
WHERE vendor_id IS NOT NULL
ORDER BY vendor_id;
```

### 5. Validar dimensiones

Igual que en Fase 3: en Jupyter usa `information_schema` en vez de `\dv`
(meta-comando de psql/pgcli, no de JupySQL):

```sql
%%sql
SELECT table_name FROM information_schema.views WHERE table_schema = 'curated';
SELECT * FROM curated.zone LIMIT 5;
SELECT * FROM curated.vendor LIMIT 5;
```

### 6. View denormalizada `curated.vw_trip_denorm`

```sql
%%sql
CREATE OR REPLACE VIEW curated.vw_trip_denorm AS
SELECT
    t.trip_id,
    t.vendor_id,
    v.vendor_name,
    t.pickup_datetime,
    t.dropoff_datetime,
    t.passenger_count,
    t.trip_distance,
    t.fare_amount,
    t.total_amount,
    t.pulocation_id,
    pz.borough AS pickup_borough,
    pz.zone_name AS pickup_zone,
    t.dolocation_id,
    dz.borough AS dropoff_borough,
    dz.zone_name AS dropoff_zone
FROM curated.trip t
LEFT JOIN curated.vendor v ON t.vendor_id = v.vendor_id
LEFT JOIN curated.zone pz ON t.pulocation_id = pz.location_id
LEFT JOIN curated.zone dz ON t.dolocation_id = dz.location_id;
```

> `t.tip_amount` estaba en la versión original de esta guía pero no existe en
> `curated.trip` — su `CREATE TABLE` (Fase 2, definición inferida) nunca incluyó
> esa columna. Se quitó de la view; si la quieres disponible, tocaría un
> `ALTER TABLE curated.trip ADD COLUMN tip_amount NUMERIC;` + backfill desde
> `raw.yellow_taxi_raw`, fuera del alcance verificado de esta guía.

Usa `LEFT JOIN` (no `INNER JOIN`) a propósito: preserva viajes con `vendor_id`,
`pulocation_id` o `dolocation_id` inválidos/NULL — también son parte de la
realidad del dataset y conviene poder identificarlos después.

### 7. Materialized view `curated.mv_daily_zone`

```sql
%%sql
CREATE MATERIALIZED VIEW curated.mv_daily_zone AS
SELECT
    DATE(pickup_datetime) AS day,
    pulocation_id,
    COUNT(*) AS trip_count,
    SUM(total_amount) AS total_revenue,
    AVG(trip_distance) AS avg_distance,
    AVG(passenger_count) AS avg_passengers
FROM curated.trip
WHERE pickup_datetime >= '2024-01-01'
GROUP BY DATE(pickup_datetime), pulocation_id
ORDER BY day, pulocation_id;

CREATE UNIQUE INDEX idx_mv_daily_zone_day_loc
ON curated.mv_daily_zone (day, pulocation_id);
```

Diferencia con una view normal: la materialized view **guarda físicamente** el
resultado (no se recalcula en cada consulta) — ideal para agregaciones costosas
que se consultan muchas veces. Hay que refrescarla manualmente si cambian los
datos base (`REFRESH MATERIALIZED VIEW curated.mv_daily_zone;`).

### 8. Validar

```sql
%%sql
SELECT matviewname FROM pg_matviews WHERE schemaname = 'curated';
SELECT * FROM curated.mv_daily_zone LIMIT 5;
```

### 9. Anti-patrón a evitar

Mal (JOINs repetidos en cada query analítica):

```sql
SELECT DATE(t.pickup_datetime) AS day, pz.zone_name, SUM(t.total_amount) AS revenue
FROM curated.trip t
LEFT JOIN curated.zone pz ON t.pulocation_id = pz.location_id
WHERE t.pickup_datetime >= '2024-01-01'
GROUP BY DATE(t.pickup_datetime), pz.zone_name;
```

Bien (usar la view ya resuelta):

```sql
SELECT DATE(pickup_datetime) AS day, pickup_zone, SUM(total_amount) AS revenue
FROM curated.vw_trip_denorm
WHERE pickup_datetime >= '2024-01-01'
GROUP BY DATE(pickup_datetime), pickup_zone;
```

Mismo resultado, la mitad de líneas, y si cambia el modelo solo se toca la
definición de la view — no las queries de los analistas.

---

## Cierre

Con esto termina el video (Nivel 0 completo). Resumen del estado final en
`ny_taxi`:

- `raw.yellow_taxi_raw`, `raw.taxi_zone_lookup` — datos crudos como TEXT.
- `curated.trip` — tabla tipada con PK (`trip_id`).
- `curated.zone`, `curated.vendor` — dimensiones scaffolding (views).
- `curated.vw_trip_denorm` — view denormalizada para análisis.
- `curated.mv_daily_zone` — materialized view con agregados por día/zona.

DBeaver, DAX y Power Query **no aparecen** en este video — quedan fuera del
alcance de esta guía.
