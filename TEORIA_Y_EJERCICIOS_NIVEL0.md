# Teoría y ejercicios — Nivel 0 (NYC Yellow Taxi)

Un concepto por sección: qué es, para qué sirve, el código que realmente
corrimos, y el resultado real obtenido (no simulado) en la sesión sobre
`ny_taxi`. Sirve como material de repaso independiente de la guía paso a paso
(`GUIA_COMPLETA_NIVEL0.md`).

---

## 1. Docker Compose

**Qué es:** una herramienta para definir y levantar varios contenedores
Docker relacionados (servicios) con un solo archivo YAML, en vez de escribir
comandos `docker run` largos y repetirlos a mano.

**Para qué sirve:** en este nivel, levantar Postgres y pgAdmin juntos, ya
conectados en la misma red interna, con sus credenciales y puertos definidos
una sola vez.

**Código (`docker-compose.yml`):**
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

Piezas clave:
- `container_name`: nombre fijo del contenedor — también funciona como
  hostname dentro de la red de Docker (por eso pgAdmin se conecta a Postgres
  usando `postgres-container`, no `localhost`).
- `env_file`: carga variables (usuario, password) desde un archivo aparte, en
  vez de escribirlas directo en el YAML.
- `volumes` (nombrado, `postgres-db-volume`): persiste los datos de Postgres
  aunque el contenedor se destruya y se recree.
- `healthcheck`: le dice a Docker cómo saber si Postgres ya está listo para
  aceptar conexiones (no solo si el proceso arrancó).
- `depends_on`: pgAdmin espera a que el servicio `postgres-2` inicie primero
  (aunque no espera al healthcheck, solo al arranque).

**Resultado real:**
```
docker compose up -d
[+] up 2/2
 ✔ Container postgres-container Started
 ✔ Container pgadmin-container  Started
```
Con `docker ps`, ambos contenedores en estado `Up ... (healthy)`.

---

## 2. Clientes de Postgres: pgcli, psql, pgAdmin

**Qué es:** tres formas distintas de hablar con el mismo motor de base de
datos — dos de línea de comandos (`psql`, el cliente oficial; `pgcli`, una
versión con autocompletado y resaltado de sintaxis) y una gráfica web
(`pgAdmin`).

**Para qué sirve:** `psql`/`pgcli` para trabajo rápido en terminal y para
scripts (`psql` es el único que corre bien dentro de `%%bash` en notebooks);
`pgAdmin` para explorar visualmente el árbol de bases/schemas/tablas y correr
queries con una interfaz de "Query Tool".

**Código:**
```bash
pgcli -h localhost -U postgres -d ny_taxi        # terminal, interactivo
psql postgresql://postgres:changeme1234@localhost:5432/ny_taxi -c "SELECT 1;"  # scripts
```

**Detalle importante:** desde la terminal del Codespace (host), Postgres se
alcanza en `localhost:5432` porque el puerto está publicado
(`ports: "5432:5432"` en el compose). Pero **dentro** de la red de Docker
—que es donde vive el contenedor de pgAdmin— hay que usar el nombre del
contenedor (`postgres-container`), no `localhost`, porque pgAdmin no comparte
la red del host.

**Resultado real:** registrar el servidor en pgAdmin con Host=
`postgres-container` funcionó; con Host=`localhost` daba timeout (pgAdmin
buscaba Postgres dentro de su propio contenedor, donde no hay nada
escuchando en ese puerto).

---

## 3. Schema

**Qué es:** un espacio de nombres dentro de una base de datos — como una
carpeta que agrupa tablas, vistas e índices. Una base (`ny_taxi`) puede tener
varios schemas (`raw`, `curated`) sin que sus tablas choquen entre sí.

**Para qué sirve:** separar capas de un pipeline de datos (crudo vs curado)
dentro de la misma base, en vez de usar bases distintas o prefijos en los
nombres de tabla.

**Código:**
```sql
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS curated;
```

