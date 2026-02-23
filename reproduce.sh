#!/usr/bin/env bash
# ============================================================================
# Greenmask Issue #396 — Reproduction script
# https://github.com/GreenmaskIO/greenmask/issues/396
#
# Demonstrates that polymorphic virtual_references with multiple types on
# the same FK column drop one type's rows during subset.
#
# Requirements: docker, greenmask (v0.2.x), psql, pg_dump, pg_restore
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PG_PORT=15432
PGPASSWORD=postgres
export PGPASSWORD

# --- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BOLD}==>${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
fail()  { echo -e "${RED}✗${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }

# --- Detect pg_bin_path ----------------------------------------------------
detect_pg_bin() {
    local candidates=(
        "/opt/homebrew/opt/postgresql@17/bin"
        "/opt/homebrew/opt/postgresql@16/bin"
        "/usr/lib/postgresql/17/bin"
        "/usr/lib/postgresql/16/bin"
        "/usr/bin"
    )
    for dir in "${candidates[@]}"; do
        if [[ -x "$dir/pg_dump" ]]; then
            echo "$dir"
            return
        fi
    done
    # Fallback: use whatever is in PATH
    dirname "$(command -v pg_dump 2>/dev/null || echo "/usr/bin/pg_dump")"
}

PG_BIN_PATH="$(detect_pg_bin)"
info "Using pg tools from: $PG_BIN_PATH"

# --- Check greenmask -------------------------------------------------------
if ! command -v greenmask &>/dev/null; then
    echo "ERROR: greenmask not found in PATH."
    echo "Install: https://github.com/GreenmaskIO/greenmask/releases"
    exit 1
fi
info "greenmask version: $(greenmask --version 2>&1 | head -1)"

# --- Prepare config with correct pg_bin_path -------------------------------
CONFIG="$SCRIPT_DIR/config.yml"
sed -i.bak "s|PG_BIN_PATH_PLACEHOLDER|$PG_BIN_PATH|" "$CONFIG"
trap 'mv "$CONFIG.bak" "$CONFIG" 2>/dev/null; docker compose -f "$SCRIPT_DIR/docker-compose.yml" down -v 2>/dev/null' EXIT

# --- Start PostgreSQL ------------------------------------------------------
info "Starting PostgreSQL on port $PG_PORT..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --wait

PSQL="psql -h localhost -p $PG_PORT -U postgres -q --no-psqlrc"

# Wait for postgres to accept connections
for i in $(seq 1 30); do
    if $PSQL -c "SELECT 1" &>/dev/null; then break; fi
    sleep 0.5
done

# --- Create databases ------------------------------------------------------
info "Creating databases..."
$PSQL -c "DROP DATABASE IF EXISTS gm396_source;"
$PSQL -c "DROP DATABASE IF EXISTS gm396_target;"
$PSQL -c "CREATE DATABASE gm396_source;"
$PSQL -c "CREATE DATABASE gm396_target;"

# --- Load schema + data into source ----------------------------------------
info "Loading schema and test data..."
$PSQL -d gm396_source -f "$SCRIPT_DIR/setup.sql"

# --- Show source data ------------------------------------------------------
echo ""
info "SOURCE DATABASE (before greenmask):"
echo ""
echo "accounts (2 rows — subset to id=1):"
$PSQL -d gm396_source -c "SELECT * FROM accounts ORDER BY id;"
echo ""
echo "controls (3 rows — 2 in account 1, 1 in account 2):"
$PSQL -d gm396_source -c "SELECT c.id, c.audit_id, c.name, a.id as account_id FROM controls c JOIN audits au ON c.audit_id=au.id JOIN projects p ON au.project_id=p.id JOIN accounts a ON p.account_id=a.id ORDER BY c.id;"
echo ""
echo "confirmation_items (3 rows — 2 in account 1, 1 in account 2):"
$PSQL -d gm396_source -c "SELECT ci.id, ci.confirmation_id, ci.name, a.id as account_id FROM confirmation_items ci JOIN confirmations co ON ci.confirmation_id=co.id JOIN projects p ON co.project_id=p.id JOIN accounts a ON p.account_id=a.id ORDER BY ci.id;"
echo ""
echo "comments (6 rows — polymorphic to controls/confirmation_items):"
$PSQL -d gm396_source -c "SELECT * FROM comments ORDER BY id;"

# --- Clean dump directory --------------------------------------------------
rm -rf /tmp/greenmask_396_dumps /tmp/greenmask_396
mkdir -p /tmp/greenmask_396_dumps /tmp/greenmask_396

# --- Run greenmask dump ----------------------------------------------------
echo ""
info "Running greenmask dump..."
greenmask dump --config "$CONFIG" 2>&1 | tail -5

# --- Run greenmask restore -------------------------------------------------
info "Running greenmask restore..."
greenmask restore --config "$CONFIG" latest 2>&1 | tail -5

# --- Show target data ------------------------------------------------------
echo ""
info "TARGET DATABASE (after greenmask dump+restore):"
echo ""

ACCOUNTS_COUNT=$($PSQL -d gm396_target -tAc "SELECT count(*) FROM accounts;")
PROJECTS_COUNT=$($PSQL -d gm396_target -tAc "SELECT count(*) FROM projects;")
CONTROLS_COUNT=$($PSQL -d gm396_target -tAc "SELECT count(*) FROM controls;")
CONF_ITEMS_COUNT=$($PSQL -d gm396_target -tAc "SELECT count(*) FROM confirmation_items;")
COMMENTS_COUNT=$($PSQL -d gm396_target -tAc "SELECT count(*) FROM comments;")

echo "accounts ($ACCOUNTS_COUNT rows):"
$PSQL -d gm396_target -c "SELECT * FROM accounts ORDER BY id;"
echo ""
echo "controls ($CONTROLS_COUNT rows):"
$PSQL -d gm396_target -c "SELECT * FROM controls ORDER BY id;"
echo ""
echo "confirmation_items ($CONF_ITEMS_COUNT rows):"
$PSQL -d gm396_target -c "SELECT * FROM confirmation_items ORDER BY id;"
echo ""
echo "comments ($COMMENTS_COUNT rows):"
$PSQL -d gm396_target -c "SELECT * FROM comments ORDER BY id;"

# --- Verify ----------------------------------------------------------------
echo ""
echo "============================================"
echo "  RESULTS"
echo "============================================"
echo ""

printf "  %-22s  %-10s  %-10s\n" "Table" "Expected" "Actual"
printf "  %-22s  %-10s  %-10s\n" "-------" "--------" "------"
printf "  %-22s  %-10s  %-10s\n" "accounts" "1" "$ACCOUNTS_COUNT"
printf "  %-22s  %-10s  %-10s\n" "projects" "1" "$PROJECTS_COUNT"
printf "  %-22s  %-10s  %-10s\n" "controls" "2" "$CONTROLS_COUNT"
printf "  %-22s  %-10s  %-10s\n" "confirmation_items" "2" "$CONF_ITEMS_COUNT"
printf "  %-22s  %-10s  %-10s\n" "comments" "4" "$COMMENTS_COUNT"
echo ""

if [[ "$COMMENTS_COUNT" -eq 4 ]]; then
    ok "Comments count is correct (4). Bug may be fixed!"
elif [[ "$COMMENTS_COUNT" -eq 0 ]]; then
    fail "Comments count is 0 — all polymorphic rows dropped."
    echo ""
    echo "  Both polymorphic guards fail: a 'Control' comment fails the"
    echo "  'ConfirmationItem' guard and vice versa."
elif [[ "$COMMENTS_COUNT" -lt 4 ]]; then
    fail "Comments count is $COMMENTS_COUNT instead of 4 — confirms bug #396."
    echo ""
    # Show which types survived
    echo "  Surviving comment types:"
    $PSQL -d gm396_target -c "SELECT commentable_type, count(*) FROM comments GROUP BY commentable_type ORDER BY commentable_type;"
    echo ""
    echo "  Only one polymorphic type survives. The other type's comments"
    echo "  are dropped because the scope predicates are AND-combined"
    echo "  without OR NOT bypass guards."
else
    warn "Unexpected comments count: $COMMENTS_COUNT (expected 4)"
fi

echo ""
