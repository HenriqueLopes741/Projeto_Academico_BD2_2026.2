#!/usr/bin/env bash
# Restaura um backup gerado por scripts/backup.sh e CONFERE contra a impressão digital.
#   ./scripts/restore.sh backups/matricula_X.dump             → base nova `matricula_restaurada` (segura)
#   ./scripts/restore.sh backups/matricula_X.dump --desastre  → derruba e recria `matricula` (substitui a original)
# Fora do Docker: RUN="" PGHOST=localhost PGPASSWORD=bd2 ./scripts/restore.sh ...
set -euo pipefail
cd "$(dirname "$0")/.."
RUN="${RUN-docker compose exec -T postgres}"
DUMP="${1:?uso: $0 backups/matricula_<data>.dump [--desastre]}"
MODO="${2:-seguro}"
[ -f "$DUMP" ] || { echo "arquivo não encontrado: $DUMP" >&2; exit 1; }
FP="${DUMP%.dump}.fingerprint"
# matricula_<data>_<hora>.dump  →  globais_<data>_<hora>.sql (mesmo carimbo)
GLOBAIS="$(dirname "$DUMP")/globais_$(basename "$DUMP" .dump | sed 's/^matricula_//').sql"

if [ "$MODO" = "--desastre" ]; then DESTINO="matricula"; else DESTINO="matricula_restaurada"; fi
adm() { $RUN psql -U bd2 -d postgres -X -q -v ON_ERROR_STOP=1 "$@"; }

echo "[1/4] roles (já existentes geram aviso e são ignoradas)"
if [ -f "$GLOBAIS" ]; then
  $RUN psql -U bd2 -d postgres -X -q < "$GLOBAIS" 2>&1 | grep -v -E 'already exists|^$' || true
else
  echo "  aviso: $GLOBAIS não encontrado; sem as roles, GRANT/POLICY falham na restauração"
fi

echo "[2/4] recriando a base $DESTINO"
adm -c "DROP DATABASE IF EXISTS $DESTINO WITH (FORCE)"   # FORCE (PG13+): encerra conexões abertas
adm -c "CREATE DATABASE $DESTINO OWNER bd2"

echo "[3/4] pg_restore em $DESTINO"
$RUN pg_restore -U bd2 -d "$DESTINO" --exit-on-error --no-owner --role=bd2 < "$DUMP"

echo "[4/4] conferência (restaurada x original no momento do backup)"
$RUN psql -U bd2 -d "$DESTINO" -X -At < sql/08_backup_restore.sql > /tmp/fp_restaurada.$$
if diff -u "$FP" /tmp/fp_restaurada.$$ >/dev/null; then
  echo "  >>> OK: $(wc -l < "$FP") itens idênticos (contagens, md5 do conteúdo, sequences, índices, RLS, views)"
else
  echo "  >>> DIFERENÇA encontrada:"; diff -u "$FP" /tmp/fp_restaurada.$$ || true; rm -f /tmp/fp_restaurada.$$; exit 1
fi
rm -f /tmp/fp_restaurada.$$