**Resultado:** ambos schemas creados sin error; `raw.yellow_taxi_raw` y
`curated.trip` conviven en `ny_taxi` sin conflicto de nombres.

---

## 4. Capa RAW: todo como TEXT

**Qué es:** una tabla que refleja el CSV de origen sin ninguna conversión de
tipos — cada columna es `TEXT`, incluso las que "deberían" ser número o fecha.

**Para qué sirve:** aislar los problemas de calidad de datos del origen (texto
mal formado, decimales donde se esperaba un entero, fechas corruptas) para que
nunca rompan la carga inicial. Si el `COPY` falla por un tipo, se pierde la
ingesta completa; con TEXT, el archivo siempre carga.

**Código:**
```sql
CREATE TABLE raw.yellow_taxi_raw (
    vendor_id TEXT, pickup_datetime TEXT, dropoff_datetime TEXT,
    passenger_count TEXT, trip_distance TEXT, ratecode_id TEXT,
    store_and_fwd_flag TEXT, pulocation_id TEXT, dolocation_id TEXT,
    payment_type TEXT, fare_amount TEXT, extra TEXT, mta_tax TEXT,
    tip_amount TEXT, tolls_amount TEXT, improvement_surcharge TEXT,
    total_amount TEXT, congestion_surcharge TEXT, airport_fee TEXT
);
```

**Resultado real:** `COPY 2964624` — las 2,964,624 filas del CSV cargaron sin
un solo error, precisamente porque nada se intentó castear en la carga (ver
sección 5 sobre cómo se hizo esa carga).

---

## 5. `\copy` (cliente) vs `COPY` (servidor)

**Qué es:** dos formas de cargar un archivo a una tabla, con una diferencia
crítica de **dónde** vive el archivo. `COPY` (mayúscula, comando SQL) le pide
al **servidor** de Postgres que lea el archivo — tiene que existir dentro del
contenedor del servidor. `\copy` (con backslash, meta-comando de `psql`) lee
el archivo desde la máquina donde corre el **cliente** `psql`, y lo transmite
por la conexión — no necesita que el archivo esté dentro del contenedor.

**Para qué sirve:** en este setup, el CSV vive en el Codespace (el host),
mientras que Postgres corre dentro de su propio contenedor Docker. `\copy` es
la única opción que funciona sin antes copiar el archivo dentro del
contenedor.

**Código correcto (una sola línea, o heredoc si son varios statements):**
```bash
psql postgresql://postgres:changeme1234@localhost:5432/ny_taxi \
  -c "\copy raw.yellow_taxi_raw FROM '/workspaces/.../yellow_tripdata_2024-01.csv' CSV HEADER;"
```
```bash
psql postgresql://postgres:changeme1234@localhost:5432/ny_taxi << 'EOF'
CREATE TABLE raw.taxi_zone_lookup (...);
\copy raw.taxi_zone_lookup FROM '/workspaces/.../taxi_zone_lookup.csv' CSV HEADER;
EOF
```

**El error real que nos pasó (dos veces):** al partir el `-c "..."` con un
`\` seguido de salto de línea dentro de comillas dobles, bash interpreta eso
como continuación de línea y **se come el backslash** — `\copy` llega a
`psql` como `copy` (sin backslash, minúscula), que Postgres interpreta como el
comando SQL `COPY` de servidor, no el meta-comando de cliente:
```
ERROR:  could not open file "/workspaces/.../yellow_tripdata_2024-01.csv" for reading: No such file or directory
HINT:  COPY FROM instructs the PostgreSQL server process to read a file.
       You may want a client-side facility such as psql's \copy.
