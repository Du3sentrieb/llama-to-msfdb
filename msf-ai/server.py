
import os

import psycopg
from psycopg.rows import dict_row
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("msfdb-readonly")


def query_db(sql, params):
    """Execute one predefined read-only query."""
    with psycopg.connect(
        os.environ["MSFDB_DSN"],
        row_factory=dict_row,
        options=(
            "-c default_transaction_read_only=on "
            "-c statement_timeout=5000"
        ),
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.fetchall()


@mcp.tool()
def msf_hosts(workspace: str, limit: int = 100) -> list[dict]:
    """List discovered hosts in a Metasploit workspace."""
    limit = max(1, min(limit, 200))

    return query_db(
        """
        SELECT
            h.address::text AS ip,
            h.name,
            h.os_name
        FROM hosts h
        JOIN workspaces w ON w.id = h.workspace_id
        WHERE w.name = %s
        ORDER BY h.address
        LIMIT %s
        """,
        (workspace, limit),
    )


@mcp.tool()
def msf_services(workspace: str, limit: int = 100) -> list[dict]:
    """List network services in a Metasploit workspace."""
    limit = max(1, min(limit, 200))

    return query_db(
        """
        SELECT
            h.address::text AS ip,
            s.port,
            s.proto,
            s.name,
            s.state,
            s.info
        FROM services s
        JOIN hosts h ON h.id = s.host_id
        JOIN workspaces w ON w.id = h.workspace_id
        WHERE w.name = %s
        ORDER BY h.address, s.port
        LIMIT %s
        """,
        (workspace, limit),
    )


if __name__ == "__main__":
    mcp.run(transport="stdio")
