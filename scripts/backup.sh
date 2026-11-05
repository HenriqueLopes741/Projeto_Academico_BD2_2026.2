#!/usr/bin/env bash
# Backup lógico da base `matricula` (formato custom) + roles do cluster + impressão digital.
# Uso: ./scripts/backup.sh          Saída: backups/matricula_<data>.{dump,fingerprint}, backups/globais_<data>.sql
# Fora do Docker: RUN="" PGHOST=localhost PGPASSWORD=bd2 ./scripts/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
RUN="${RUN-docker compose exec -T postgres}"
mkdir -p backups
TS="$(date +%Y%m%d_%H%M%S)"
DUMP="backups/matricula_${TS}.dump"

echo "[1/3] pg_dump -Fc (snapshot consistente, sem parar o banco)"
$RUN pg_dump -U bd2 -d matricula -Fc > "$DUMP"
echo "[2/3] pg_dumpall --globals-only (roles; contém hash de senha, não versionar)"
$RUN pg_dumpall -U bd2 --globals-only > "backups/globais_${TS}.sql"
echo "[3/3] impressão digital da base original"
$RUN psql -U bd2 -d matricula -X -At < sql/08_backup_restore.sql > "backups/matricula_${TS}.fingerprint"

echo "OK: $DUMP ($(du -h "$DUMP" | cut -f1)), sha256 $(sha256sum "$DUMP" | cut -c1-16)…"
echo "Restaurar: ./scripts/restore.sh $DUMP [--desastre]"
