
#!/usr/bin/env bash
set -euo pipefail

LLAMA="$HOME/llama-to-msfdb/llama.cpp//build-vulkan/bin/llama-server"
MODEL="$HOME/llama-to-msfdb/llama.cpp//unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf"
MCP_DIR="$HOME/llama-to-msfdb/msf-ai"

# 1. Configure PostgreSQL connection
export MSFDB_DSN="host=127.0.0.1 port=5432 dbname=msf user=msf_ai"

# 2. Start Metasploit's database if necessary
if ! pg_isready -h 127.0.0.1 -p 5432 -q; then
    echo "[*] Starting Metasploit database..."
    sudo msfdb start
fi

# 3. Verify read-only database access
echo "[*] Checking database connection..."
if ! psql -w -X -d "$MSFDB_DSN" \
    -Atqc "SELECT COUNT(*) FROM public.hosts" >/dev/null; then
    echo "[!] Database connection failed. Check ~/.pgpass."
    exit 1
fi

# 4. Verify required files
for file in "$LLAMA" "$MODEL" \
    "$MCP_DIR/server.py" "$MCP_DIR/.venv/bin/python"; do
    if [[ ! -f "$file" ]]; then
        echo "[!] Missing: $file"
        exit 1
    fi
done

# 5. Generate MCP configuration
cat > "$MCP_DIR/mcp.json" <<EOF
{
  "mcpServers": {
    "msfdb": {
      "command": "$MCP_DIR/.venv/bin/python",
      "args": ["$MCP_DIR/server.py"]
    }
  }
}
EOF

# 6. Launch local AI server
echo "[*] Starting Qwen with Metasploit MCP..."

exec "$LLAMA" \
    -m "$MODEL" \
    -c 16384 \
    -ngl 99 \
    --jinja \
    --host 127.0.0.1 \
    --port 8080 \
    --mcp-servers-config "$MCP_DIR/mcp.json"
