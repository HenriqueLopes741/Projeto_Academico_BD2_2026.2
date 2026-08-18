# scripts/

Ferramental de teste e automação — não é código avaliado como artefato, é apoio.

Exemplos do que entra aqui:

- Scripts de verificação/conformidade que comparam o esquema criado no banco contra o modelo lógico (nomes de tabela, coluna, tipo).
- Geradores de dado sintético auxiliares à carga de `sql/04_carga.sql`.
- Wrappers `docker compose exec` + `psql` para rodar os scripts SQL em sequência.

Convenção: bash com `set -euo pipefail`, espera de serviço via healthcheck real (nunca `sleep` fixo), saída em português.
