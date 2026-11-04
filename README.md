# llama to msfdb

Personal project to allow local AI access to Metaploit AI.

Partially vibe coded.


First started out with setting up ollama and llama.cpp until I was able to run llama-server.
(including all the graphics driver fuckery; ended up with a vulkan build)


Also disabled cloud functionality:
sudo systemctl edit ollama

add:
[Service]
Environment="OLLAMA_NO_CLOUD=1"
Environment="OLLAMA_HOST=127.0.0.1:11434"

then
sudo systemctl daemon-reload
sudo systemctl restart ollama


Currently using:
unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf


My llama.cpp is currently sitting inside llama-to-msfdb, but that's not really necassary.



# Setting up llama to msfdb

Step 1 — Check MCP support
./build-vulkan/bin/llama-server --help | grep -i mcp
Look for:
--mcp-servers-config


Step 2 — Create a Python MCP server
python3 -m venv .venv

.venv/bin/pip install \
  "mcp>=1.28,<2" \
  "psycopg[binary]"


Step 3 — Configure read-only database access

Initialize msfdb

sudo msfdb init
sudo msfdb start

sudo msfconsole

msf > db_status
[*] Connected to msf. Connection type: postgresql.

In terminal:
sudo -u postgres psql
psql (17.x)
Type "help" for help.

postgres=#

Next, list the available databases. Look for a database named msf.
\l


Create the AI database user

CREATE ROLE msf_ai LOGIN;

\password msf_ai

GRANT CONNECT ON DATABASE msf TO msf_ai;

\connect msf

Your prompt should change to:
msf=#

Give the AI read-only permissions

GRANT USAGE ON SCHEMA public TO msf_ai;

GRANT SELECT ON
    public.workspaces,
    public.hosts,
    public.services
TO msf_ai;

ALTER ROLE msf_ai
SET default_transaction_read_only = on;

Now exit PostgreSQL:
\q

In your Kali terminal, create a PostgreSQL password file:
touch ~/.pgpass
chmod 600 ~/.pgpass
nano ~/.pgpass

127.0.0.1:5432:msf:msf_ai:YOUR_PASSWORD

Test the connection
psql -h 127.0.0.1 \
  -p 5432 \
  -U msf_ai \
  -d msf \
  -c "SELECT COUNT(*) FROM hosts;"
  
psql -h 127.0.0.1 \
  -p 5432 \
  -U msf_ai \
  -d msf \
  -c "SELECT COUNT(*) FROM services;"
  

Then just edit the paths in start-server.sh and run the script.