```
El propio `HINT` de Postgres explica el problema. Fix: todo en una sola línea,
o usar heredoc (`<< 'EOF' ... EOF`) para bloques con varios statements — así
bash nunca toca el contenido dentro del `\copy`.

---

## 6. Casteo seguro: `TEXT → NUMERIC → INTEGER`

**Qué es:** la regla de que un texto como `"1.0"` no puede convertirse
directo a `INTEGER` en Postgres, aunque represente un entero — hay que pasar
primero por `NUMERIC`.

**Para qué sirve:** evitar que la carga de la capa curada falle por completo
ante un solo valor con formato decimal. Es la razón real por la que muchos
pipelines separan RAW (TEXT) de CURATED (tipado).

**Código (falla a propósito):**
```sql
SELECT passenger_count::INTEGER FROM raw.yellow_taxi_raw;  -- falla
```
**Código (fix):**
```sql
SELECT passenger_count::NUMERIC::INTEGER FROM raw.yellow_taxi_raw;  -- funciona
```

**Resultado real:**
```
psycopg2.errors.InvalidTextRepresentation: invalid input syntax
for type integer: "1.0"
```
Con `::NUMERIC::INTEGER`, el `INSERT INTO curated.trip (...)` de las
2,964,624 filas corrió sin error.

---

## 7. Detección de calidad de datos con regex

**Qué es:** usar un patrón de expresión regular contra una columna `TEXT`
para separar valores "bien formados" de los que no calzan con el formato
esperado, antes de intentar castear nada.

**Para qué sirve:** diagnosticar *qué tan sucia* está realmente una columna
antes de decidir el fix — en vez de adivinar por qué falla un `::CAST`.

**Código:**
```sql
SELECT DISTINCT passenger_count
FROM raw.yellow_taxi_raw
WHERE passenger_count !~ '^[0-9]+(\.0)?$'
ORDER BY passenger_count
LIMIT 20;
```
`^[0-9]+(\.0)?$` acepta enteros, o enteros seguidos de `.0`. `!~` significa
"no coincide con este patrón" — trae los valores que quedan **fuera** de ese
formato.

**Resultado real:** **0 filas.** Es decir, no había texto realmente corrupto
en `passenger_count` — todos los valores eran enteros o enteros con `.0`. El
error de casteo de la sección 6 no era un problema de datos sucios, sino de
la regla estricta de Postgres para convertir texto a entero. La misma técnica
sirve para el caso contrario: si esta query hubiera devuelto filas, esas
serían los valores genuinamente problemáticos a limpiar antes de castear.

---

## 8. Primary Key con `SERIAL`

**Qué es:** una columna autoincremental (`SERIAL`) marcada como llave primaria,
que Postgres garantiza única — pero **no** garantiza sin huecos.

**Para qué sirve:** identificar cada fila de forma inequívoca sin depender de
una combinación de columnas del negocio.

**Código:**
```sql
CREATE TABLE curated.trip (
    trip_id SERIAL PRIMARY KEY,
    ...
);
```

**Resultado real (hallazgo importante):** tras el INSERT que falló a
propósito (sección 6) y el INSERT que sí funcionó después, el rango de
`trip_id` salió `MIN=3, MAX=2964626` — no `1` y `2964624` como "debería" ser
con 2,964,624 filas consecutivas. Motivo: la secuencia de `SERIAL` avanza
igual aunque el `INSERT` haga rollback; el contador no se revierte, solo las
filas. Confirmado con `SELECT COUNT(*) FROM curated.trip` = exactamente
`2964624` — cero filas perdidas, solo IDs no consecutivos.

---

## 9. `EXPLAIN` vs `EXPLAIN ANALYZE`

**Qué es:** `EXPLAIN` muestra el plan de ejecución **estimado** por el
optimizador, sin correr la query. `EXPLAIN ANALYZE` **ejecuta realmente** la
query y agrega tiempos reales medidos.

**Para qué sirve:** decidir si una query necesita un índice, y verificar si
Postgres realmente lo está usando. En producción se prefiere `EXPLAIN` solo
(no ejecuta dos veces una query costosa).

**Código y resultado real — filtro amplio (sin índice útil):**
```sql
EXPLAIN ANALYZE
SELECT * FROM curated.trip WHERE pickup_datetime >= '2024-01-15';
```
```
Seq Scan on trip (actual time=94.178..254.300 rows=1678072 loops=1)
  Filter: (pickup_datetime >= '2024-01-15 00:00:00'::timestamp)
  Rows Removed by Filter: 1286552
