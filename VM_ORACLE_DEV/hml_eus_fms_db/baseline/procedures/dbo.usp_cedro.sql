CREATE PROCEDURE [dbo].[usp_cedro]
AS
BEGIN
-- =============================================
-- Author:      Breno
-- Create Date: 2025-01-28
-- =============================================

	return --> adicionado em 2026-02-04
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON

    -- verificaÃ§Ã£o 1: negÃ³cios duplicados
	-- verificar se existe mais de 1 linha na tabela tb_trade com o mesmo valor para process_date, symbol e trade_id
	-- possÃ­vel tratamento: desconsiderar eventos duplicados

	--insert into tb_trade_duplicados
	--select * from tb_trade t1 where exists (select 1 from tb_trade t2 where t1.symbol = t2.symbol and t1.trade_id = t2.trade_id and t1.msg_time <> t2.msg_time)
	--select symbol , trade_id , count(1) From tb_trade group by symbol , trade_id having count(1) > 1
	--select * from tb_trade_duplicados

	-- verificaÃ§Ã£o 2: negÃ³cios ausentes
	-- verificar se houve negÃ³cios presentes na tb_entrypoint, mas ausentes na tb_trade
	-- possÃ­vel tratamento: adicionar eventos da tb_entrypoint Ã  tb_trade

	--insert into tb_entrypoint_ausentes
	--select e.* from tb_entrypoint e where not exists (select 1 from tb_trade t where e.trade_id = t.trade_id and e.symbol = t.symbol) and e.trade_id is not null
	--select * from tb_entrypoint_ausentes

	-- verificaÃ§Ã£o 3: cotaÃ§Ãµes diferentes
	-- verificar se existe divergÃªncia entre as colunas da tb_quote com as colunas da st_ativo_bovespa
	-- possÃ­vel tratamento: utilizar os dados da B3 em vez dos da Cedro

	--insert into tb_quote_divergentes
	--select q.symbol, q.symbol_timestamp, q.trade_count, b.TOTNEG, q.financial_volume, b.VOLTOT from tb_quote q left join st_ativo_bovespa_fms b
	--on q.symbol = b.CODNEG and q.symbol_timestamp = cast(b.dt_periodo as date) and q.trade_count <> b.TOTNEG and q.financial_volume <> b.VOLTOT
	--where TOTNEG is not null
	--select * from tb_quote_divergentes

	-- requisitos: tb_trade, tb_entrypoint, tb_quote, st_ativo_bovespa

END