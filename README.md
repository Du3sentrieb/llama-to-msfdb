# llama-to-msfdb

**Give a locally hosted LLM read-only access to Metasploit's database.**

A personal project that connects [`llama.cpp`](https://github.com/ggml-org/llama.cpp) to the Metasploit Framework PostgreSQL database (`msfdb`) through a small Python [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server.

The goal is to let a local model answer questions about an existing Metasploit workspace —for example, which hosts were discovered, which services they expose, and what those results might mean— without giving the model permission to modify the database or run Metasploit modules (yet).

> **Project status:** Experimental, partly vibe-coded, and built for my own Kali Linux environment. Review the scripts and adapt the paths before using them elsewhere.

## My setup

| Component | Configuration |
| --- | --- |
| Operating system | Kali Linux (bare metal) |
| GPU | NVIDIA RTX 4090 (24 GB VRAM) |
| System memory | 32 GB DDR5 |
| Inference runtime | `llama.cpp` / `llama-server` |
| GPU backend | Vulkan |
| Model | `unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf` |
| Model context | 16,384 tokens |
| Database | Metasploit's PostgreSQL database (`msf`) |
| Integration | Python MCP server using `mcp` and `psycopg` |

I initially tried Ollama and a CUDA build of `llama.cpp`. After some NVIDIA driver/toolkit bs, I ended up using the Vulkan backend. Ollama isn't required to run the final `llama-server` + MCP setup.

My `llama.cpp` checkout currently lives inside the project directory, but it can be installed anywhere. The paths in the launcher simply need to match your machine.

## Prerequisites

- Kali Linux with a working Metasploit installation and PostgreSQL database.
- A working `llama-server` build (Vulkan in my case) and a downloaded GGUF model.
- Python 3 with virtual environment support, plus the PostgreSQL client (`psql`).
- The project's **Python MCP server** and **`start-server.sh` launcher**, configured for your local paths.

> **Note:** This README describes the setup; the MCP server and startup script must also be present. A database user alone does not connect `llama-server` to Metasploit.

## Setup

### 1. Verify `llama-server` supports MCP

**In a Kali terminal**, run the following from your `llama.cpp` checkout (adjust the path if needed):

```bash
./build-vulkan/bin/llama-server --help | grep -i mcp
```

Look for `--mcp-servers-config`. This option is experimental and requires a sufficiently recent `llama.cpp` build.

### 2. Set up the Python MCP environment

**In a Kali terminal**, navigate to the directory containing your Python MCP server, then run:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install 'mcp>=1.28,<2' 'psycopg[binary]'
```

The MCP server is a small Python bridge between `llama-server` and PostgreSQL. It should expose **specific, parameterized read-only queries**, not a general-purpose SQL execution tool.

The launcher must reference the correct `.venv/bin/python` and MCP server file.

### 3. Start and verify the Metasploit database

**In a Kali terminal:**

```bash
# Only needed once on a fresh Metasploit database setup:
sudo msfdb init

# Start the database on subsequent sessions:
sudo msfdb start

# Check the Metasploit connection:
msfconsole
```

**Inside `msfconsole`** (prompt like `msf6 >`):

```text
db_status
```

Expected output:

```text
[*] Connected to msf. Connection type: postgresql.
```

### 4. Create a read-only PostgreSQL user

Open **another Kali terminal**, then start the PostgreSQL console as an administrator:

```bash
sudo -u postgres psql
```

The prompt should resemble `postgres=#`. **All commands in this subsection go into `psql`, not `msfconsole` or the shell.**

Check that the `msf` database exists:

```sql
\l
```

Create a dedicated account and set its password (only do this once):

```sql
CREATE ROLE msf_ai LOGIN;
\password msf_ai
```

Give it permission to connect to the Metasploit database:

```sql
GRANT CONNECT ON DATABASE msf TO msf_ai;
\connect msf
```

The prompt should now resemble `msf=#`. Grant access **only** to the tables the MCP bridge needs:

```sql
GRANT USAGE ON SCHEMA public TO msf_ai;

GRANT SELECT ON
    public.workspaces,
    public.hosts,
    public.services
TO msf_ai;

ALTER ROLE msf_ai
SET default_transaction_read_only = on;
```

The restricted `SELECT` grants enforce the database permissions; the read-only transaction default adds defense in depth. If the MCP server later uses more tables, grant access to those tables explicitly instead of granting broad access to the entire database.

Exit `psql`:

```text
\q
```

> If your PostgreSQL database or role already exists, don't recreate it. Check the current configuration first. Database names and TCP ports can vary between installations.

### 5. Configure passwordless local access for the launcher

**Back in your Kali terminal**, create a PostgreSQL password file:

```bash
touch ~/.pgpass
chmod 600 ~/.pgpass
nano ~/.pgpass
```

Add a line using the password you assigned to `msf_ai`:

```text
127.0.0.1:5432:msf:msf_ai:YOUR_PASSWORD
```

Replace `YOUR_PASSWORD` with the real password, and adjust the port/database name if necessary. Ensure the file is only readable by your account:

```bash
chmod 600 ~/.pgpass
```

### 6. Test the restricted database account

**In a Kali terminal:**

```bash
psql -h 127.0.0.1 -p 5432 -U msf_ai -d msf \
  -c 'SELECT COUNT(*) FROM public.hosts;'

psql -h 127.0.0.1 -p 5432 -U msf_ai -d msf \
  -c 'SELECT COUNT(*) FROM public.services;'
```

Both queries should return a count. A count of `0` is fine—it simply means that table is empty. If authentication fails, check `.pgpass` and whether PostgreSQL listens on `127.0.0.1:5432`.

### 7. Configure and launch `llama-server`

Edit the paths in `start-server.sh` to match your system, especially:

- The `llama-server` executable built with Vulkan.
- The local `.gguf` model file.
- The Python MCP server, virtual environment, and MCP JSON configuration.

The launcher should export the database connection setting before it starts `llama-server`:

```bash
export MSFDB_DSN='host=127.0.0.1 port=5432 dbname=msf user=msf_ai'
```

That `export` lasts for the script's process and its children; it does **not** need to persist across reboots because it is set again at each launch.

Run your launcher:

```bash
chmod +x ./start-server.sh
./start-server.sh
```

Open **http://127.0.0.1:8080** (assuming the launcher uses port 8080). The MCP configuration should let `llama-server` start the Python bridge as a subprocess—no separate MCP daemon is necessary.

To check the registered tools:

```bash
curl -s http://127.0.0.1:8080/tools | python3 -m json.tool
```

You should see whichever tools your Python MCP server implements (for example, host and service lookups). Tool names depend on the MCP server configuration.

*Personal learning project. Expect rough edges and verify AI-generated conclusions against the actual tool output.*

yes, this documentation was also written by ai and proof read by me. dont @ me