Execution Time: 313.505 ms
```
Ese filtro devuelve el 57% de la tabla (1.68M de 2.96M filas) — Postgres
decide que leer todo (`Seq Scan`) es más barato que usar el índice.

**Código y resultado real — filtro puntual (índice útil):**
```sql
EXPLAIN ANALYZE
SELECT * FROM curated.trip WHERE pickup_datetime = '2024-01-15 08:00:00';
```
```
Index Scan using idx_trip_pickup_datetime on trip (rows=0 loops=1)
Execution Time: 0.064 ms
```
`Index Scan`, ~5,000x más rápido que el `Seq Scan` de arriba.

---

## 10. Índices B-tree

**Qué es:** una estructura de datos ordenada que Postgres mantiene aparte de
la tabla, para localizar filas sin recorrerla completa — el tipo por defecto
es B-tree, ideal para igualdades y rangos.

**Para qué sirve:** acelerar filtros selectivos (pocas filas de muchas). No
ayuda, y hasta estorba (hay que mantenerlo en cada INSERT/UPDATE), en filtros
que devuelven una porción grande de la tabla.

**Código:**
```sql
CREATE INDEX idx_trip_pickup_datetime ON curated.trip (pickup_datetime);
```
Verificación (en Jupyter, vía catálogo — `\di` es de pgcli/psql, no de
JupySQL):
```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'curated' AND tablename = 'trip';
```

**Resultado real:**
```
trip_pkey                  | CREATE UNIQUE INDEX trip_pkey ON curated.trip USING btree (trip_id)
idx_trip_pickup_datetime   | CREATE INDEX idx_trip_pickup_datetime ON curated.trip USING btree (pickup_datetime)
```

> Nota macro: el SQL es portable, pero el modelo de ejecución no. En
> Snowflake/BigQuery/Redshift no hay índices B-tree tradicionales — usan
> pruning (micro-partitions, clustering). Lo transferible es el hábito de
> "leer el plan del motor", no la sintaxis del índice.

---

## 11. Views (vistas)

**Qué es:** una query guardada con nombre, que se re-ejecuta cada vez que se
consulta — no almacena datos, solo la definición.

**Para qué sirve:** centralizar lógica repetida (JOINs, CASE) en un solo
lugar, para que las queries de análisis queden simples y consistentes.

**Código — vista "dimensión scaffolding" con CASE (`vendor_id` → nombre):**
```sql
CREATE OR REPLACE VIEW curated.vendor AS
SELECT DISTINCT vendor_id,
    CASE vendor_id
        WHEN 1 THEN 'Creative Mobile Technologies'
        WHEN 2 THEN 'VeriFone Inc.'
        WHEN 4 THEN 'Unknown / Other'
        ELSE 'Vendor ' || vendor_id::TEXT
    END AS vendor_name
FROM curated.trip WHERE vendor_id IS NOT NULL ORDER BY vendor_id;
```

**Resultado real:**
```
vendor_id | vendor_name
1         | Creative Mobile Technologies
2         | VeriFone Inc.
6         | Vendor 6
```
`vendor_id = 6` no estaba mapeado en el `CASE` y cayó correctamente en el
`ELSE` — así se comporta un mapeo con "fallback" ante valores no previstos.

**Código — vista denormalizada (varios `LEFT JOIN`):**
```sql
CREATE OR REPLACE VIEW curated.vw_trip_denorm AS
SELECT t.trip_id, t.vendor_id, v.vendor_name, t.pickup_datetime,
       t.pulocation_id, pz.borough AS pickup_borough, pz.zone_name AS pickup_zone,
       t.dolocation_id, dz.borough AS dropoff_borough, dz.zone_name AS dropoff_zone
