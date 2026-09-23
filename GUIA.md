# Setup del entorno: Postgres + pgcli + pgAdmin

Replica de la sección "SETUP DEL ENTORNO: POSTGRES + PGCLI + PGADMIN" del video,
pensada para correr dentro de un GitHub Codespace (o cualquier VM Linux con Docker).

## 0. Copiar estos archivos al Codespace

En la raíz de tu repo, dentro del Codespace, crea esta estructura:

```
/ (raíz del repo)
├── docker-compose.yml
├── config/
│   ├── postgres.env
│   └── pgadmin.env
└── setup.sh
```

La forma más rápida: en la terminal del Codespace, pega el contenido de cada archivo
con `cat > archivo << 'EOF' ... EOF` (te doy el bloque exacto cuando estés ahí), o
arrástralos al explorador de archivos de VS Code Web.

## 1. Estructura de carpetas del nivel

```bash
mkdir -p nivel-0/notebooks nivel-0/sql nivel-0/data
cd nivel-0
pwd
```

- `mkdir -p nivel-0` — crea la carpeta `nivel-0` (con `-p` no falla si ya existe).
- `cd nivel-0` — te mueves a esa carpeta; todo el trabajo del nivel vive ahí.
- `mkdir -p notebooks sql data` — subcarpetas para notebooks, queries SQL y datos.
- `pwd` — confirma el directorio actual.

## 2. Inspeccionar el docker-compose.yml

```bash
cd ..
cat docker-compose.yml
```

Busca el servicio **postgres-2**: mapea el puerto del contenedor al host (por eso
luego nos conectamos por `localhost`), y lee sus credenciales desde `config/postgres.env`.

```bash
cat config/postgres.env
```

| Variable | Valor | Uso |
|---|---|---|
| POSTGRES_USER | postgres | usuario de Postgres |
| POSTGRES_PASSWORD | changeme1234 | contraseña |
| POSTGRES_DB | postgres | base de datos por defecto |

## 3. Instalar pgcli

```bash
sudo apt update && sudo apt install pgcli -y
pgcli --version
```

- `sudo apt update` — actualiza el catálogo de paquetes disponibles.
- `sudo apt install pgcli -y` — instala pgcli a nivel de sistema (no necesita venv,
  es una CLI standalone). El `-y` responde "sí" automáticamente.
- `pgcli --version` — confirma la instalación (ej. `Version: 3.5.1`).

## 4. Levantar Postgres

```bash
docker compose up -d postgres-2
docker ps
```

- `docker compose up -d postgres-2` — arranca **solo** el servicio postgres-2, en
  segundo plano (`-d`).
- `docker ps` — debe mostrar `postgres-container` con estado `Up ... (healthy)`.

### 4.1 Verificar que responde

```bash
docker exec -it postgres-container psql -U postgres -d postgres -c "SELECT version();"
```

- `docker exec -it postgres-container ...` — ejecuta un comando dentro del contenedor.
- `psql -U postgres -d postgres -c "SELECT version();"` — corre esa query con el
  cliente `psql` ya instalado dentro del contenedor.

## 5. pgcli en acción

```bash
pgcli -h localhost -U postgres -d postgres
```

Pide la contraseña (`changeme1234`). Si todo sale bien verás el prompt:

```
postgres@localhost:postgres>
```

One-liner para scripts (sin prompt de password, usando variable de entorno):

```bash
PGPASSWORD=changeme1234 pgcli -h localhost -U postgres -d postgres
```

Comandos útiles dentro de pgcli:

| Comando | Qué hace |
|---|---|
| `\l` | lista todas las bases de datos |
| `\dt` | lista las tablas de la base actual |
| `\d <tabla>` | describe una tabla (columnas, tipos) |
| `\dn` | lista los esquemas |
| `SELECT 1;` | prueba de conexión |
| `\q` | salir de pgcli |

## 6. pgAdmin en acción

```bash
cd ..
docker compose up -d pgadmin
docker ps
```

Abre en el navegador del Codespace: **http://localhost:5050**

> Nota corregida sobre el video: el puerto real reenviado por pgAdmin es **5050**
> (se ve en el panel "Ports" del Codespace), no 8080.

### 6.1 Login en pgAdmin

Credenciales (definidas en `config/pgadmin.env`):

- Email: `pgadmin4@pgadmin.org`
- Password: `admin`

### 6.2 Registrar el servidor Postgres dentro de pgAdmin

Clic derecho en "Servers" → **Register → Server**

**Pestaña General**
- Name: `Postgres`

**Pestaña Connection**
- Host name/address: `postgres-container` (nombre del contenedor en la red de Docker;
  NO uses `localhost` aquí porque pgAdmin corre en su propio contenedor)
- Port: `5432`
- Maintenance database: `postgres`
- Username: `postgres`
- Password: `changeme1234`
- Save password: activar (opcional, comodidad)

Guarda. Deberías ver en el árbol: `Servers > Postgres > Databases > postgres`.

Para probar: clic derecho en la base `postgres` → **Query Tool**, y corre:

```sql
SELECT version();
```

Si devuelve algo como `PostgreSQL 13.14 ...`, pgAdmin está conectado correctamente.

## 7. (Opcional) venv y dependencias de Python

Si vas a usar notebooks/pandas contra esta base, dentro de `nivel-0/`:

```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install pyarrow pandas psycopg2 sqlalchemy
```

---

## Sobre Airflow / Superset / Spark

Esos servicios aparecen referenciados de fondo en el `docker-compose.yml` completo
del curso, pero **no se levantan en esta sección del video** (solo se usa
`docker compose up -d postgres-2` y `docker compose up -d pgadmin`, uno a la vez).
Todo indica que pertenecen a un nivel/sección posterior del curso que no se analizó
todavía. Si me confirmas el minuto o el nombre de esa sección, reviso el video y
preparo esa parte igual de verificada — prefiero no inventar esa configuración.
