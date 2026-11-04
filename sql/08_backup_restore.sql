-- =====================================================================
-- 08_backup_restore.sql
-- Procedimento de backup e restauração, documentado e reproduzível
-- Frente: Administração e Operação
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================
-- Demonstrável ao vivo (Seção 6 do enunciado). Ferramentas: pg_dump,
-- pg_restore e pg_dumpall, que já vêm na imagem postgres:17. Tudo é
-- automatizado em scripts/backup.sh e scripts/restore.sh; este arquivo explica
-- o PORQUÊ e traz a conferência SQL que prova que a restauração ficou idêntica.
--
-- ESCOLHAS
--   * Backup LÓGICO em formato custom (pg_dump -Fc): comprimido, restaura
--     seletivamente e em paralelo (pg_restore -j), e é consistente (um único
--     snapshot, sem parar o banco, graças ao MVCC). Alternativa física
--     (pg_basebackup + WAL/PITR) permite recuperar a um instante, mas exige
--     arquivamento de WAL; para este porte, o lógico basta e é portátil entre
--     versões. Limite honesto: só restaura até o momento do dump (RPO = idade
--     do último backup).
--   * Roles NÃO entram no dump da base: pg_dump leva os GRANT e as policies do
--     RLS, mas não cria as roles (são do cluster). Sem elas, a restauração
--     falha nos GRANT/POLICY. Por isso o backup também faz
--     pg_dumpall --globals-only (contém hash de senhas: arquivo sensível, fora
--     do Git, via .gitignore).
--
-- PROCEDIMENTO (do zero)
--   0. Ambiente no ar e scripts 01–07 executados.
--   1. Backup:        ./scripts/backup.sh
--        gera backups/matricula_<data>.dump, backups/globais_<data>.sql e
--        backups/matricula_<data>.fingerprint (resultado da consulta abaixo).
--   2. Restauração SEGURA (não toca na base original): em base nova
--        ./scripts/restore.sh backups/matricula_<data>.dump
--        cria matricula_restaurada e compara a "impressão digital" com a original.
--   3. Restauração de DESASTRE (ao vivo):
--        a) estrago:  DELETE FROM tb_matricula;   (histórico some em cascata)
--        b) ./scripts/restore.sh backups/matricula_<data>.dump --desastre
--           derruba a base `matricula` e restaura sobre ela; confere as contagens.
--   4. Recomeçar do zero em outro ambiente: docker compose up -d; depois
--        ./scripts/restore.sh <dump> --desastre   (restaura roles + base).
--
-- VERIFICAÇÃO: a consulta abaixo devolve contagem e md5 do conteúdo de cada
-- tabela, mais sequences, índices, políticas RLS e views. Rode na base original
-- e na restaurada: as linhas têm de ser idênticas. É esta consulta que os
-- scripts executam (psql -At < sql/08_backup_restore.sql) — mantenha-a como o
-- ÚNICO comando executável deste arquivo.
--   Detalhe: `sequences` comparadas garantem que o próximo id gerado após a
--   restauração não colide com os existentes.
--   `matviews_populadas`: a materialized view volta com dados (pg_restore
--   refaz o REFRESH ao final).

SELECT 'tb_campus' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_campus x UNION ALL
SELECT 'tb_disciplina' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_disciplina x UNION ALL
SELECT 'tb_periodo_letivo' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_periodo_letivo x UNION ALL
SELECT 'tb_professor' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_professor x UNION ALL
SELECT 'tb_curso' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_curso x UNION ALL
SELECT 'tb_sala' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_sala x UNION ALL
SELECT 'tb_feriado' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_feriado x UNION ALL
SELECT 'tb_turma' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_turma x UNION ALL
SELECT 'tb_curriculo' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_curriculo x UNION ALL
SELECT 'tb_turma_horario' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_turma_horario x UNION ALL
SELECT 'tb_aluno' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_aluno x UNION ALL
SELECT 'tb_curriculo_disciplina' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_curriculo_disciplina x UNION ALL
SELECT 'tb_matricula' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_matricula x UNION ALL
SELECT 'tb_pre_requisito' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_pre_requisito x UNION ALL
SELECT 'tb_historico' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_historico x UNION ALL
SELECT 'tb_log_matricula' AS item, count(*)::text AS qtde, md5(coalesce(string_agg(x::text, '|' ORDER BY x::text), '')) AS md5 FROM tb_log_matricula x UNION ALL
SELECT 'sequences', count(*)::text, md5(string_agg(sequencename || '=' || coalesce(last_value::text, 'null'), '|' ORDER BY sequencename)) FROM pg_sequences WHERE schemaname = 'public' UNION ALL
SELECT 'indices', count(*)::text, md5(string_agg(indexdef, '|' ORDER BY indexname)) FROM pg_indexes WHERE schemaname = 'public' UNION ALL
SELECT 'politicas_rls', count(*)::text, md5(coalesce(string_agg(tablename || policyname || coalesce(qual, ''), '|' ORDER BY tablename, policyname), '')) FROM pg_policies WHERE schemaname = 'public' UNION ALL
SELECT 'views', count(*)::text, md5(string_agg(viewname, '|' ORDER BY viewname)) FROM pg_views WHERE schemaname = 'public' UNION ALL
SELECT 'matviews_populadas', count(*)::text, md5(string_agg(matviewname, '|' ORDER BY matviewname)) FROM pg_matviews WHERE schemaname = 'public' AND ispopulated
ORDER BY 1;