FROM curated.trip t
LEFT JOIN curated.vendor v ON t.vendor_id = v.vendor_id
LEFT JOIN curated.zone pz ON t.pulocation_id = pz.location_id
LEFT JOIN curated.zone dz ON t.dolocation_id = dz.location_id;
```
Se usa `LEFT JOIN` (no `INNER JOIN`) a propósito: preserva viajes con
`vendor_id`/`pulocation_id`/`dolocation_id` inválidos o NULL en vez de
descartarlos silenciosamente.

**Comparación real (anti-patrón vs vista), mismo resultado exacto:**
```sql
-- Repitiendo el JOIN en cada query analítica (anti-patrón)
SELECT DATE(t.pickup_datetime) AS day, pz.zone_name, SUM(t.total_amount) AS revenue
FROM curated.trip t LEFT JOIN curated.zone pz ON t.pulocation_id = pz.location_id
WHERE t.pickup_datetime >= '2024-01-01' GROUP BY day, pz.zone_name;

-- Usando la vista ya resuelta
SELECT DATE(pickup_datetime) AS day, pickup_zone, SUM(total_amount) AS revenue
FROM curated.vw_trip_denorm
WHERE pickup_datetime >= '2024-01-01' GROUP BY day, pickup_zone;
```
Ambas devolvieron, fila por fila, el mismo resultado (ej. `2024-01-01,
Alphabet City, 5600.35`) — la ventaja de la vista no es el resultado, es que
la lógica del JOIN vive en un solo lugar.

---

## 12. Materialized View

**Qué es:** una vista que, a diferencia de una vista normal, **guarda
físicamente** el resultado de la query en disco en el momento en que se crea
(o se refresca) — no se recalcula en cada consulta.

**Para qué sirve:** pre-calcular agregaciones costosas (sumas, promedios sobre
millones de filas) que se van a consultar muchas veces, para que leerlas sea
tan rápido como leer una tabla normal. El costo: los datos pueden quedar
desactualizados si la tabla base cambia — hay que refrescarla a mano (o con un
job programado).

**Código:**
```sql
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
Para refrescarla si cambian los datos base:
```sql
REFRESH MATERIALIZED VIEW curated.mv_daily_zone;
```
Validación (catálogo `pg_matviews`, no `\dm` — ese es de pgcli/psql):
```sql
SELECT matviewname FROM pg_matviews WHERE schemaname = 'curated';
SELECT * FROM curated.mv_daily_zone LIMIT 5;
```

**Resultado real:** `6952 rows affected` al crearla (una fila por combinación
día × zona de recogida, ya agregada). Muestra:
```
day        | pulocation_id | trip_count | total_revenue | avg_distance | avg_passengers
2024-01-01 | 1             | 21         | 1991.52        | 0.8157...    | 2.3809...
2024-01-01 | 3             | 1          | 36.77          | 9.66         | None
2024-01-01 | 4             | 207        | 5600.35        | 3.2018...    | 1.3225...
```
Una consulta sobre `mv_daily_zone` (6,952 filas) es instantánea comparada con
recalcular la misma agregación cada vez sobre `curated.trip` (2.96M filas).

---

## 13. Resumen: vista vs materialized view vs tabla

| | Vista | Materialized view | Tabla |
|---|---|---|---|
| ¿Guarda datos? | No, recalcula siempre | Sí, hasta el próximo `REFRESH` | Sí, definitivo |
| ¿Se actualiza sola? | Sí (siempre al día) | No, hay que refrescarla | No aplica |
| ¿Cuándo usarla? | Lógica reusable, datos que cambian seguido | Agregaciones costosas, consultadas muchas veces | Datos fuente, capa RAW/CURATED |

---

## Fuente de estos ejercicios

Todo el código y los resultados de este documento se ejecutaron y verificaron
en vivo sobre el Codespace real (`data-engineering-roadmap-2026`), base
`ny_taxi`, durante esta sesión — no son transcripción del video sin probar. El
paso a paso completo, en orden, está en `GUIA_COMPLETA_NIVEL0.md`.
