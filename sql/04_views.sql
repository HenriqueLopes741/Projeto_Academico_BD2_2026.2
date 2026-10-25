-- =====================================================================
-- 04_views.sql
-- 3 views (oferta, vagas, histórico) + 1 materialized view de indicadores
-- Frente: Administração e Operação
-- Banco de Dados II (CCO072) — IESB 2026/2
-- =====================================================================

-- vw_vagas: uma linha por turma, com ano e semestre para filtrar,
-- vagas ocupadas e vagas livres.
-- Ocupam vaga as matrículas 'ativa' e 'concluida'; 'trancada' e 'cancelada'
-- liberam. 'concluida' é necessária porque nas turmas de semestres passados
-- não há mais matrículas ativas; em 2026/2 ela não altera o resultado.
CREATE VIEW vw_vagas AS
SELECT pl.ano_periodo_letivo 					AS ano,
		pl.semestre_periodo_letivo  			AS semestre,
		t.codigo_turma,
		t.vagas_turma,
		COUNT (m.id_matricula)					AS ocupadas,
		t.vagas_turma - COUNT(m.id_matricula) 	AS vagas_livres
FROM tb_turma t
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
LEFT JOIN tb_matricula m
	ON m.id_turma = t.id_turma
	AND m.status_matricula IN	('ativa', 'concluida')
GROUP BY t.id_turma, pl.id_periodo_letivo;

