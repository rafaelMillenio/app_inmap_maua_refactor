--
-- PostgreSQL database dump
--

-- Dumped from database version 11.10 (Debian 11.10-1.pgdg90+1)
-- Dumped by pg_dump version 16.0

-- Started on 2026-07-24 16:07:52 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 17 (class 2615 OID 899765)
-- Name: app; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app;


--
-- TOC entry 2127 (class 1247 OID 902165)
-- Name: boxplot_values; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.boxplot_values AS (
	min numeric,
	q1 numeric,
	median numeric,
	q3 numeric,
	max numeric
);


--
-- TOC entry 2130 (class 1247 OID 902168)
-- Name: timestamp_boxplot_values; Type: TYPE; Schema: app; Owner: -
--

CREATE TYPE app.timestamp_boxplot_values AS (
	min timestamp without time zone,
	q1 numeric,
	median numeric,
	q3 numeric,
	max timestamp without time zone
);


--
-- TOC entry 1664 (class 1255 OID 902178)
-- Name: _final_boxplot(double precision[]); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app._final_boxplot(a double precision[]) RETURNS app.boxplot_values
    LANGUAGE plpythonu IMMUTABLE
    AS $$

    a.sort()
    i = len(a)
    if a[0] is None:
        a[0] = 0
    return ( a[0], a[i/4], a[i/2], a[i*3/4], a[-1] )

$$;


--
-- TOC entry 1666 (class 1255 OID 902179)
-- Name: _final_boxplot(numeric[]); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app._final_boxplot(a numeric[]) RETURNS app.boxplot_values
    LANGUAGE plpythonu IMMUTABLE
    AS $$
    a.sort()
    i = len(a)
    return ( a[0], a[i/4], a[i/2], a[i*3/4], a[-1] )
$$;


--
-- TOC entry 1665 (class 1255 OID 902180)
-- Name: _final_boxplot(timestamp without time zone[]); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app._final_boxplot(a timestamp without time zone[]) RETURNS app.timestamp_boxplot_values
    LANGUAGE plpythonu IMMUTABLE
    AS $$
    return (min(a), 0, 0, 0, max(a))
$$;


--
-- TOC entry 1679 (class 1255 OID 902181)
-- Name: command(text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.command(ccommand text) RETURNS json
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public', 'topology'
    AS $$
DECLARE
    jResult json;
BEGIN
    /* *************************************************************************************
	need to add after ajust into postgrest 5.0.0v, the transaction is read-only;
	links:
		https://github.com/PostgREST/postgrest/issues/1086
		https://www.postgresql.org/docs/10/static/sql-set-transaction.html
		https://www.postgresql.org/docs/10/static/runtime-config-client.html#GUC-DEFAULT-TRANSACTION-ISOLATION
	obs:
		optimize check if has some ddl (like create, or drop stuff) so then set this mode.
    ************************************************************************************* */
    --set transaction read write;
    --set default_transaction_read_only = off;
    --set default_transaction_isolation = "read committed";
    EXECUTE "ccommand" into jResult;
    RETURN jResult;


    /*EXCEPTION WHEN OTHERS THEN
    BEGIN
	  --SET TRANSACTION ISOLATION LEVEL READ COMMITTED READ WRITE;
	  --BEGIN TRANSACTION;
	    set transaction read write;
	    EXECUTE "ccommand" into jResult;
	    RETURN jResult;
	  --raise notice 'The transaction is in an uncommittable state. Transaction was rolled back';
	  --raise notice '% %', SQLERRM, SQLSTATE;
    END;*/


END;
$$;


--
-- TOC entry 1680 (class 1255 OID 902182)
-- Name: dd2dms(double precision, character varying, character varying, character varying); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.dd2dms(p_ddecdeg double precision, p_sdegreesymbol character varying, p_sminutesymbol character varying, p_ssecondsymbol character varying) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
       v_iDeg INT;
       v_iMin INT;
       v_dSec FLOAT;
    BEGIN
       v_iDeg := Trunc(p_dDecDeg)::INT;
       v_iMin := Trunc(   (Abs(p_dDecDeg) - Abs(v_iDeg)) * 60)::INT;
       v_dSec := Round(((((Abs(p_dDecDeg) - Abs(v_iDeg)) * 60) - v_iMin) * 60)::NUMERIC, 0)::FLOAT;
       RETURN TRIM(to_char(v_iDeg,'9999')) || p_sDegreeSymbol::text || TRIM(to_char(v_iMin,'99')) || p_sMinuteSymbol::text ||
              CASE WHEN v_dSec = 0::FLOAT THEN '0' ELSE REPLACE(TRIM(to_char(v_dSec,'99.999')),'.000','') END || p_sSecondSymbol::text;
    END;
$$;


--
-- TOC entry 1681 (class 1255 OID 902183)
-- Name: dms2dd(double precision, double precision, double precision); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.dms2dd(p_ddeg double precision, p_dmin double precision, p_dsec double precision) RETURNS double precision
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
    DECLARE
       v_dDD FLOAT;
    BEGIN
       v_dDD := ABS(p_dDeg) + p_dMin / 60::FLOAT + p_dSec / 3600::FLOAT;
       RETURN SIGN(p_dDeg) * v_dDD;
    END;
    $$;


--
-- TOC entry 1682 (class 1255 OID 902184)
-- Name: fn_calculateboxplot(text, text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_calculateboxplot(schemaname text, tablename text, columnname text) RETURNS json
    LANGUAGE plpgsql
    AS $_$
DECLARE boxplotvalues boxplot_values; boxplotvalues2 timestamp_boxplot_values;
    DECLARE stmt text; stmt2 text; response json;
    DECLARE curs1 refcursor; rec record;
	BEGIN
    	IF (coalesce(schemaname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Schema name cannot be null or empty',
            HINT = 'Send a schema name';
        END IF;
        IF (coalesce(tablename, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Table name cannot be null or empty',
            HINT = 'Send a table name';
        END IF;
        IF (coalesce(columnname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Colum nname cannot be null or empty',
            HINT = 'Send a column name';
        END IF;
        stmt = format('WITH test(x) AS (SELECT %1$I::TEXT FROM %2$I.%3$I WHERE %1$I IS NOT NULL LIMIT 1)
				SELECT x, "public".isnumeric(x), "public".isdate(x),(NOT "public".isnumeric(x) and NOT "public".isdate(x)) as istext FROM test;',columnname,schemaname,tablename);
        stmt2 = format('SELECT ("%2$I".boxplot(%1$I)).* FROM %2$I.%3$I', columnname,  schemaname, tablename);
        OPEN curs1 FOR EXECUTE stmt;
        FETCH NEXT FROM curs1 INTO rec;
            WHILE FOUND
                LOOP
                	IF (rec.isnumeric = true) THEN
                    	EXECUTE stmt2 INTO boxplotvalues;
                        response = json_build_object('min',boxplotvalues.min,'q1',boxplotvalues.q1,'median',boxplotvalues.median,'q3',boxplotvalues.q3,'max',boxplotvalues.max);
                    ELSIF (rec.isdate = true) THEN
                    	EXECUTE stmt2 INTO boxplotvalues2;
                        response = json_build_object('min',boxplotvalues2.min,'q1',boxplotvalues2.q1,'median',boxplotvalues2.median,'q3',boxplotvalues2.q3,'max',boxplotvalues2.max);
                    ELSE
                    	response = json_build_object('min',0,'q1',0,'median',0,'q3',0,'max',0);
                    END IF;
                    FETCH NEXT FROM curs1 INTO rec;
                END LOOP;
        CLOSE curs1;
        RETURN response;
    END;
$_$;


--
-- TOC entry 1683 (class 1255 OID 902185)
-- Name: fn_calculateboxplot(text, text, text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_calculateboxplot(schemaname text, tablename text, columnname text, conditions text DEFAULT NULL::text) RETURNS json
    LANGUAGE plpgsql
    AS $_$
DECLARE boxplotvalues boxplot_values; boxplotvalues2 timestamp_boxplot_values;
    DECLARE stmt text; stmt2 text; response json; _conditions text := '';
    DECLARE curs1 refcursor; rec record;
	BEGIN
    	IF (coalesce(schemaname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Schema name cannot be null or empty',
            HINT = 'Send a schema name';
        END IF;
        IF (coalesce(tablename, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Table name cannot be null or empty',
            HINT = 'Send a table name';
        END IF;
        IF (coalesce(columnname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Colum nname cannot be null or empty',
            HINT = 'Send a column name';
        END IF;
		IF (coalesce(conditions, '') != '') THEN
        	_conditions := format('WHERE %1$s', conditions);
        END IF;
        stmt = format('WITH test(x) AS (SELECT %1$I::TEXT FROM "%2$I"."%3$I" WHERE %1$I IS NOT NULL LIMIT 1)
				SELECT x, "public".isnumeric(x), "public".isdate(x),(NOT "public".isnumeric(x) and NOT "public".isdate(x)) as istext FROM test;',columnname,schemaname,tablename);
        stmt2 = format('SELECT ("%2$I".boxplot(%1$I)).* FROM "%2$I"."%3$I" %4$s', columnname,  schemaname, tablename, _conditions);
        OPEN curs1 FOR EXECUTE stmt;
        FETCH NEXT FROM curs1 INTO rec;
            WHILE FOUND
                LOOP
                	IF (rec.isnumeric = true) THEN
                    	EXECUTE stmt2 INTO boxplotvalues;
                        response = json_build_object('min',boxplotvalues.min,'q1',boxplotvalues.q1,'median',boxplotvalues.median,'q3',boxplotvalues.q3,'max',boxplotvalues.max);
                    ELSIF (rec.isdate = true) THEN
                    	EXECUTE stmt2 INTO boxplotvalues2;
                        response = json_build_object('min',boxplotvalues2.min,'q1',boxplotvalues2.q1,'median',boxplotvalues2.median,'q3',boxplotvalues2.q3,'max',boxplotvalues2.max);
                    ELSE
                    	response = json_build_object('min',0,'q1',0,'median',0,'q3',0,'max',0);
                    END IF;
                    FETCH NEXT FROM curs1 INTO rec;
                END LOOP;
        CLOSE curs1;
        RETURN response;
    END;
$_$;


--
-- TOC entry 1684 (class 1255 OID 902186)
-- Name: fn_findcoveredby(text, text, bigint, text[]); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_findcoveredby(basetable text, basetablekey text, basetablevalue bigint, coveredtables text[]) RETURNS json
    LANGUAGE plpgsql
    AS $_$
    DECLARE stmt text;
    DECLARE recordcount int;
    DECLARE at_json json;
    DECLARE tb_json json;
    DECLARE pk_json json;
	BEGIN
    	IF (coalesce(basetable, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Base table cannot be null or empty',
            HINT = 'Send a base table name';
        END IF;
        IF (coalesce(basetablekey, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Base table Key cannot be null or empty',
            HINT = 'Send a valid base table key';
        END IF;
        IF (basetablevalue <= 0) THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'basetablevalue cannot be less than or equal zero',
            HINT = 'Send a valid basetablevalue';
        END IF;
		
	/*IF (coalesce(array_length(coveredtables, 1),0) <= 0) THEN
            RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Collection cannot be empty',
            HINT = 'Send a valid list of tables';
        END IF;*/

        --Temp table
        DROP TABLE IF EXISTS temp_table_coveredby;
        CREATE TEMP TABLE IF NOT EXISTS temp_table_coveredby (
            schemaname text,
            tablename text,
            pkname text,
            pkvalue bigint,
            attributes jsonb
        );
        --Incluindo a linha do lote
        EXECUTE format('SELECT json_agg(t) FROM (SELECT row_to_json(a.*) record FROM app.%1$I as a WHERE a.%2$I = %s) t;', basetable, basetablekey, basetablevalue) INTO at_json;
        INSERT INTO temp_table_coveredby VALUES ('app', basetable, basetablekey, basetablevalue, at_json);

        --FOR i IN 1 .. array_upper(coveredtables, 1)
	IF (coalesce(array_length(coveredtables, 1),0) > 0) THEN
		FOR i in array_lower(coveredtables, 1) .. array_upper(coveredtables, 1)
		LOOP
			stmt = format('SELECT json_agg(t) FROM (SELECT row_to_json(b.*) record
				FROM app.%1$I as a INNER JOIN app.%2$I as b
				ON public.ST_CoveredBy(public.ST_PointOnSurface(public.ST_MakeValid(b.geom)), public.ST_MakeValid(a.geom))
				WHERE a.%3$I = %s) t;', basetable, coveredtables[i], basetablekey, basetablevalue);
			--RAISE NOTICE 'hasRows: (%)', tb_json IS NULL;
			EXECUTE stmt INTO tb_json;
			--GET DIAGNOSTICS recordcount = ROW_COUNT;
			IF tb_json IS NOT NULL THEN
				EXECUTE format('SELECT app.fn_getprimarykey(''app'', %1$L);', coveredtables[i]) INTO pk_json;
				INSERT INTO temp_table_coveredby VALUES (pk_json->>'table_schema', coveredtables[i], pk_json->>'column_name', 0, tb_json);
			END IF;
		END LOOP;
	END IF;

        SELECT json_agg(t) FROM (
            SELECT
                   schemaname as "schema",
                   tablename as "table",
                   pkname as "uidcolumn",
                   attributes->>'uid' as "uidvalue",
                   attributes as "records"
            FROM temp_table_coveredby
        ) t INTO tb_json;

        RETURN (SELECT json_build_object('transaction', public.uuid_generate_v4(), 'tables', tb_json));
    END;

$_$;


--
-- TOC entry 1685 (class 1255 OID 902187)
-- Name: fn_getdatatype(text, text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_getdatatype(schemaname text, tablename text, columnname text) RETURNS regtype
    LANGUAGE plpgsql
    AS $_$
	DECLARE strings text[];
    DECLARE stmt text;
    DECLARE typereg regtype;
	BEGIN
    	IF (coalesce(schemaname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Schema name cannot be null or empty',
            HINT = 'Send a schema name';
        END IF;
        IF (coalesce(tablename, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Table name cannot be null or empty',
            HINT = 'Send a table name';
        END IF;
        IF (coalesce(columnname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Colum nname cannot be null or empty',
            HINT = 'Send a column name';
        END IF;
        stmt = format('SELECT pg_typeof(%1$I) FROM %2$I.%3$I WHERE %1$I IS NOT NULL LIMIT 1; ', columnname,  schemaname, tablename);
        EXECUTE stmt INTO typereg;
        RETURN typereg;
    END;
	
$_$;


--
-- TOC entry 1686 (class 1255 OID 902188)
-- Name: fn_getprimarykey(text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_getprimarykey(schemaname text, tablename text) RETURNS json
    LANGUAGE plpgsql
    AS $$
    DECLARE stmt text;
    DECLARE result json;
	BEGIN
    	IF (coalesce(schemaname, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Schema name cannot be null or empty',
            HINT = 'Send a schema name';
      END IF;
      IF (coalesce(tablename, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Table name cannot be null or empty',
            HINT = 'Send a table name';
      END IF;
      EXECUTE format('SELECT row_to_json(row)
FROM (SELECT t.table_catalog,
         t.table_schema,
         t.table_name,
         kcu.constraint_name,
         kcu.column_name,
         kcu.ordinal_position
FROM    INFORMATION_SCHEMA.TABLES t
         LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
                 ON tc.table_catalog = t.table_catalog
                 AND tc.table_schema = t.table_schema
                 AND tc.table_name = t.table_name
                 AND tc.constraint_type = ''PRIMARY KEY''
         LEFT JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                 ON kcu.table_catalog = tc.table_catalog
                 AND kcu.table_schema = tc.table_schema
                 AND kcu.table_name = tc.table_name
                 AND kcu.constraint_name = tc.constraint_name
WHERE   t.table_schema = %L AND t.table_name = %L) row;', schemaname, tablename) INTO result;
      -- EXECUTE stmt INTO result;
      /*RAISE EXCEPTION 'Execution refused'
            USING DETAIL = stmt,
            HINT = 'Send a view text';*/
      RETURN result;
    END;
$$;


--
-- TOC entry 1687 (class 1255 OID 902189)
-- Name: fn_gettableattributes(text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_gettableattributes(schemaname text, tablename text) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE data_type json;
BEGIN
	IF (coalesce(schemaName, '') = '') THEN
		RAISE EXCEPTION 'Execution refused'
		USING DETAIL = 'Schema name cannot be null or empty',
		HINT = 'Send a schema name';
	END IF;
	IF (coalesce(tablename, '') = '') THEN
		RAISE EXCEPTION 'Execution refused'
		USING DETAIL = 'Table name cannot be null or empty',
		HINT = 'Send a table name';
	END IF;

	RETURN 
		(select array_to_json(array_agg(row_to_json(t)))
		    from (
			SELECT a.attname, format_type(a.atttypid, a.atttypmod) AS atttype, a.atttypid
			FROM pg_attribute a
			JOIN pg_class b ON (a.attrelid = b.relfilenode)
			JOIN pg_namespace c ON (c.oid = b.relnamespace)
			WHERE b.relname = tablename and
				c.nspname = schemaname and
				a.attstattarget = -1) as t);
END;
$$;


--
-- TOC entry 1688 (class 1255 OID 902190)
-- Name: fn_registerview(text, text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_registerview(schemaname text, viewname text, viewtext text) RETURNS json
    LANGUAGE plpgsql
    AS $_$
	DECLARE strings text[];
	BEGIN
    	IF (coalesce(schemaName, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Schema name cannot be null or empty',
            HINT = 'Send a schema name';
        END IF;
        IF (coalesce(viewName, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'View name cannot be null or empty',
            HINT = 'Send a view name';
        END IF;
        IF (coalesce(viewText, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'View text cannot be null or empty',
            HINT = 'Send a view text';
        END IF;
		strings := (SELECT string_to_array(viewText, ';'));
		IF (array_length(strings, 1) > 2) THEN
            RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Detected many queries',
            HINT = 'Send only one query';
		ELSE
        	EXECUTE format('
      CREATE OR REPLACE VIEW %1$I.%2$I AS %3$s', schemaName, viewName, strings[1]);
            --EXECUTE IMMEDIATE 'CREATE OR REPLACE VIEW "' + schemaName + '"."' + viewName + '" AS ' + strings[1];
            RETURN json_build_object('schemaName', schemaName, 'viewName', viewName, 'success', 'true');
        END IF;
    END;
	$_$;


--
-- TOC entry 1689 (class 1255 OID 902191)
-- Name: fn_unregisterview(text, text); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.fn_unregisterview(schemaname text, viewname text) RETURNS json
    LANGUAGE plpgsql
    AS $_$
DECLARE strings text[];
	BEGIN
    	IF (coalesce(schemaName, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'Schema name cannot be null or empty',
            HINT = 'Send a schema name';
        END IF;
        IF (coalesce(viewName, '') = '') THEN
        	RAISE EXCEPTION 'Execution refused'
            USING DETAIL = 'View name cannot be null or empty',
            HINT = 'Send a view name';
        END IF;
	EXECUTE format('DROP VIEW IF EXISTS %1$I.%2$I', schemaName, viewName);
	RETURN json_build_object('schemaName', schemaName, 'viewName', viewName, 'success', 'true');
    END;

$_$;


--
-- TOC entry 1690 (class 1255 OID 902192)
-- Name: get_film(integer); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.get_film(p_pattern integer DEFAULT NULL::integer) RETURNS TABLE(geodb_oid integer, geom jsonb)
    LANGUAGE sql
    AS $_$
--BEGIN
 --RETURN QUERY 
  SELECT
     geodb_oid
	,ST_AsGeoJSON(ST_CurveToLine(geom))::jsonb "geom"
  FROM "SDE"."FLTE_LOTES" "x"
 WHERE geodb_oid = $1;
--END; 
$_$;


--
-- TOC entry 2601 (class 1255 OID 902248)
-- Name: boxplot(double precision); Type: AGGREGATE; Schema: app; Owner: -
--

CREATE AGGREGATE app.boxplot(double precision) (
    SFUNC = array_append,
    STYPE = double precision[],
    INITCOND = '{}',
    FINALFUNC = app._final_boxplot
);


--
-- TOC entry 2602 (class 1255 OID 902249)
-- Name: boxplot(numeric); Type: AGGREGATE; Schema: app; Owner: -
--

CREATE AGGREGATE app.boxplot(numeric) (
    SFUNC = array_append,
    STYPE = numeric[],
    INITCOND = '{}',
    FINALFUNC = app._final_boxplot
);


--
-- TOC entry 2603 (class 1255 OID 902250)
-- Name: boxplot(timestamp without time zone); Type: AGGREGATE; Schema: app; Owner: -
--

CREATE AGGREGATE app.boxplot(timestamp without time zone) (
    SFUNC = array_append,
    STYPE = timestamp without time zone[],
    INITCOND = '{}',
    FINALFUNC = app._final_boxplot
);


SET default_tablespace = '';

--
-- TOC entry 229 (class 1259 OID 902287)
-- Name: t_imobiliario_default; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_imobiliario_default (
    codred bigint NOT NULL,
    inscricao character varying(255) NOT NULL,
    chave_lote character varying(50),
    cod_face character varying(50),
    face character varying(50),
    zona_fiscal character varying(50),
    zoneamento character varying(50),
    data_implantacao timestamp(6) without time zone,
    data_ultima_atualizacao timestamp(6) without time zone,
    usuario_alteracao character varying(255),
    matricula character varying(255),
    habitese character varying(255),
    data_habitese timestamp(6) without time zone,
    situacao_cadastral character varying(50),
    cod_proprietario character varying(255),
    proprietario character varying(255),
    rg_proprietario character varying(50),
    cpf_proprietario character varying(50),
    cnpj_proprietario character varying(50),
    cod_compromissario character varying(50),
    compromissario character varying(255),
    rg_compromissario character varying(50),
    cpf_compromissario character varying(50),
    cnpj_compromissario character varying(50),
    cod_logradouro character varying(50),
    logradouro character varying(255),
    numero character varying(50),
    numero_anterior character varying(50),
    complemento character varying(255),
    cod_bairro character varying(50),
    bairro character varying(255),
    cep character varying(50),
    cod_loteamento character varying(50),
    loteamento character varying(255),
    quadra_loteam character varying(50),
    lote_loteam character varying(50),
    ent_logradouro character varying(255),
    ent_numero character varying(50),
    ent_complemento character varying(255),
    ent_bairro character varying(255),
    ent_cidade character varying(255),
    ent_uf character varying(5),
    ent_cep character varying(50),
    cobranca character varying(255),
    categ_propriedade character varying(50),
    area_terreno double precision,
    fracao_ideal double precision,
    testada_princ double precision,
    soma_testadas double precision,
    qt_testadas smallint,
    area_ocupada double precision,
    ocupacao character varying(50),
    uso_terreno character varying(50),
    situacao character varying(50),
    topografia character varying(50),
    consistencia_solo character varying(50),
    forma character varying(50),
    benfeitorias character varying(50),
    condominio character varying(255),
    vagas_cobertas character varying(50),
    vagas_descobertas character varying(50),
    id_edificacao character varying(50),
    area_const_princ double precision,
    area_depend double precision,
    area_garagem double precision,
    area_cobert double precision,
    area_pisc double precision,
    area_const_total double precision,
    area_const_lote double precision,
    qt_pavimentos smallint,
    area_privativa double precision,
    area_comum double precision,
    tipo_const character varying(50),
    padrao_const character varying(50),
    conservacao character varying(50),
    posicao_const character varying(50),
    situacao_const character varying(50),
    edicula character varying(50),
    regime_ocupacao character varying(50),
    categoria_ocupacao character varying(50),
    elevador character varying(50),
    estrutura character varying(50),
    cobertura character varying(50),
    fachada character varying(50),
    pintura_ext character varying(50),
    pintura_int character varying(50),
    revest_int_social character varying(50),
    revest_int_servico character varying(50),
    revestimento_ext character varying(50),
    forro_social character varying(50),
    forro_servico character varying(50),
    pintura_forro character varying(50),
    piso_social character varying(50),
    piso_servico character varying(50),
    piso_externo character varying(50),
    portas character varying(50),
    esq_janelas character varying(50),
    esq_vitros character varying(50),
    esq_pintura character varying(50),
    inst_eletrica character varying(50),
    inst_sanitaria character varying(50),
    piscina character varying(50),
    pe_direito character varying(50),
    vao character varying(50),
    recuo character varying(50),
    beiral character varying(50),
    data_construcao timestamp(6) without time zone,
    qt_edificacoes smallint,
    acesso character varying(50),
    desconto character varying(50),
    observacao character varying(255),
    agua character varying(50),
    luz character varying(50),
    pavimentacao character varying(50),
    meio_fio character varying(50),
    esgoto character varying(50),
    coleta_lixo character varying(50),
    telefone character varying(50),
    ilum_publica character varying(50),
    aguas_pluviais character varying(50),
    status character varying(50),
    cdc character varying(25),
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint NOT NULL,
    dt_import timestamp(6) with time zone
);


--
-- TOC entry 5418 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE t_imobiliario_default; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_imobiliario_default IS 'Cadastro imobiliário consolidado';


--
-- TOC entry 5419 (class 0 OID 0)
-- Dependencies: 229
-- Name: COLUMN t_imobiliario_default.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_imobiliario_default.md_add IS 'Data criação';


--
-- TOC entry 5420 (class 0 OID 0)
-- Dependencies: 229
-- Name: COLUMN t_imobiliario_default.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_imobiliario_default.md_alt IS 'Data alteração';


--
-- TOC entry 5421 (class 0 OID 0)
-- Dependencies: 229
-- Name: COLUMN t_imobiliario_default.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_imobiliario_default.md_usr IS 'User id criação';


--
-- TOC entry 5422 (class 0 OID 0)
-- Dependencies: 229
-- Name: COLUMN t_imobiliario_default.md_usr_last; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_imobiliario_default.md_usr_last IS 'User id alteração';


--
-- TOC entry 230 (class 1259 OID 902294)
-- Name: 000_-_000_-_Caracteristica_do_Imovel_View; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app."000_-_000_-_Caracteristica_do_Imovel_View" AS
 SELECT t_imobiliario_default.codred AS sequencia,
    t_imobiliario_default.chave_lote AS rk,
    t_imobiliario_default.inscricao,
    NULL::text AS "009___041__forma",
    t_imobiliario_default.proprietario,
    NULL::text AS cpfproprietario,
    t_imobiliario_default.compromissario,
    NULL::text AS cpf_compr,
    NULL::text AS codlogr,
    NULL::text AS nomelogr,
    NULL::text AS nrimovel,
    NULL::text AS complemento,
    NULL::text AS cod_bairro,
    NULL::text AS nomebairro,
    NULL::text AS cep_c,
    NULL::text AS cod_loteam,
    NULL::text AS loteamento,
    NULL::text AS qdloteamento,
    NULL::text AS loteloteamento,
    t_imobiliario_default.ocupacao AS "009___025___ocupação",
    NULL::text AS "009___029___topografia",
    NULL::text AS cond_vert,
    NULL::text AS benfeitorias,
    NULL::text AS "009___026___situação_do_terreno",
    NULL::text AS "009___031___patrimônio",
    NULL::text AS "010___035___caracterização",
    t_imobiliario_default.uso_terreno AS "009___027__utilização_do_imovel",
    NULL::text AS padrao,
    NULL::text AS "010___044___estado_de_conservação",
    NULL::text AS pavimento,
    NULL::text AS "010___036___revestimento_externo",
    NULL::text AS "010___051___pintura_externa",
    NULL::text AS "010___045___instalacão__elétrica",
    NULL::text AS "010___043___estrutura",
    NULL::text AS "010___039___cobertura",
    NULL::text AS "010___054___esquadrias",
    t_imobiliario_default.area_terreno AS areaterreno,
    t_imobiliario_default.testada_princ AS testadaprincipal,
    t_imobiliario_default.area_const_total AS areaprincipal,
    NULL::text AS area_auto,
    t_imobiliario_default.area_const_lote AS areaatualita,
    NULL::text AS areatotalunid,
    NULL::text AS data_levant,
    (((t_imobiliario_default.logradouro)::text || ', '::text) || (t_imobiliario_default.numero)::text) AS endreco_full,
    t_imobiliario_default.logradouro AS nomelogr_c,
    t_imobiliario_default.numero AS nrimovel_c,
    NULL::text AS complemento_c,
    t_imobiliario_default.bairro AS nomebairro_c,
    'Mauá'::text AS municipio_c,
    'SP'::text AS uf_c,
    '00'::text AS distrito,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS zona,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS dd,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS zn,
    substr((t_imobiliario_default.chave_lote)::text, 4, 3) AS qqq,
    substr((t_imobiliario_default.chave_lote)::text, 8, 3) AS llll,
    '00'::text AS uuu,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS ddzn,
    substr((t_imobiliario_default.chave_lote)::text, 1, 6) AS ddznqqq,
    t_imobiliario_default.chave_lote AS ddznqqqllll,
    t_imobiliario_default.inscricao AS ddssqqqlllluuu,
    substr((t_imobiliario_default.chave_lote)::text, 1, 6) AS ddzn_f,
    substr((t_imobiliario_default.chave_lote)::text, 1, 6) AS ddznqqq_f,
    substr((t_imobiliario_default.chave_lote)::text, 1, 10) AS ddznqqqllll_f,
    t_imobiliario_default.inscricao AS ddssqqqlllluuu_f,
    NULL::text AS cod_bairro_str,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS folha_str,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS param_str,
    substr((t_imobiliario_default.chave_lote)::text, 4, 3) AS quadra_str,
    substr((t_imobiliario_default.chave_lote)::text, 8, 3) AS lote_str,
    '00'::text AS bloco_str,
    '00'::text AS sub_bloco_str,
    (((t_imobiliario_default.logradouro)::text || ', '::text) || (t_imobiliario_default.numero)::text) AS endreco_full_all,
    1 AS segmento,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS folha,
    substr((t_imobiliario_default.chave_lote)::text, 1, 2) AS parametro,
    substr((t_imobiliario_default.chave_lote)::text, 4, 3) AS quadra,
    substr((t_imobiliario_default.chave_lote)::text, 8, 3) AS lote,
    '00'::text AS unidade,
    NULL::text AS tipopessoaprop,
    NULL::text AS "010___052____revestimento_interno",
    NULL::text AS "010___053___pintura_interna",
    NULL::text AS "010___038___forro",
    NULL::text AS nrsala,
    NULL::text AS nrquarto,
    NULL::text AS nrcozinha,
    NULL::text AS nrbanheiro,
    NULL::text AS nrdependencia,
    NULL::text AS nrgaragem,
    NULL::text AS pedireito,
    NULL::text AS vao,
    NULL::text AS pavimentos,
    NULL::text AS recuo,
    NULL::text AS aproveitamento,
    NULL::text AS txocupacao,
    NULL::text AS utilizacao,
    NULL::text AS iesem,
    NULL::text AS iepiscina,
    NULL::text AS iequadra,
    NULL::text AS iesauna,
    NULL::text AS ieeventos,
    NULL::text AS ieoutros,
    NULL::text AS cnpjproprietario,
    NULL::text AS "009___028___pedologia",
    NULL::text AS "009___030___limitação",
    NULL::text AS "009___042___calçada",
    NULL::text AS "009___040__nivel",
    NULL::text AS demaistestadas,
    NULL::text AS areaedicula,
    NULL::text AS areagaragem,
    NULL::text AS areaterraco,
    NULL::text AS areapiscina,
    NULL::text AS "010___037___piso",
    NULL::text AS "010___040___instalação_sanitária",
    NULL::text AS "010___049___ano_de_construção",
    t_imobiliario_default.uid,
    NULL::text AS md_usr,
    NULL::text AS md_add,
    NULL::text AS md_alt,
    NULL::text AS md_usr_last
   FROM app.t_imobiliario_default;


--
-- TOC entry 231 (class 1259 OID 902313)
-- Name: TBL_TEMP; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app."TBL_TEMP" (
    objectid smallint NOT NULL,
    themestyle jsonb NOT NULL,
    inserted timestamp without time zone DEFAULT now() NOT NULL,
    updated timestamp without time zone,
    uid bigint NOT NULL,
    fuid bigint,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text
);


--
-- TOC entry 232 (class 1259 OID 902321)
-- Name: TBL_TEMP_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app."TBL_TEMP_uid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5423 (class 0 OID 0)
-- Dependencies: 232
-- Name: TBL_TEMP_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app."TBL_TEMP_uid_seq" OWNED BY app."TBL_TEMP".uid;


--
-- TOC entry 233 (class 1259 OID 902323)
-- Name: TBL_THEMES; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app."TBL_THEMES" (
    objectid bigint NOT NULL,
    userid integer,
    title character varying(255),
    description character varying(255),
    settings jsonb,
    inserted timestamp without time zone DEFAULT now() NOT NULL,
    updated timestamp without time zone,
    uid bigint NOT NULL,
    fuid bigint,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text
);


--
-- TOC entry 234 (class 1259 OID 902331)
-- Name: TBL_THEMES_objectid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app."TBL_THEMES_objectid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5424 (class 0 OID 0)
-- Dependencies: 234
-- Name: TBL_THEMES_objectid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app."TBL_THEMES_objectid_seq" OWNED BY app."TBL_THEMES".objectid;


--
-- TOC entry 235 (class 1259 OID 902333)
-- Name: TBL_THEMES_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app."TBL_THEMES_uid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5425 (class 0 OID 0)
-- Dependencies: 235
-- Name: TBL_THEMES_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app."TBL_THEMES_uid_seq" OWNED BY app."TBL_THEMES".uid;


--
-- TOC entry 236 (class 1259 OID 902335)
-- Name: TBL_THEMETYPES; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app."TBL_THEMETYPES" (
    objectid smallint NOT NULL,
    typename character varying(100) NOT NULL,
    typedescription character varying(255),
    inserted timestamp without time zone DEFAULT now() NOT NULL,
    updated timestamp without time zone,
    uid bigint NOT NULL,
    fuid bigint,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text
);


--
-- TOC entry 237 (class 1259 OID 902343)
-- Name: TBL_THEMETYPES_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app."TBL_THEMETYPES_uid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5426 (class 0 OID 0)
-- Dependencies: 237
-- Name: TBL_THEMETYPES_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app."TBL_THEMETYPES_uid_seq" OWNED BY app."TBL_THEMETYPES".uid;


--
-- TOC entry 238 (class 1259 OID 902345)
-- Name: uid_acesso_audit_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_acesso_audit_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 239 (class 1259 OID 902347)
-- Name: acesso_audit; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.acesso_audit (
    id integer NOT NULL,
    datetime timestamp(6) without time zone NOT NULL,
    ip character varying NOT NULL,
    "user" character varying,
    "table" character varying,
    action character varying NOT NULL,
    description text,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_acesso_audit_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 5427 (class 0 OID 0)
-- Dependencies: 239
-- Name: TABLE acesso_audit; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.acesso_audit IS 'Consulta Uso e Ocupação e Memorial Descritivo';


--
-- TOC entry 240 (class 1259 OID 902355)
-- Name: acesso_audit_id_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.acesso_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5428 (class 0 OID 0)
-- Dependencies: 240
-- Name: acesso_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.acesso_audit_id_seq OWNED BY app.acesso_audit.id;


--
-- TOC entry 241 (class 1259 OID 902357)
-- Name: uid_acesso_settings_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_acesso_settings_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 242 (class 1259 OID 902359)
-- Name: acesso_settings; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.acesso_settings (
    "ID" integer NOT NULL,
    "TYPE" integer DEFAULT 1,
    "NAME" text,
    "USERNAME" text,
    "COOKIE" character varying,
    "SEARCH" text,
    "TABLENAME" character varying,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_acesso_settings_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 5429 (class 0 OID 0)
-- Dependencies: 242
-- Name: TABLE acesso_settings; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.acesso_settings IS 'Consulta Uso e Ocupação e Memorial Descritivo';


--
-- TOC entry 243 (class 1259 OID 902368)
-- Name: acesso_settings_ID_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app."acesso_settings_ID_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 244 (class 1259 OID 902370)
-- Name: acesso_settings_id_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.acesso_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5430 (class 0 OID 0)
-- Dependencies: 244
-- Name: acesso_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.acesso_settings_id_seq OWNED BY app.acesso_settings."ID";


--
-- TOC entry 245 (class 1259 OID 902372)
-- Name: uid_acesso_tbl_link_acesso_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_acesso_tbl_link_acesso_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 246 (class 1259 OID 902374)
-- Name: acesso_tbl_link_acesso; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.acesso_tbl_link_acesso (
    ident smallint NOT NULL,
    descricao character varying(255),
    link_acesso character varying(1000),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_acesso_tbl_link_acesso_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 247 (class 1259 OID 902382)
-- Name: acesso_tbl_link_acesso_ident_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.acesso_tbl_link_acesso_ident_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5431 (class 0 OID 0)
-- Dependencies: 247
-- Name: acesso_tbl_link_acesso_ident_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.acesso_tbl_link_acesso_ident_seq OWNED BY app.acesso_tbl_link_acesso.ident;


--
-- TOC entry 248 (class 1259 OID 902384)
-- Name: admin_editor_settings; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.admin_editor_settings AS
 SELECT DISTINCT '1'::text AS uid,
    ''::text AS u_name,
    ''::text AS u_login,
    ''::text AS u_email,
    ''::text AS u_access,
    (json_build_object('pt-BR', '', 'es', '', 'en', '', 'it', '', 'raw', ''))::jsonb AS t_alias,
    col.catalog AS t_catalog,
    col.schema AS t_schema,
    col."table" AS t_name,
    tbl.table_type AS t_type,
        CASE
            WHEN ((tbl.is_insertable_into)::text = 'YES'::text) THEN true
            ELSE false
        END AS t_insertable,
    (col.columns)::jsonb AS t_columns,
    pk.attname AS k_name,
    pk.f_type AS k_udt,
    geom.f_geometry_column AS g_name,
    geom.coord_dimension AS g_dimension,
    geom.srid AS g_srid,
    geom.type AS g_udt,
    (((('GEOMETRY('::text || (geom.type)::text) || ','::text) || geom.srid) || ')'::text) AS g_desc
   FROM (((( SELECT colum.table_catalog AS catalog,
            colum.table_schema AS schema,
            colum.table_name AS "table",
            json_agg(json_build_object('name', colum.column_name, 'udt', colum.udt_name, 'dbt', colum.data_type, 'auto', ((seq.sequence_name)::text <> ''::text), 'isnull', lower((colum.is_nullable)::text), 'seq', seq.sequence_name)) AS columns
           FROM (information_schema.columns colum
             LEFT JOIN information_schema.sequences seq ON ((((seq.sequence_catalog)::text = (colum.table_catalog)::text) AND ((seq.sequence_schema)::text = (colum.table_schema)::text) AND ((colum.column_default)::text ~ similar_escape((('%('::text || (seq.sequence_name)::text) || ')%'::text), NULL::text)) AND ((seq.sequence_name)::text <> ''::text))))
          GROUP BY colum.table_catalog, colum.table_schema, colum.table_name) col
     LEFT JOIN public.geometry_columns geom ON ((((geom.f_table_catalog)::text = (col.catalog)::text) AND ((geom.f_table_schema)::text = (col.schema)::text) AND ((geom.f_table_name)::text = (col."table")::text))))
     LEFT JOIN ( SELECT s.nspname,
            c.relname,
            a.attname,
            format_type(a.atttypid, a.atttypmod) AS f_type
           FROM (((pg_attribute a
             JOIN ( SELECT pg_index.indexrelid,
                    pg_index.indrelid,
                    pg_index.indnatts,
                    pg_index.indisunique,
                    pg_index.indisprimary,
                    pg_index.indisexclusion,
                    pg_index.indimmediate,
                    pg_index.indisclustered,
                    pg_index.indisvalid,
                    pg_index.indcheckxmin,
                    pg_index.indisready,
                    pg_index.indislive,
                    pg_index.indisreplident,
                    pg_index.indkey,
                    pg_index.indcollation,
                    pg_index.indclass,
                    pg_index.indoption,
                    pg_index.indexprs,
                    pg_index.indpred,
                    generate_subscripts(pg_index.indkey, 1) AS indkey_subscript
                   FROM pg_index) i ON ((i.indisprimary AND (i.indrelid = a.attrelid) AND (a.attnum = i.indkey[i.indkey_subscript]))))
             JOIN pg_class c ON ((a.attrelid = c.oid)))
             JOIN pg_namespace s ON ((c.relnamespace = s.oid)))) pk ON (((pk.nspname = (col.schema)::name) AND (pk.relname = (col."table")::name))))
     LEFT JOIN information_schema.tables tbl ON ((((tbl.table_catalog)::text = (col.catalog)::text) AND ((tbl.table_schema)::text = (col.schema)::text) AND ((tbl.table_name)::text = (col."table")::text))));


--
-- TOC entry 249 (class 1259 OID 902484)
-- Name: app_tdirfoto_id; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.app_tdirfoto_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 250 (class 1259 OID 902846)
-- Name: t_cius_consulta; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_consulta (
    id bigint NOT NULL,
    data_consulta timestamp(6) without time zone,
    solicitante character varying(255),
    autor character varying(255),
    chave character varying(50),
    loteamento character varying(255),
    uso_pretendido character varying(255),
    endereco character varying(500),
    ocupacao character varying(50),
    area_parcela_cad real,
    area_construida real,
    coordenadas character varying(255),
    imagem character varying(1000),
    app_50m_nascente character varying(50),
    area_app_50m_nascente real,
    app_30m character varying(50),
    area_app_30m real,
    apm character varying(50),
    area_apm real,
    parte_area_apm character varying(50),
    apm_categoria character varying(50),
    apm_classe character varying(50),
    macrozoneamento character varying(150),
    zona character varying(150),
    zoneamento character varying(150),
    atividade_p character varying(255),
    parcela_minima_p character varying(255),
    taxa_ocupacao_p character varying(100),
    coef_aproveitamento_p character varying(255),
    outorga_p character varying(100),
    taxa_permeabilidade_p character varying(255),
    recuo_frontal_p character varying(100),
    testada_p character varying(100),
    vagas_p character varying(100),
    zona_luos character varying(50),
    luos character varying(150),
    tipo_luos character varying(255),
    parcela_minima_luos character varying(255),
    taxa_ocupacao_luos character varying(100),
    categoria_luos integer,
    coef_aproveitamento_luos character varying(255),
    outorga_luos character varying(100),
    taxa_permeabilidade_luos character varying(255),
    recuo_frontal_luos character varying(100),
    testada_luos character varying(100),
    vagas_luos character varying(100),
    lote_maximo_luos character varying(100),
    atividade character varying(255),
    parcela_minima character varying(255),
    taxa_ocupacao character varying(100),
    coef_aproveitamento character varying(255),
    outorga character varying(100),
    taxa_permeabilidade character varying(255),
    recuo_frontal character varying(100),
    testada character varying(100),
    vagas character varying(100),
    hierarquia character varying(100),
    funcionario character varying(255),
    status character varying(15),
    data_altera timestamp(6) without time zone,
    outros_processos character varying(50),
    eiv_rit character varying(50),
    area_parcela_geo real,
    indice_ocupacao character varying(100),
    indice_edificacao character varying(100),
    indice_permeabilidade character varying(100),
    outorga_onerosa character varying(100),
    acao_alinhamento character varying(3),
    acao_const_comercial character varying(3),
    acao_alvara_emergencia character varying(3),
    acao_const_residencial character varying(3),
    acao_desmenbramento character varying(3),
    acao_diretrizes_zoneamento character varying(3),
    cnae character varying(255),
    cnae_secao character varying(2),
    cnae_grupo character varying(10),
    categoria_atividade character varying(255),
    descricao text,
    perim_parcela_geo real,
    qt_vertices smallint,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint NOT NULL,
    dist_zeic real,
    tipo_atividade_pretend character varying(255),
    atividade_pretend character varying(255),
    incomodidade_pretend character varying(255),
    cnae_pretend character varying(255),
    excecao_pretend character varying(255),
    desc_excecao character varying(255),
    observacao character varying(255),
    bairro character varying(255),
    descricao_macro character varying(255),
    ca_min_macro character varying(255),
    ca_bas_macro character varying(255),
    ca_max_macro character varying(255),
    to_pc_macro character varying(255),
    tp_pc_macro character varying(255),
    incomodo1 character varying(255),
    incomodo2 character varying(255),
    incomodo_medio character varying(255),
    incomodo_alto character varying(255),
    av_perc character varying(254),
    recuoslat character varying(254),
    recuofund character varying(254),
    link_url character varying(500),
    img_macro character varying(1000),
    img_zona character varying(1000),
    token character varying(500),
    cdc character varying(25),
    descricao_cius text,
    data_texto character varying(255),
    corzona character varying(255),
    faixa_nao_edif character varying(255),
    tipo_consulta character varying(255),
    tipo_atividade_pretend_comp text,
    atividade_pretend_comp text,
    cnae_pretend_comp character varying(255),
    deferido text,
    indeferido text
);


--
-- TOC entry 251 (class 1259 OID 902853)
-- Name: cons_uso_e_ocupacao_id_seq1; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.cons_uso_e_ocupacao_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5432 (class 0 OID 0)
-- Dependencies: 251
-- Name: cons_uso_e_ocupacao_id_seq1; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.cons_uso_e_ocupacao_id_seq1 OWNED BY app.t_cius_consulta.id;


--
-- TOC entry 252 (class 1259 OID 903098)
-- Name: geo_lote_31983; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.geo_lote_31983 (
    uid integer NOT NULL,
    geom public.geometry(MultiPolygon,4326),
    setor character varying(50),
    quadra character varying(50),
    lote character varying(50),
    chave character varying(50),
    data character varying(10),
    shape_area double precision,
    shape_len double precision,
    chave_mapa character varying(50),
    chave_lote character varying(50),
    md_add timestamp without time zone,
    md_alt timestamp without time zone,
    md_usr character varying,
    md_usr_last character varying,
    fuid bigint,
    edificacao double precision,
    numero character varying(255)
);


--
-- TOC entry 5433 (class 0 OID 0)
-- Dependencies: 252
-- Name: TABLE geo_lote_31983; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.geo_lote_31983 IS 'versão - 2026-07-14 11:24:22.205697-03';


--
-- TOC entry 253 (class 1259 OID 903112)
-- Name: geo_lote_31983_uid2_seq1; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.geo_lote_31983_uid2_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5434 (class 0 OID 0)
-- Dependencies: 253
-- Name: geo_lote_31983_uid2_seq1; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.geo_lote_31983_uid2_seq1 OWNED BY app.geo_lote_31983.uid;


--
-- TOC entry 254 (class 1259 OID 903430)
-- Name: metadata_setting; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.metadata_setting AS
 SELECT DISTINCT '1'::text AS uid,
    ''::text AS u_name,
    ''::text AS u_login,
    ''::text AS u_email,
    ''::text AS u_access,
    (json_build_object('pt-BR', '', 'es', '', 'en', '', 'it', '', 'raw', ''))::jsonb AS t_alias,
    col.catalog AS t_catalog,
    col.schema AS t_schema,
    col."table" AS t_name,
    tbl.table_type AS t_type,
        CASE
            WHEN ((tbl.is_insertable_into)::text = 'YES'::text) THEN true
            ELSE false
        END AS t_insertable,
    (col.columns)::jsonb AS t_columns,
    pk.attname AS k_name,
    pk.f_type AS k_udt,
    geom.f_geometry_column AS g_name,
    geom.coord_dimension AS g_dimension,
    geom.srid AS g_srid,
    geom.type AS g_udt,
    (((('GEOMETRY('::text || (geom.type)::text) || ','::text) || geom.srid) || ')'::text) AS g_desc
   FROM (((( SELECT colum.table_catalog AS catalog,
            colum.table_schema AS schema,
            colum.table_name AS "table",
            json_agg(json_build_object('name', colum.column_name, 'udt', colum.udt_name, 'dbt', colum.data_type, 'auto', ((seq.sequence_name)::text <> ''::text), 'isnull', lower((colum.is_nullable)::text), 'seq', seq.sequence_name)) AS columns
           FROM (information_schema.columns colum
             LEFT JOIN information_schema.sequences seq ON ((((seq.sequence_catalog)::text = (colum.table_catalog)::text) AND ((seq.sequence_schema)::text = (colum.table_schema)::text) AND ((colum.column_default)::text ~ similar_escape((('%('::text || (seq.sequence_name)::text) || ')%'::text), NULL::text)) AND ((seq.sequence_name)::text <> ''::text))))
          GROUP BY colum.table_catalog, colum.table_schema, colum.table_name) col
     LEFT JOIN public.geometry_columns geom ON ((((geom.f_table_catalog)::text = (col.catalog)::text) AND ((geom.f_table_schema)::text = (col.schema)::text) AND ((geom.f_table_name)::text = (col."table")::text))))
     LEFT JOIN ( SELECT s.nspname,
            c.relname,
            a.attname,
            format_type(a.atttypid, a.atttypmod) AS f_type
           FROM (((pg_attribute a
             JOIN ( SELECT pg_index.indexrelid,
                    pg_index.indrelid,
                    pg_index.indnatts,
                    pg_index.indisunique,
                    pg_index.indisprimary,
                    pg_index.indisexclusion,
                    pg_index.indimmediate,
                    pg_index.indisclustered,
                    pg_index.indisvalid,
                    pg_index.indcheckxmin,
                    pg_index.indisready,
                    pg_index.indislive,
                    pg_index.indisreplident,
                    pg_index.indkey,
                    pg_index.indcollation,
                    pg_index.indclass,
                    pg_index.indoption,
                    pg_index.indexprs,
                    pg_index.indpred,
                    generate_subscripts(pg_index.indkey, 1) AS indkey_subscript
                   FROM pg_index) i ON ((i.indisprimary AND (i.indrelid = a.attrelid) AND (a.attnum = i.indkey[i.indkey_subscript]))))
             JOIN pg_class c ON ((a.attrelid = c.oid)))
             JOIN pg_namespace s ON ((c.relnamespace = s.oid)))) pk ON (((pk.nspname = (col.schema)::name) AND (pk.relname = (col."table")::name))))
     LEFT JOIN information_schema.tables tbl ON ((((tbl.table_catalog)::text = (col.catalog)::text) AND ((tbl.table_schema)::text = (col.schema)::text) AND ((tbl.table_name)::text = (col."table")::text))));


--
-- TOC entry 255 (class 1259 OID 903668)
-- Name: t_anexo_IV_12_03_2026; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app."t_anexo_IV_12_03_2026" (
    "Macrozonas" character varying(255),
    "Zonas" character varying(255),
    "Categorias de uso permitidas (8)" character varying(255),
    "Exigência / Controle de Impacto" character varying(255),
    "Lote mínimo (m²)" character varying(255),
    "Testada Mínima (m)" character varying(255),
    "Taxa de Ocupação %" character varying(255),
    "Taxa de Permeabilidade (TP)
(3) (4)" character varying(255),
    "Coeficiente de Aproveitamento - CAMínimo" character varying(255),
    "Coeficiente de Aproveitamento - CA Básico" character varying(255),
    "Coeficiente de Aproveitamento - CA Máximo
(2)" character varying(255),
    "Recuo Frontal
(*) ver art 33 a 35" character varying(255),
    "Recuo Fundos
(*) Ver Art.36 à 37" character varying(255),
    "Recuo Lateral
(*) Ver Art.38 e 39" character varying(255)
);


--
-- TOC entry 256 (class 1259 OID 903674)
-- Name: t_anexo_V_12_03_2026; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app."t_anexo_V_12_03_2026" (
    tipo_empre character varying(255),
    lt_min_declivi_0_30 character varying(255),
    lt_min_declivi_30_50 character varying(255),
    lt_max character varying(255),
    testada character varying(255),
    recuo_frente character varying(255),
    recuo_fundos character varying(255),
    recuo_lateral character varying(255),
    tx_perme_declivi_0_20 character varying(255),
    tx_perme_declivi_20_50 character varying(255),
    tx_ocupacao character varying(255),
    ca character varying(255),
    "Categoria de Uso [6]" character varying(255),
    vaga_his1_zeis_ap character varying(255),
    vaga_his1_fzeis character varying(255)
);


--
-- TOC entry 257 (class 1259 OID 903680)
-- Name: t_anexos; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_anexos (
    inscricao character varying(255) NOT NULL,
    foto text,
    croqui text,
    matricula text,
    documento text,
    tipo character varying(255),
    chave_lote character varying(255),
    uid bigint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 258 (class 1259 OID 903687)
-- Name: t_anexos_ident_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_anexos_ident_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5435 (class 0 OID 0)
-- Dependencies: 258
-- Name: t_anexos_ident_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_anexos_ident_seq OWNED BY app.t_anexos.uid;


--
-- TOC entry 259 (class 1259 OID 903689)
-- Name: t_arquivos_anexos; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_arquivos_anexos (
    arquivos text,
    nivel character varying(255),
    arquivo character varying(255),
    ic character varying(50),
    chave character varying(50),
    cadastro character varying(50),
    end_fisico character varying(255),
    end_url character varying(255),
    tipo character varying(50),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint NOT NULL
);


--
-- TOC entry 260 (class 1259 OID 903696)
-- Name: t_arquivos_anexos_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_arquivos_anexos_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5436 (class 0 OID 0)
-- Dependencies: 260
-- Name: t_arquivos_anexos_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_arquivos_anexos_uid_seq OWNED BY app.t_arquivos_anexos.uid;


--
-- TOC entry 261 (class 1259 OID 903698)
-- Name: t_cius_atividades; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_atividades (
    ordem smallint NOT NULL,
    atividade character varying(500),
    incomodidade character varying(255),
    tipo character varying(255),
    cnae character varying(255),
    excecao smallint,
    uso_imovel character varying(25),
    desc_excecao character varying(255),
    uid integer NOT NULL
);


--
-- TOC entry 262 (class 1259 OID 903704)
-- Name: t_cius_atividades_ordem_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_cius_atividades_ordem_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5437 (class 0 OID 0)
-- Dependencies: 262
-- Name: t_cius_atividades_ordem_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_cius_atividades_ordem_seq OWNED BY app.t_cius_atividades.ordem;


--
-- TOC entry 263 (class 1259 OID 903706)
-- Name: t_cius_atividades_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_cius_atividades_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5438 (class 0 OID 0)
-- Dependencies: 263
-- Name: t_cius_atividades_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_cius_atividades_uid_seq OWNED BY app.t_cius_atividades.uid;


--
-- TOC entry 264 (class 1259 OID 903708)
-- Name: uid_t_cius_cnae_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_cnae_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 265 (class 1259 OID 903710)
-- Name: t_cius_cnae; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_cnae (
    id bigint NOT NULL,
    classe character varying(255),
    denominacao character varying(255),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_cius_cnae_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 266 (class 1259 OID 903718)
-- Name: uid_t_cius_cnae_denominacao_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_cnae_denominacao_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 267 (class 1259 OID 903720)
-- Name: t_cius_cnae_denominacao; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_cnae_denominacao (
    id bigint NOT NULL,
    secao character varying(255),
    grupo character varying(255),
    classe character varying(255),
    denominacao character varying(255),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_cius_cnae_denominacao_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 268 (class 1259 OID 903728)
-- Name: uid_t_cius_cnae_grupo_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_cnae_grupo_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 269 (class 1259 OID 903730)
-- Name: t_cius_cnae_grupo; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_cnae_grupo (
    id bigint NOT NULL,
    secao character varying(255),
    grupo character varying(255),
    denominacao character varying(255),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_cius_cnae_grupo_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 270 (class 1259 OID 903738)
-- Name: uid_t_cius_cnae_secao_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_cnae_secao_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 271 (class 1259 OID 903740)
-- Name: t_cius_cnae_secao; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_cnae_secao (
    id bigint NOT NULL,
    secao character varying(255),
    denominacao character varying(255),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_cius_cnae_secao_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 272 (class 1259 OID 903755)
-- Name: uid_t_cius_status_certidao_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_status_certidao_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 273 (class 1259 OID 903757)
-- Name: t_cius_status_certidao; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_status_certidao (
    id integer NOT NULL,
    status character varying,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_cius_status_certidao_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 274 (class 1259 OID 903765)
-- Name: uid_t_cius_uso_geral_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_uso_geral_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 275 (class 1259 OID 903767)
-- Name: t_cius_uso_geral; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_cius_uso_geral (
    id integer NOT NULL,
    tipo_uso character varying(255),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_cius_uso_geral_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 276 (class 1259 OID 903775)
-- Name: t_config_system; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_config_system (
    uid integer NOT NULL,
    system_name character varying(255),
    end_logo character varying(255)
);


--
-- TOC entry 277 (class 1259 OID 903781)
-- Name: t_depart; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_depart (
    uid smallint NOT NULL,
    depart character varying(255),
    descricao character varying(255),
    ordem_depart smallint,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 278 (class 1259 OID 903788)
-- Name: t_depart_cadastro; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_depart_cadastro (
    uid integer NOT NULL,
    fuid_depart character varying(32),
    depart character varying(255),
    fuid_cad integer,
    cadastro character varying(255),
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    link text,
    name_link character varying(255)
);


--
-- TOC entry 279 (class 1259 OID 903795)
-- Name: t_depart_cadastro_grupo; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_depart_cadastro_grupo (
    uid integer NOT NULL,
    fuid_group integer,
    name_group character varying(255),
    fuid_depart_cadastro integer,
    fuid_depart integer,
    depart character varying(255),
    fuid_cadastro integer,
    cadastro character varying(255),
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    link text,
    link_view text,
    link_print text
);


--
-- TOC entry 280 (class 1259 OID 903802)
-- Name: t_depart_cadastro_grupo_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_depart_cadastro_grupo_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5439 (class 0 OID 0)
-- Dependencies: 280
-- Name: t_depart_cadastro_grupo_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_depart_cadastro_grupo_uid_seq OWNED BY app.t_depart_cadastro_grupo.uid;


--
-- TOC entry 281 (class 1259 OID 903804)
-- Name: t_depart_cadastro_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_depart_cadastro_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5440 (class 0 OID 0)
-- Dependencies: 281
-- Name: t_depart_cadastro_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_depart_cadastro_uid_seq OWNED BY app.t_depart_cadastro.uid;


--
-- TOC entry 282 (class 1259 OID 903806)
-- Name: t_depart_link_docs; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_depart_link_docs (
    uid smallint NOT NULL,
    tipo character varying(255),
    permissao character varying(255)
);


--
-- TOC entry 283 (class 1259 OID 903812)
-- Name: t_depart_link_docs_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_depart_link_docs_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5441 (class 0 OID 0)
-- Dependencies: 283
-- Name: t_depart_link_docs_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_depart_link_docs_uid_seq OWNED BY app.t_depart_link_docs.uid;


--
-- TOC entry 284 (class 1259 OID 903814)
-- Name: t_depart_tabela; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_depart_tabela (
    uid smallint DEFAULT nextval('app.t_depart_cadastro_uid_seq'::regclass) NOT NULL,
    cadastro character varying(255),
    descricao character varying(255),
    ordem_cadastro integer,
    chave_cadastro character varying(255),
    camada character varying(255),
    chave_camada character varying(255),
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    url_link text,
    "order" integer
);


--
-- TOC entry 285 (class 1259 OID 903822)
-- Name: t_depart_tabela_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_depart_tabela_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5442 (class 0 OID 0)
-- Dependencies: 285
-- Name: t_depart_tabela_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_depart_tabela_uid_seq OWNED BY app.t_depart_tabela.uid;


--
-- TOC entry 286 (class 1259 OID 903824)
-- Name: t_depart_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_depart_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5443 (class 0 OID 0)
-- Dependencies: 286
-- Name: t_depart_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_depart_uid_seq OWNED BY app.t_depart.uid;


--
-- TOC entry 287 (class 1259 OID 903826)
-- Name: t_end_storage; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_end_storage (
    uid integer NOT NULL,
    end_url character varying(255),
    end_fisico character varying(255)
);


--
-- TOC entry 288 (class 1259 OID 903832)
-- Name: t_estim_area_const; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_estim_area_const (
    chave_lote character varying(13),
    area_original double precision,
    area_estimada double precision,
    var_abs double precision,
    var_pc double precision,
    ocupacao_old character varying(50),
    ocupacao_new character varying(50),
    status character varying(50),
    condominio character varying(50),
    qt_unid bigint,
    fx_abs character varying(50),
    fx_pc character varying(50),
    maior_50_50 character varying(50),
    maior_20_15 character varying(50),
    uid bigint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 289 (class 1259 OID 903839)
-- Name: t_estim_area_const_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_estim_area_const_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5444 (class 0 OID 0)
-- Dependencies: 289
-- Name: t_estim_area_const_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_estim_area_const_uid_seq OWNED BY app.t_estim_area_const.uid;


--
-- TOC entry 290 (class 1259 OID 903841)
-- Name: t_estim_area_const_vistoria; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_estim_area_const_vistoria (
    cdc bigint,
    chave_lote character varying(255),
    des_identificacao character varying(255),
    area_terr double precision,
    qtd_construcoes bigint,
    area_original_lote double precision,
    area_estimada_lote double precision,
    var_abs_lote double precision,
    var_pc_lote double precision,
    fx_abs character varying(50),
    fx_pc character varying(50),
    nome_prop character varying(255),
    cod_logradouro double precision,
    loc_logradouro character varying(255),
    loc_numero character varying(50),
    loc_complemento character varying(255),
    loc_bairro character varying(255),
    loc_cep character varying(50),
    ent_logradouro character varying(255),
    ent_numero character varying(50),
    ent_complemento character varying(255),
    ent_bairro character varying(255),
    ent_cidade character varying(50),
    ent_cep character varying(50),
    ent_uf character varying(50),
    des_cobranca character varying(50),
    status character varying(50),
    grupo character varying(50),
    uid bigint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 291 (class 1259 OID 903848)
-- Name: t_estim_area_const_vistoria_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_estim_area_const_vistoria_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5445 (class 0 OID 0)
-- Dependencies: 291
-- Name: t_estim_area_const_vistoria_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_estim_area_const_vistoria_uid_seq OWNED BY app.t_estim_area_const_vistoria.uid;


--
-- TOC entry 292 (class 1259 OID 903850)
-- Name: t_face_quadra; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_face_quadra (
    exercicio character varying(255),
    face_quadra character varying(255),
    logradouro character varying(255),
    bairro character varying(255),
    cep character varying(255),
    zona_fiscal character varying(255),
    valorm2 character varying(255),
    folha character varying(255),
    parametro character varying(255),
    quadra character varying(255),
    codface character varying(255),
    chave_face character varying(255),
    cod_log integer,
    log_cad character varying(255),
    agua character varying(50),
    luz character varying(50),
    pavimentacao character varying(50),
    meio_fio character varying(50),
    esgoto character varying(50),
    coleta_lixo character varying(50),
    telefone character varying(50),
    ilum_publica character varying(50),
    aguas_pluviais character varying(50),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint NOT NULL
);


--
-- TOC entry 293 (class 1259 OID 903857)
-- Name: t_face_quadra_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_face_quadra_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5446 (class 0 OID 0)
-- Dependencies: 293
-- Name: t_face_quadra_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_face_quadra_uid_seq OWNED BY app.t_face_quadra.uid;


--
-- TOC entry 294 (class 1259 OID 903859)
-- Name: t_pack; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_pack (
    uid integer NOT NULL,
    pack character varying(255),
    descricao character varying(255),
    ordem_pack integer,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    "order" integer
);


--
-- TOC entry 295 (class 1259 OID 903866)
-- Name: t_group_layer_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_group_layer_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5447 (class 0 OID 0)
-- Dependencies: 295
-- Name: t_group_layer_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_group_layer_uid_seq OWNED BY app.t_pack.uid;


--
-- TOC entry 296 (class 1259 OID 903868)
-- Name: t_groups; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_groups (
    uid bigint NOT NULL,
    name text,
    jbrules jsonb,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    modulo character varying(255),
    permissao character varying(255),
    tipo character varying(255)
);


--
-- TOC entry 5448 (class 0 OID 0)
-- Dependencies: 296
-- Name: TABLE t_groups; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_groups IS 'Tabela com os grupos com os tipos de permissão de acesso';


--
-- TOC entry 5449 (class 0 OID 0)
-- Dependencies: 296
-- Name: COLUMN t_groups.jbrules; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_groups.jbrules IS 'Um campo do tipo jsonb, onde armazenaremos algum json contendo os modulos e oque pode ser feito, um exemplo: {"uid":1, "name":"Administradores", md_{...}: "...", "jbRules": [ { module:"Sefin", police: CRUD - "onde C: enable to create, R: enable to retrieve, U: enable to update, D: enable to delete", } ]}';


--
-- TOC entry 5450 (class 0 OID 0)
-- Dependencies: 296
-- Name: COLUMN t_groups.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_groups.md_add IS 'Data de criação';


--
-- TOC entry 5451 (class 0 OID 0)
-- Dependencies: 296
-- Name: COLUMN t_groups.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_groups.md_alt IS 'Data de alteração';


--
-- TOC entry 5452 (class 0 OID 0)
-- Dependencies: 296
-- Name: COLUMN t_groups.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_groups.md_usr IS 'Id Usuário criação.';


--
-- TOC entry 5453 (class 0 OID 0)
-- Dependencies: 296
-- Name: COLUMN t_groups.md_usr_last; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_groups.md_usr_last IS 'Id usuário ultima alteração';


--
-- TOC entry 297 (class 1259 OID 903875)
-- Name: t_groups_permissao; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_groups_permissao (
    uid smallint NOT NULL,
    permissao character varying(255),
    regra character varying(255),
    tipo character varying(255)
);


--
-- TOC entry 298 (class 1259 OID 903881)
-- Name: t_groups_permissao_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_groups_permissao_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5454 (class 0 OID 0)
-- Dependencies: 298
-- Name: t_groups_permissao_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_groups_permissao_uid_seq OWNED BY app.t_groups_permissao.uid;


--
-- TOC entry 299 (class 1259 OID 903883)
-- Name: t_groups_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_groups_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5455 (class 0 OID 0)
-- Dependencies: 299
-- Name: t_groups_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_groups_uid_seq OWNED BY app.t_groups.uid;


--
-- TOC entry 300 (class 1259 OID 903885)
-- Name: t_imobiliario_default_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_imobiliario_default_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 301 (class 1259 OID 903887)
-- Name: t_imobiliario_default_uid_seq1; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_imobiliario_default_uid_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5456 (class 0 OID 0)
-- Dependencies: 301
-- Name: t_imobiliario_default_uid_seq1; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_imobiliario_default_uid_seq1 OWNED BY app.t_imobiliario_default.uid;


--
-- TOC entry 302 (class 1259 OID 903889)
-- Name: t_imobiliario_recad; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_imobiliario_recad (
    cidinscricao bigint NOT NULL,
    cbloqueio smallint,
    ciddispositivo bigint,
    cchave character varying(13),
    cinscricaoold character varying(18),
    cinscricaonew character varying(18) NOT NULL,
    cquadraold character varying(9),
    cquadranew character varying(9),
    cloteold character varying(9),
    clotenew character varying(9),
    cocorrencianew character varying(80),
    cproprietarioold character varying(120),
    cproprietarionew character varying(120),
    ctelefoneproprietarioold character varying(30),
    ctelefoneproprietarionew character varying(30),
    cemailproprietarioold character varying(50),
    cemailproprietarionew character varying(50),
    ccompromissarioold character varying(120),
    ccompromissarionew character varying(120),
    ctelefonecompromissarioold character varying(30),
    ctelefonecompromissarionew character varying(50),
    cemailcompromissarioold character varying(50),
    cemailcompromissarionew character varying(50),
    ccodlogold character varying(6),
    ccodlognew character varying(6),
    clogradouroold character varying(80),
    clogradouronew character varying(80),
    cnumeroold character varying(10),
    cnumeronew character varying(10),
    cocorrencianumeroold character varying(20),
    cocorrencianumeronew character varying(20),
    cnumerolocalnew character varying(10),
    cnumeromapanew character varying(10),
    ccomplementoold character varying(100),
    ccomplementonew character varying(100),
    cbairroold character varying(50),
    cbairronew character varying(50),
    ccepold character varying(20),
    ccepnew character varying(20),
    cloteamentoold character varying(50),
    cloteamentonew character varying(50),
    cloteamentoquadraold character varying(50),
    cloteamentoquadranew character varying(50),
    csituacaoold character varying(30),
    csituacaonew character varying(30),
    cpedologiaold character varying(30),
    cpedologianew character varying(30),
    ctopografiaold character varying(30),
    ctopografianew character varying(30),
    ccodcobrancaold character varying(50),
    ccodcobrancanew character varying(50),
    ccatproprietarioold character varying(30),
    ccatproprietarionew character varying(30),
    cbenfeitoriasold character varying(30),
    cbenfeitoriasnew character varying(30),
    ccatusoold character varying(30),
    ccatusonew character varying(30),
    ctipoconstrucaoold character varying(40),
    ctipoconstrucaonew character varying(40),
    cconservacaoold character varying(30),
    cconservacaonew character varying(30),
    cpadraoold character varying(30),
    cpadraonew character varying(30),
    crecuoold character varying(30),
    crecuonew character varying(30),
    cediculaold character varying(30),
    cediculanew character varying(30),
    celevadorold character varying(30),
    celevadornew character varying(30),
    csituacaoedifold character varying(30),
    csituacaoedifnew character varying(30),
    ccoberturaold character varying(30),
    ccoberturanew character varying(30),
    cparedesold character varying(30),
    cparedesnew character varying(30),
    crevestexparedesold character varying(30),
    crevestexparedesnew character varying(30),
    cpinturaexparedesold character varying(30),
    cpinturaexparedesnew character varying(30),
    crevestinparedessocold character varying(30),
    crevestinparedessocnew character varying(30),
    crevestinparedesservold character varying(30),
    crevestinparedesservnew character varying(30),
    cpinturainparedesold character varying(30),
    cpinturainparedesnew character varying(30),
    crevestforrosocold character varying(30),
    crevestforrosocnew character varying(30),
    crevestforroservold character varying(30),
    crevestforroservnew character varying(30),
    cpinturaforroold character varying(30),
    cpinturaforronew character varying(30),
    cpisosocialold character varying(30),
    cpisosocialnew character varying(30),
    cpisoservicoold character varying(30),
    cpisoserviconew character varying(30),
    cfachadaprincipalold character varying(30),
    cfachadaprincipalnew character varying(30),
    cpisoexternoold character varying(30),
    cpisoexternonew character varying(30),
    cportasold character varying(50),
    cportasnew character varying(50),
    cesquadjanelasold character varying(30),
    cesquadjanelasnew character varying(30),
    cesquadvitrosold character varying(30),
    cesquadvitrosnew character varying(30),
    cpinturaesquadriasold character varying(30),
    cpinturaesquadriasnew character varying(30),
    cinstalacoesold character varying(40),
    cinstalacoesnew character varying(40),
    cbeiralold character varying(80),
    cbeiralnew character varying(80),
    cacessonew character varying(30),
    careaterrenoold double precision,
    careaterrenonew double precision,
    ctestadaprincipalold double precision,
    ctestadaprincipalnew double precision,
    csomatestadasold double precision,
    csomatestadasnew double precision,
    cnumerotestadasold integer,
    cnumerotestadasnew integer,
    careaedificadaold double precision,
    careaedificadanew double precision,
    careatotalconstrold double precision,
    careatotalconstrnew double precision,
    careacomumcobertaold double precision,
    careacomumcobertanew double precision,
    careacomumdescobertaold double precision,
    careacomumdescobertanew double precision,
    careaprivativaold double precision,
    careaprivativanew double precision,
    cpavimentosold integer,
    cpavimentosnew integer,
    canoconstrucaoold character varying(4),
    canoconstrucaonew character varying(4),
    careaindustriapiaold double precision,
    careaindustriapianew double precision,
    careaindustriapibold double precision,
    careaindustriapibnew double precision,
    careaindustriapiiaold double precision,
    careaindustriapiianew double precision,
    careaindustriapiibold double precision,
    careaindustriapiibnew double precision,
    careaindustriaadiold double precision,
    careaindustriaadinew double precision,
    careaindustriaadiiold double precision,
    careaindustriaadiinew double precision,
    careaindustriagalpaoold double precision,
    careaindustriagalpaonew double precision,
    careaindustriatelheiroold double precision,
    careaindustriatelheironew double precision,
    cdatalevantamentonew timestamp(6) without time zone,
    cdataatualizacaonew timestamp(6) without time zone,
    ccadastradornew bigint,
    cobservacaonew character varying(255),
    cusuarioalteracao character varying(15),
    cusuario character varying(20),
    centrega smallint,
    crevisado smallint,
    cinclusao smallint,
    cadastroexportado character varying(8),
    cicmillenio character varying(50),
    fotos character varying(255),
    croquis character varying(10),
    situacaocadastro character varying(255),
    ctipoatualizacao character(1),
    atividadeeconomica smallint,
    cinscricaoorig character varying(255),
    layer character varying(255),
    const_principal character varying(1),
    const_dependencia character varying(1),
    cdc numeric(18,0),
    num_edif integer,
    uid integer NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 303 (class 1259 OID 903896)
-- Name: t_imobiliario_recad_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_imobiliario_recad_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5457 (class 0 OID 0)
-- Dependencies: 303
-- Name: t_imobiliario_recad_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_imobiliario_recad_uid_seq OWNED BY app.t_imobiliario_recad.uid;


--
-- TOC entry 304 (class 1259 OID 903898)
-- Name: t_pack_layer_grupo; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_pack_layer_grupo (
    uid integer NOT NULL,
    fuid_user integer,
    name_user character varying(255),
    fuid_group integer NOT NULL,
    name_group character varying(255),
    fuid_pack integer NOT NULL,
    name_pack character varying(255),
    ds_enable character varying(255),
    ds_name character varying(255),
    ds_type character varying(255),
    ws_name character varying(255),
    type character varying(255),
    srs character varying(255),
    projection_policy character varying(255),
    enabled character varying(255),
    name character varying(255),
    title character varying(255),
    native_name character varying(255),
    prefixed_name character varying(255),
    abstract character varying(255),
    name_tema character varying(255),
    fuid_tema_pack integer,
    ordem integer,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 305 (class 1259 OID 903905)
-- Name: t_layer_group_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_layer_group_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5458 (class 0 OID 0)
-- Dependencies: 305
-- Name: t_layer_group_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_layer_group_uid_seq OWNED BY app.t_pack_layer_grupo.uid;


--
-- TOC entry 306 (class 1259 OID 903907)
-- Name: t_logradouros; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_logradouros (
    cod_logradouro bigint NOT NULL,
    logradouro character varying(255),
    cep_correio character varying(254),
    esc_mapa character varying(254),
    tp_dec_lei character varying(254),
    num_dec_lei character varying(254),
    ano_dec_lei character varying(254),
    nom_anterior character varying(254),
    codgeo_ini character varying(254),
    codgeo_fim character varying(254),
    loteamento character varying(254),
    livro character varying(254),
    folha character varying(254),
    obs character varying(254),
    tipo character varying(254),
    agua character varying(50),
    luz character varying(50),
    pavimentacao character varying(50),
    meio_fio character varying(50),
    esgoto character varying(50),
    coleta_lixo character varying(50),
    telefone character varying(50),
    ilum_publica character varying(50),
    aguas_pluviais character varying(50),
    uid smallint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    problema character varying(255),
    nome character varying(255),
    link text,
    codgeo_eixo character varying(255),
    codgeo_eixo_correto character varying(255)
);


--
-- TOC entry 307 (class 1259 OID 903914)
-- Name: t_logradouros_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_logradouros_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5459 (class 0 OID 0)
-- Dependencies: 307
-- Name: t_logradouros_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_logradouros_uid_seq OWNED BY app.t_logradouros.uid;


--
-- TOC entry 308 (class 1259 OID 903916)
-- Name: uid_t_memo_registro_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_memo_registro_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 309 (class 1259 OID 903918)
-- Name: t_memo_registro; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_memo_registro (
    id bigint DEFAULT nextval('app.cons_uso_e_ocupacao_id_seq1'::regclass) NOT NULL,
    data_consulta timestamp(6) without time zone,
    solicitante character varying(255),
    autor character varying(255),
    chave character varying(20),
    loteamento character varying(255),
    uso_pretendido character varying(255),
    endereco character varying(500),
    ocupacao character varying(50),
    area_parcela_cad real,
    area_construida real,
    coordenadas character varying(255),
    imagem character varying(1000),
    app_50m_nascente character varying(50),
    area_app_50m_nascente real,
    app_30m character varying(50),
    area_app_30m real,
    apm character varying(50),
    area_apm real,
    parte_area_apm character varying(50),
    apm_categoria character varying(50),
    apm_classe character varying(50),
    macrozoneamento character varying(150),
    zona character varying(50),
    zoneamento character varying(150),
    atividade_p character varying(255),
    parcela_minima_p character varying(255),
    taxa_ocupacao_p character varying(100),
    coef_aproveitamento_p character varying(255),
    outorga_p character varying(100),
    taxa_permeabilidade_p character varying(255),
    recuo_frontal_p character varying(100),
    testada_p character varying(100),
    vagas_p character varying(100),
    zona_luos character varying(50),
    luos character varying(150),
    tipo_luos character varying(255),
    parcela_minima_luos character varying(255),
    taxa_ocupacao_luos character varying(100),
    categoria_luos integer,
    coef_aproveitamento_luos character varying(255),
    outorga_luos character varying(100),
    taxa_permeabilidade_luos character varying(255),
    recuo_frontal_luos character varying(100),
    testada_luos character varying(100),
    vagas_luos character varying(100),
    lote_maximo_luos character varying(100),
    atividade character varying(255),
    parcela_minima character varying(255),
    taxa_ocupacao character varying(100),
    coef_aproveitamento character varying(255),
    outorga character varying(100),
    taxa_permeabilidade character varying(255),
    recuo_frontal character varying(100),
    testada character varying(100),
    vagas character varying(100),
    hierarquia character varying(100),
    funcionario character varying(255),
    status character varying(15),
    data_altera timestamp(6) without time zone,
    outros_processos character varying(50),
    eiv_rit character varying(50),
    area_parcela_geo real,
    indice_ocupacao character varying(100),
    indice_edificacao character varying(100),
    indice_permeabilidade character varying(100),
    outorga_onerosa character varying(100),
    acao_alinhamento character varying(3),
    acao_const_comercial character varying(3),
    acao_alvara_emergencia character varying(3),
    acao_const_residencial character varying(3),
    acao_desmenbramento character varying(3),
    acao_diretrizes_zoneamento character varying(3),
    cnae character varying(255),
    cnae_secao character varying(2),
    cnae_grupo character varying(10),
    categoria_atividade character varying(255),
    descricao text,
    perim_parcela_geo real,
    qt_vertices smallint,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_t_memo_registro_pk_seq'::regclass) NOT NULL,
    cdc character varying(255)
);


--
-- TOC entry 310 (class 1259 OID 903927)
-- Name: t_mensagens; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_mensagens (
    uid bigint NOT NULL,
    fuid bigint,
    email_title text,
    email_to text,
    email_body text,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_last_usr text,
    observacao text,
    md_sent timestamp with time zone,
    email_attach_history text,
    md_usr_last text
);


--
-- TOC entry 5460 (class 0 OID 0)
-- Dependencies: 310
-- Name: TABLE t_mensagens; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_mensagens IS 'Tabela de mensagens ';


--
-- TOC entry 5461 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.fuid; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.fuid IS 'Uid do usuário que enviou a mensagem';


--
-- TOC entry 5462 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.email_title; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.email_title IS 'Titulo da mensagem';


--
-- TOC entry 5463 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.email_to; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.email_to IS 'E-mail de destinatario';


--
-- TOC entry 5464 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.email_body; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.email_body IS 'Conteúdo da mensagem';


--
-- TOC entry 5465 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.md_add IS 'Data de criação';


--
-- TOC entry 5466 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.md_alt IS 'Data de alteração';


--
-- TOC entry 5467 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.md_usr IS 'Id do usuário que criou o registro';


--
-- TOC entry 5468 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.md_last_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.md_last_usr IS 'Id do usuário que realizou a ultima alteração no registro.';


--
-- TOC entry 5469 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.observacao; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.observacao IS 'Campo adicionado para usuário incluir qualquer informação que esse achar relevante e que não será enviada por e-mail';


--
-- TOC entry 5470 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.md_sent; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.md_sent IS 'Data do último envio.';


--
-- TOC entry 5471 (class 0 OID 0)
-- Dependencies: 310
-- Name: COLUMN t_mensagens.email_attach_history; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens.email_attach_history IS 'Coluna temporária com a informação do nome do arquivo enviado em anexo nas mensagens. 
Apenas informativa.';


--
-- TOC entry 311 (class 1259 OID 903934)
-- Name: t_mensagens_anexos; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_mensagens_anexos (
    uid bigint NOT NULL,
    fuid bigint,
    anexo text,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text
);


--
-- TOC entry 5472 (class 0 OID 0)
-- Dependencies: 311
-- Name: TABLE t_mensagens_anexos; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_mensagens_anexos IS 'Anexos enviados por e-mail';


--
-- TOC entry 5473 (class 0 OID 0)
-- Dependencies: 311
-- Name: COLUMN t_mensagens_anexos.fuid; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens_anexos.fuid IS 'Uid da mensagem enviada';


--
-- TOC entry 5474 (class 0 OID 0)
-- Dependencies: 311
-- Name: COLUMN t_mensagens_anexos.anexo; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens_anexos.anexo IS 'Arquivo anexo na base de dados.';


--
-- TOC entry 5475 (class 0 OID 0)
-- Dependencies: 311
-- Name: COLUMN t_mensagens_anexos.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens_anexos.md_add IS 'Data de criação';


--
-- TOC entry 5476 (class 0 OID 0)
-- Dependencies: 311
-- Name: COLUMN t_mensagens_anexos.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens_anexos.md_alt IS 'Data de alteração';


--
-- TOC entry 5477 (class 0 OID 0)
-- Dependencies: 311
-- Name: COLUMN t_mensagens_anexos.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens_anexos.md_usr IS 'Id usuário criação';


--
-- TOC entry 5478 (class 0 OID 0)
-- Dependencies: 311
-- Name: COLUMN t_mensagens_anexos.md_usr_last; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_mensagens_anexos.md_usr_last IS 'Id usuário ultima alteração.';


--
-- TOC entry 312 (class 1259 OID 903941)
-- Name: t_mensagens_anexos_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_mensagens_anexos_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5479 (class 0 OID 0)
-- Dependencies: 312
-- Name: t_mensagens_anexos_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_mensagens_anexos_uid_seq OWNED BY app.t_mensagens_anexos.uid;


--
-- TOC entry 313 (class 1259 OID 903943)
-- Name: t_mensagens_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_mensagens_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5480 (class 0 OID 0)
-- Dependencies: 313
-- Name: t_mensagens_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_mensagens_uid_seq OWNED BY app.t_mensagens.uid;


--
-- TOC entry 314 (class 1259 OID 903945)
-- Name: t_metadados_print; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_metadados_print (
    uid bigint NOT NULL,
    titulo character varying(30),
    descricao character varying(80),
    cliente character varying(50),
    departamento character varying(50),
    logo_brasao text,
    rc_1 character varying(50),
    rc_2 character varying(50),
    tipo_img character varying(20),
    imagem text,
    isurl boolean DEFAULT false NOT NULL,
    overflow_texto character varying(60)
);


--
-- TOC entry 5481 (class 0 OID 0)
-- Dependencies: 314
-- Name: COLUMN t_metadados_print.isurl; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_metadados_print.isurl IS 'Indica se a imagem vem de uma fonte externa';


--
-- TOC entry 5482 (class 0 OID 0)
-- Dependencies: 314
-- Name: COLUMN t_metadados_print.overflow_texto; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_metadados_print.overflow_texto IS 'Notificação de quebra da legenda';


--
-- TOC entry 315 (class 1259 OID 903952)
-- Name: t_metadados_print_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_metadados_print_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5483 (class 0 OID 0)
-- Dependencies: 315
-- Name: t_metadados_print_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_metadados_print_uid_seq OWNED BY app.t_metadados_print.uid;


--
-- TOC entry 316 (class 1259 OID 903954)
-- Name: t_mobiliario_empresa; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_mobiliario_empresa (
    cinscmobiliariaold character varying(10),
    cinscmobiliarianew character varying(10),
    cocorrencianew character varying(40),
    crazaosocialnew character varying(200),
    cnomefantasianew character varying(200),
    ccpfcnpjnew character varying(30),
    ccodlognew character varying(5),
    clogradouronew character varying(80),
    cnumeronew character varying(50),
    ccomplementonew character varying(80),
    catividadecnaenew character varying(500),
    cobservacaonew character varying(255),
    cinclusao character varying(1),
    cinscricaooldorig character varying(18),
    cinscricaonew character varying(18),
    cchave character varying(13),
    cdatalevantamentonew character varying(60),
    uid bigint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 317 (class 1259 OID 903961)
-- Name: t_mobiliario_empresa_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_mobiliario_empresa_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5484 (class 0 OID 0)
-- Dependencies: 317
-- Name: t_mobiliario_empresa_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_mobiliario_empresa_uid_seq OWNED BY app.t_mobiliario_empresa.uid;


--
-- TOC entry 318 (class 1259 OID 903963)
-- Name: t_mobiliario_servicos; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_mobiliario_servicos (
    cmc character varying(255) NOT NULL,
    num_serv character varying(255) NOT NULL,
    servicos character varying(50),
    ds_servicos character varying(255),
    status character varying(30),
    uid integer NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 319 (class 1259 OID 903970)
-- Name: t_mobiliario_servicos_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_mobiliario_servicos_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5485 (class 0 OID 0)
-- Dependencies: 319
-- Name: t_mobiliario_servicos_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_mobiliario_servicos_uid_seq OWNED BY app.t_mobiliario_servicos.uid;


--
-- TOC entry 321 (class 1259 OID 903982)
-- Name: t_pack_layer; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_pack_layer (
    uid integer DEFAULT nextval('app.t_layer_group_uid_seq'::regclass) NOT NULL,
    fuid_pack integer NOT NULL,
    name_pack character varying(255) NOT NULL,
    ds_enable character varying(255),
    ds_name character varying(255),
    ds_type character varying(255),
    ws_name character varying(255),
    type character varying(255),
    srs character varying(255),
    projection_policy character varying(255),
    enabled character varying(255),
    name character varying(255),
    title character varying(255),
    native_name character varying(255),
    prefixed_name character varying(255) DEFAULT nextval('app.t_layer_group_uid_seq'::regclass) NOT NULL,
    abstract character varying(255),
    ordem_layer integer,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 322 (class 1259 OID 903991)
-- Name: t_tema_pack; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_tema_pack (
    uid integer NOT NULL,
    pack character varying(255),
    fuid_pack integer,
    tema character varying(255),
    fuid_tema integer,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    "order" integer
);


--
-- TOC entry 323 (class 1259 OID 903998)
-- Name: t_pack_tema_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_pack_tema_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5486 (class 0 OID 0)
-- Dependencies: 323
-- Name: t_pack_tema_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_pack_tema_uid_seq OWNED BY app.t_tema_pack.uid;


--
-- TOC entry 320 (class 1259 OID 903972)
-- Name: t_pack_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_pack_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5487 (class 0 OID 0)
-- Dependencies: 320
-- Name: t_pack_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_pack_uid_seq OWNED BY app.t_pack.uid;


--
-- TOC entry 324 (class 1259 OID 904000)
-- Name: t_renum_logradouros; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_renum_logradouros (
    cod_log_geo double precision NOT NULL,
    nome character varying(254),
    codgeo_ini character varying(254),
    codgeo_fim character varying(254),
    nome_ini character varying(254),
    nome_fim character varying(254),
    qt_lote integer,
    qt_mantidos integer,
    qt_alterados integer,
    uid bigint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 325 (class 1259 OID 904007)
-- Name: t_renum_logradouros_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_renum_logradouros_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5488 (class 0 OID 0)
-- Dependencies: 325
-- Name: t_renum_logradouros_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_renum_logradouros_uid_seq OWNED BY app.t_renum_logradouros.uid;


--
-- TOC entry 326 (class 1259 OID 904009)
-- Name: t_renum_planilha; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_renum_planilha (
    cod_log_geo double precision,
    lado character varying(10),
    codgis character varying(100),
    cruzamento character varying(255),
    inscricao character varying(255),
    fx_min integer,
    fx_max integer,
    div_min character varying(1),
    div_max character varying(1),
    num_minimo bigint,
    num_medio bigint,
    num_maximo bigint,
    num_cad bigint,
    div_num_cad character varying(1),
    cod_log_cad character varying(10),
    cod_log_oficial character varying(10),
    tipo_const_cad character varying(50),
    compl_cad character varying(255),
    qt_unid_cad integer,
    num_atribuido bigint,
    compl_atribuido character varying(255),
    status_num character varying(50),
    nome character varying(254),
    codgeo_ini character varying(254),
    codgeo_fim character varying(254),
    nome_ini character varying(254),
    nome_fim character varying(254),
    atribuir_letra character varying(255),
    num_letra bigint,
    entrega character varying(25),
    ident bigint,
    div_num_atrib character varying(1),
    revisado character varying(255),
    num_nao_visivel character varying(255),
    teste character varying(255),
    ordem bigint,
    posicao integer,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint NOT NULL
);


--
-- TOC entry 327 (class 1259 OID 904016)
-- Name: t_renum_planilha_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_renum_planilha_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5489 (class 0 OID 0)
-- Dependencies: 327
-- Name: t_renum_planilha_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_renum_planilha_uid_seq OWNED BY app.t_renum_planilha.uid;


--
-- TOC entry 328 (class 1259 OID 904018)
-- Name: t_reuniao; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_reuniao (
    uid bigint NOT NULL,
    guid text,
    shd_data text,
    shd_hora text,
    emails text,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 5490 (class 0 OID 0)
-- Dependencies: 328
-- Name: TABLE t_reuniao; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_reuniao IS 'Tabela que registra o agendamento de reuniões';


--
-- TOC entry 5491 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.guid; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.guid IS 'Nome da sala para acesso ao Jitsi';


--
-- TOC entry 5492 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.shd_data; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.shd_data IS 'Data agendada';


--
-- TOC entry 5493 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.shd_hora; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.shd_hora IS 'Hora agendada';


--
-- TOC entry 5494 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.emails; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.emails IS 'E-mail dos participantes para videoconferencia.';


--
-- TOC entry 5495 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.md_add IS 'Data criação';


--
-- TOC entry 5496 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.md_alt IS 'Data alteração';


--
-- TOC entry 5497 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.md_usr IS 'Id usuário criação';


--
-- TOC entry 5498 (class 0 OID 0)
-- Dependencies: 328
-- Name: COLUMN t_reuniao.md_usr_last; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_reuniao.md_usr_last IS 'Id usuário ultima alteração.';


--
-- TOC entry 329 (class 1259 OID 904025)
-- Name: t_reuniao_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_reuniao_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5499 (class 0 OID 0)
-- Dependencies: 329
-- Name: t_reuniao_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_reuniao_uid_seq OWNED BY app.t_reuniao.uid;


--
-- TOC entry 330 (class 1259 OID 904027)
-- Name: t_sistema_bool; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_sistema_bool (
    uid smallint NOT NULL,
    numero smallint,
    texto character varying(5),
    abrev character varying(5),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 331 (class 1259 OID 904034)
-- Name: t_sistema_bool_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_sistema_bool_uid_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5500 (class 0 OID 0)
-- Dependencies: 331
-- Name: t_sistema_bool_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_sistema_bool_uid_seq OWNED BY app.t_sistema_bool.uid;


--
-- TOC entry 332 (class 1259 OID 904036)
-- Name: t_sistema_demanda; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_sistema_demanda (
    demanda text,
    posicao text,
    millenio text,
    prefeitura text,
    uid integer NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 333 (class 1259 OID 904043)
-- Name: t_sistema_demanda_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_sistema_demanda_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5501 (class 0 OID 0)
-- Dependencies: 333
-- Name: t_sistema_demanda_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_sistema_demanda_uid_seq OWNED BY app.t_sistema_demanda.uid;


--
-- TOC entry 334 (class 1259 OID 904045)
-- Name: t_stage_manager; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_stage_manager (
    tk uuid NOT NULL,
    completed boolean DEFAULT false,
    tag text NOT NULL,
    uid bigint NOT NULL,
    index smallint NOT NULL,
    stage smallint NOT NULL,
    action smallint NOT NULL,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text NOT NULL,
    jb_attr jsonb NOT NULL,
    md_usr_last text,
    fuid bigint
);


--
-- TOC entry 5502 (class 0 OID 0)
-- Dependencies: 334
-- Name: TABLE t_stage_manager; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_stage_manager IS 'Tabela de Controle de Processo de Desmenbramento';


--
-- TOC entry 5503 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.tk; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.tk IS 'Identificador da transação';


--
-- TOC entry 5504 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.completed; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.completed IS 'Indicador de término da ação';


--
-- TOC entry 5505 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.tag; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.tag IS 'Nome da tabela envolvida';


--
-- TOC entry 5506 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.uid; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.uid IS 'Identificador da feature envolvida';


--
-- TOC entry 5507 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.index; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.index IS 'Identificador de order da pilha';


--
-- TOC entry 5508 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.stage; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.stage IS 'Identificador do estágio';


--
-- TOC entry 5509 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.action; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.action IS 'Indicador do tipo de ação';


--
-- TOC entry 5510 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.md_add IS 'Data de criação';


--
-- TOC entry 5511 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.md_alt IS 'Data de alteração';


--
-- TOC entry 5512 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.md_usr IS 'Id do usuário que criou o registro';


--
-- TOC entry 5513 (class 0 OID 0)
-- Dependencies: 334
-- Name: COLUMN t_stage_manager.jb_attr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_stage_manager.jb_attr IS 'Atributos da feature envolvida';


--
-- TOC entry 335 (class 1259 OID 904053)
-- Name: t_tema; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_tema (
    uid smallint NOT NULL,
    tema character varying(255),
    descricao character varying(255),
    ordem_tema integer,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    "order" integer
);


--
-- TOC entry 336 (class 1259 OID 904060)
-- Name: t_tema_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_tema_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


--
-- TOC entry 5514 (class 0 OID 0)
-- Dependencies: 336
-- Name: t_tema_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_tema_uid_seq OWNED BY app.t_tema.uid;


--
-- TOC entry 337 (class 1259 OID 904078)
-- Name: t_users; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_users (
    uid bigint NOT NULL,
    fuid_groups bigint,
    name text NOT NULL,
    alias_name text,
    pass text,
    token text,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    email text,
    ativo smallint DEFAULT 0,
    fuid bigint,
    apikey text,
    reset_token text,
    reset_date timestamp(6) without time zone,
    user_type text,
    mostrar_popup character varying(255),
    tipo character varying(10)
);


--
-- TOC entry 5515 (class 0 OID 0)
-- Dependencies: 337
-- Name: TABLE t_users; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.t_users IS 'Tabela de usuarios para controle de acesso ao sistema';


--
-- TOC entry 5516 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.name; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.name IS 'Nome do usuário';


--
-- TOC entry 5517 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.alias_name; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.alias_name IS 'Nome para exibição ao realizar o login';


--
-- TOC entry 5518 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.md_add IS 'Data de criação';


--
-- TOC entry 5519 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.md_alt IS 'Data de alteração';


--
-- TOC entry 5520 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.md_usr IS 'Id usuário criação';


--
-- TOC entry 5521 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.md_usr_last; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.md_usr_last IS 'Id usuário ultima alteração';


--
-- TOC entry 5522 (class 0 OID 0)
-- Dependencies: 337
-- Name: COLUMN t_users.ativo; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.t_users.ativo IS 'Define se usuário está ativo ou não para acessar o sistema.';


--
-- TOC entry 338 (class 1259 OID 904086)
-- Name: t_users_groups; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_users_groups (
    fuid_users bigint NOT NULL,
    fuid_groups bigint NOT NULL,
    name_groups text,
    name_users text,
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint NOT NULL
);


--
-- TOC entry 339 (class 1259 OID 904093)
-- Name: t_users_groups_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_users_groups_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5523 (class 0 OID 0)
-- Dependencies: 339
-- Name: t_users_groups_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_users_groups_uid_seq OWNED BY app.t_users_groups.uid;


--
-- TOC entry 340 (class 1259 OID 904095)
-- Name: t_users_log; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.t_users_log (
    uid bigint NOT NULL,
    fuid bigint,
    action text,
    description text,
    status_action text,
    md_add timestamp without time zone,
    md_alt timestamp without time zone,
    "table" text,
    md_user bigint,
    md_username text,
    md_usr text,
    md_usr_last text
);


--
-- TOC entry 341 (class 1259 OID 904101)
-- Name: t_users_log_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_users_log_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5524 (class 0 OID 0)
-- Dependencies: 341
-- Name: t_users_log_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_users_log_uid_seq OWNED BY app.t_users_log.uid;


--
-- TOC entry 342 (class 1259 OID 904103)
-- Name: t_users_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.t_users_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5525 (class 0 OID 0)
-- Dependencies: 342
-- Name: t_users_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.t_users_uid_seq OWNED BY app.t_users.uid;


--
-- TOC entry 343 (class 1259 OID 904105)
-- Name: tbl_groups; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.tbl_groups (
    uid bigint DEFAULT nextval('app.t_groups_uid_seq'::regclass) NOT NULL,
    name text,
    jbrules jsonb,
    md_add timestamp(6) with time zone DEFAULT now(),
    md_alt timestamp(6) with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    modulo character varying(255),
    permissao character varying(255),
    tipo character varying(255)
);


--
-- TOC entry 5526 (class 0 OID 0)
-- Dependencies: 343
-- Name: TABLE tbl_groups; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON TABLE app.tbl_groups IS 'Tabela com os grupos com os tipos de permissão de acesso';


--
-- TOC entry 5527 (class 0 OID 0)
-- Dependencies: 343
-- Name: COLUMN tbl_groups.jbrules; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.tbl_groups.jbrules IS 'Um campo do tipo jsonb, onde armazenaremos algum json contendo os modulos e oque pode ser feito, um exemplo: {"uid":1, "name":"Administradores", md_{...}: "...", "jbRules": [ { module:"Sefin", police: CRUD - "onde C: enable to create, R: enable to retrieve, U: enable to update, D: enable to delete", } ]}';


--
-- TOC entry 5528 (class 0 OID 0)
-- Dependencies: 343
-- Name: COLUMN tbl_groups.md_add; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.tbl_groups.md_add IS 'Data de criação';


--
-- TOC entry 5529 (class 0 OID 0)
-- Dependencies: 343
-- Name: COLUMN tbl_groups.md_alt; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.tbl_groups.md_alt IS 'Data de alteração';


--
-- TOC entry 5530 (class 0 OID 0)
-- Dependencies: 343
-- Name: COLUMN tbl_groups.md_usr; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.tbl_groups.md_usr IS 'Id Usuário criação.';


--
-- TOC entry 5531 (class 0 OID 0)
-- Dependencies: 343
-- Name: COLUMN tbl_groups.md_usr_last; Type: COMMENT; Schema: app; Owner: -
--

COMMENT ON COLUMN app.tbl_groups.md_usr_last IS 'Id usuário ultima alteração';


--
-- TOC entry 344 (class 1259 OID 904113)
-- Name: tbl_pesq_rapida; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.tbl_pesq_rapida (
    uid integer NOT NULL,
    pesquisa character varying(255)
);


--
-- TOC entry 345 (class 1259 OID 904116)
-- Name: tbl_pesq_rapida_permissao; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.tbl_pesq_rapida_permissao (
    uid integer NOT NULL,
    item character varying(255),
    grupo character varying(255)
);


--
-- TOC entry 346 (class 1259 OID 904122)
-- Name: tbl_pesq_rapida_permissao_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.tbl_pesq_rapida_permissao_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5532 (class 0 OID 0)
-- Dependencies: 346
-- Name: tbl_pesq_rapida_permissao_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.tbl_pesq_rapida_permissao_uid_seq OWNED BY app.tbl_pesq_rapida_permissao.uid;


--
-- TOC entry 347 (class 1259 OID 904124)
-- Name: tbl_pesq_rapida_uid_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.tbl_pesq_rapida_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5533 (class 0 OID 0)
-- Dependencies: 347
-- Name: tbl_pesq_rapida_uid_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.tbl_pesq_rapida_uid_seq OWNED BY app.tbl_pesq_rapida.uid;


--
-- TOC entry 348 (class 1259 OID 904126)
-- Name: tbl_status_certidao_id_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.tbl_status_certidao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5534 (class 0 OID 0)
-- Dependencies: 348
-- Name: tbl_status_certidao_id_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.tbl_status_certidao_id_seq OWNED BY app.t_cius_status_certidao.id;


--
-- TOC entry 349 (class 1259 OID 904128)
-- Name: tbl_uso_geral_id_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.tbl_uso_geral_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5535 (class 0 OID 0)
-- Dependencies: 349
-- Name: tbl_uso_geral_id_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.tbl_uso_geral_id_seq OWNED BY app.t_cius_uso_geral.id;


--
-- TOC entry 350 (class 1259 OID 904130)
-- Name: uid_tdirfoto_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_tdirfoto_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 351 (class 1259 OID 904132)
-- Name: tdirfoto; Type: TABLE; Schema: app; Owner: -
--

CREATE TABLE app.tdirfoto (
    id integer NOT NULL,
    fotos character varying(50),
    nivel character varying(255),
    arquivo character varying(255),
    ic character varying(50),
    chave character varying(50),
    cadastro character varying(50),
    end_fisico character varying(255),
    end_url character varying(255),
    entrega character varying(255),
    md_add timestamp with time zone DEFAULT now(),
    md_alt timestamp with time zone,
    md_usr text,
    md_usr_last text,
    fuid bigint,
    uid bigint DEFAULT nextval('app.uid_tdirfoto_pk_seq'::regclass) NOT NULL
);


--
-- TOC entry 352 (class 1259 OID 904140)
-- Name: tdirfoto_id_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.tdirfoto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


--
-- TOC entry 5536 (class 0 OID 0)
-- Dependencies: 352
-- Name: tdirfoto_id_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.tdirfoto_id_seq OWNED BY app.tdirfoto.id;


--
-- TOC entry 353 (class 1259 OID 904142)
-- Name: uid_t_cius_consulta_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_cius_consulta_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5537 (class 0 OID 0)
-- Dependencies: 353
-- Name: uid_t_cius_consulta_pk_seq; Type: SEQUENCE OWNED BY; Schema: app; Owner: -
--

ALTER SEQUENCE app.uid_t_cius_consulta_pk_seq OWNED BY app.t_cius_consulta.uid;


--
-- TOC entry 354 (class 1259 OID 904144)
-- Name: uid_t_estim_area_const_old_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_estim_area_const_old_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 355 (class 1259 OID 904146)
-- Name: uid_t_renum_planilha_pk_seq; Type: SEQUENCE; Schema: app; Owner: -
--

CREATE SEQUENCE app.uid_t_renum_planilha_pk_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 356 (class 1259 OID 904148)
-- Name: view_acesso; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_acesso AS
 SELECT acesso_audit.action AS "Ação",
    acesso_audit.ip AS "IP",
    acesso_audit."user" AS "Usuário",
    acesso_audit."table" AS "Tabela",
    "right"((acesso_audit.datetime)::text, 8) AS "Hora",
    "left"((acesso_audit.datetime)::text, 10) AS "Data",
    t_users_groups.name_groups AS "Grupo"
   FROM (app.acesso_audit
     LEFT JOIN app.t_users_groups ON (((acesso_audit."user")::text = t_users_groups.name_users)))
  WHERE ((((acesso_audit.action)::text = 'login'::text) OR ((acesso_audit.action)::text = 'logout'::text) OR ((acesso_audit.action)::text = 'failed login'::text) OR ((acesso_audit.action)::text = 'add'::text) OR ((acesso_audit.action)::text = 'delete'::text) OR ((acesso_audit.action)::text = 'edit'::text) OR ((acesso_audit.action)::text = 'change password'::text)) AND (acesso_audit.datetime > '2024-01-01 00:00:00'::timestamp without time zone) AND ((acesso_audit."user")::text <> 'admin'::text) AND ((acesso_audit."user")::text <> ''::text) AND ((acesso_audit."user")::text <> ' '::text))
  ORDER BY acesso_audit."user", acesso_audit.datetime, ("right"((acesso_audit.datetime)::text, 8));


--
-- TOC entry 357 (class 1259 OID 904153)
-- Name: view_acesso_audit; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_acesso_audit AS
 WITH base AS (
         SELECT aa.action,
            aa.ip,
            aa."user",
            aa."table",
            aa.datetime,
                CASE
                    WHEN ((aa."user")::text = 'convidado'::text) THEN 'Publico'::text
                    ELSE g.name_groups
                END AS name_groups
           FROM (app.acesso_audit aa
             LEFT JOIN app.t_users_groups g ON (((aa."user")::text = g.name_users)))
          WHERE ((aa.datetime > '2024-01-01 00:00:00'::timestamp without time zone) AND (COALESCE(btrim((aa."user")::text), ''::text) <> ''::text) AND ((aa."user")::text <> 'admin'::text) AND ((aa.action)::text = ANY (ARRAY[('login'::character varying)::text, ('logout'::character varying)::text, ('failed login'::character varying)::text, ('add'::character varying)::text, ('delete'::character varying)::text, ('edit'::character varying)::text, ('change password'::character varying)::text])))
        ), logins_filtrados AS (
         SELECT b.action,
            b.ip,
            b."user",
            b."table",
            b.datetime,
            b.name_groups
           FROM ( SELECT b_1.action,
                    b_1.ip,
                    b_1."user",
                    b_1."table",
                    b_1.datetime,
                    b_1.name_groups,
                    lag(b_1.datetime) OVER (PARTITION BY b_1."user", b_1.ip, b_1.name_groups, b_1.action ORDER BY b_1.datetime) AS dt_anterior
                   FROM base b_1
                  WHERE ((b_1.action)::text = 'login'::text)) b
          WHERE ((b.dt_anterior IS NULL) OR ((b.datetime - b.dt_anterior) > '00:02:00'::interval))
        ), outros_eventos AS (
         SELECT base.action,
            base.ip,
            base."user",
            base."table",
            base.datetime,
            base.name_groups
           FROM base
          WHERE ((base.action)::text <> 'login'::text)
        )
 SELECT logins_filtrados.action AS "Ação",
    logins_filtrados.ip AS "IP",
    logins_filtrados."user" AS "Usuário",
    logins_filtrados."table" AS "Tabela",
    (date_trunc('second'::text, logins_filtrados.datetime))::time without time zone AS "Hora",
    (logins_filtrados.datetime)::date AS "Data",
    logins_filtrados.name_groups AS "Grupo"
   FROM logins_filtrados
UNION ALL
 SELECT outros_eventos.action AS "Ação",
    outros_eventos.ip AS "IP",
    outros_eventos."user" AS "Usuário",
    outros_eventos."table" AS "Tabela",
    (date_trunc('second'::text, outros_eventos.datetime))::time without time zone AS "Hora",
    (outros_eventos.datetime)::date AS "Data",
    outros_eventos.name_groups AS "Grupo"
   FROM outros_eventos
  ORDER BY 6 DESC, 5 DESC;


--
-- TOC entry 358 (class 1259 OID 904158)
-- Name: view_atributos; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_atributos AS
 SELECT columns.table_name,
    columns.column_name
   FROM information_schema.columns
  WHERE ((columns.table_schema)::text = 'app'::text)
  ORDER BY columns.table_name;


--
-- TOC entry 359 (class 1259 OID 904162)
-- Name: view_benfeitorias; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_benfeitorias AS
 SELECT DISTINCT t_imobiliario_default.benfeitorias
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.benfeitorias;


--
-- TOC entry 360 (class 1259 OID 904167)
-- Name: view_caracteristicas_imovel; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_caracteristicas_imovel AS
 SELECT t_imobiliario_default.codred,
    t_imobiliario_default.inscricao,
    replace((t_imobiliario_default.inscricao)::text, '.'::text, ''::text) AS insc_num,
    t_imobiliario_default.chave_lote,
    replace((t_imobiliario_default.chave_lote)::text, '.'::text, ''::text) AS chave_num,
    t_imobiliario_default.cod_face,
    t_imobiliario_default.face,
    t_imobiliario_default.zona_fiscal,
    t_imobiliario_default.zoneamento,
    t_imobiliario_default.data_implantacao,
    t_imobiliario_default.data_ultima_atualizacao,
    t_imobiliario_default.usuario_alteracao,
    t_imobiliario_default.matricula,
    t_imobiliario_default.habitese,
    t_imobiliario_default.data_habitese,
    t_imobiliario_default.situacao_cadastral,
    t_imobiliario_default.cod_proprietario,
    t_imobiliario_default.proprietario,
    t_imobiliario_default.rg_proprietario,
    t_imobiliario_default.cpf_proprietario,
    t_imobiliario_default.cnpj_proprietario,
    t_imobiliario_default.cod_compromissario,
    t_imobiliario_default.compromissario,
    t_imobiliario_default.rg_compromissario,
    t_imobiliario_default.cpf_compromissario,
    t_imobiliario_default.cnpj_compromissario,
    t_imobiliario_default.cod_logradouro,
    t_imobiliario_default.logradouro,
    t_imobiliario_default.numero,
    t_imobiliario_default.numero_anterior,
    t_imobiliario_default.complemento,
    t_imobiliario_default.cod_bairro,
    t_imobiliario_default.bairro,
    t_imobiliario_default.cep,
    (((t_imobiliario_default.logradouro)::text || ', '::text) || (t_imobiliario_default.numero)::text) AS endereco,
    t_imobiliario_default.cod_loteamento,
    t_imobiliario_default.loteamento,
    t_imobiliario_default.quadra_loteam,
    t_imobiliario_default.lote_loteam,
    t_imobiliario_default.ent_logradouro,
    t_imobiliario_default.ent_numero,
    t_imobiliario_default.ent_complemento,
    t_imobiliario_default.ent_bairro,
    t_imobiliario_default.ent_cidade,
    t_imobiliario_default.ent_uf,
    t_imobiliario_default.ent_cep,
    t_imobiliario_default.cobranca,
    t_imobiliario_default.categ_propriedade,
    t_imobiliario_default.area_terreno,
    t_imobiliario_default.fracao_ideal,
    t_imobiliario_default.testada_princ,
    t_imobiliario_default.soma_testadas,
    t_imobiliario_default.qt_testadas,
    t_imobiliario_default.area_ocupada,
    t_imobiliario_default.ocupacao,
    t_imobiliario_default.uso_terreno,
    t_imobiliario_default.situacao,
    t_imobiliario_default.topografia,
    t_imobiliario_default.consistencia_solo,
    t_imobiliario_default.forma,
    t_imobiliario_default.benfeitorias,
    t_imobiliario_default.condominio,
    t_imobiliario_default.vagas_cobertas,
    t_imobiliario_default.vagas_descobertas,
    t_imobiliario_default.id_edificacao,
    t_imobiliario_default.area_const_princ,
    t_imobiliario_default.area_depend,
    t_imobiliario_default.area_garagem,
    t_imobiliario_default.area_cobert,
    t_imobiliario_default.area_pisc,
    t_imobiliario_default.area_const_total,
    t_imobiliario_default.area_const_lote,
    t_imobiliario_default.qt_pavimentos,
    t_imobiliario_default.area_privativa,
    t_imobiliario_default.area_comum,
    t_imobiliario_default.tipo_const,
    t_imobiliario_default.padrao_const,
    t_imobiliario_default.conservacao,
    t_imobiliario_default.posicao_const,
    t_imobiliario_default.situacao_const,
    t_imobiliario_default.edicula,
    t_imobiliario_default.regime_ocupacao,
    t_imobiliario_default.categoria_ocupacao,
    t_imobiliario_default.elevador,
    t_imobiliario_default.estrutura,
    t_imobiliario_default.cobertura,
    t_imobiliario_default.fachada,
    t_imobiliario_default.pintura_ext,
    t_imobiliario_default.pintura_int,
    t_imobiliario_default.revest_int_social,
    t_imobiliario_default.revest_int_servico,
    t_imobiliario_default.revestimento_ext,
    t_imobiliario_default.forro_social,
    t_imobiliario_default.forro_servico,
    t_imobiliario_default.pintura_forro,
    t_imobiliario_default.piso_social,
    t_imobiliario_default.piso_servico,
    t_imobiliario_default.piso_externo,
    t_imobiliario_default.portas,
    t_imobiliario_default.esq_janelas,
    t_imobiliario_default.esq_vitros,
    t_imobiliario_default.esq_pintura,
    t_imobiliario_default.inst_eletrica,
    t_imobiliario_default.inst_sanitaria,
    t_imobiliario_default.piscina,
    t_imobiliario_default.pe_direito,
    t_imobiliario_default.vao,
    t_imobiliario_default.recuo,
    t_imobiliario_default.beiral,
    t_imobiliario_default.data_construcao,
    t_imobiliario_default.qt_edificacoes,
    t_imobiliario_default.acesso,
    t_imobiliario_default.desconto,
    t_imobiliario_default.observacao,
    t_imobiliario_default.agua,
    t_imobiliario_default.luz,
    t_imobiliario_default.pavimentacao,
    t_imobiliario_default.meio_fio,
    t_imobiliario_default.esgoto,
    t_imobiliario_default.coleta_lixo,
    t_imobiliario_default.telefone,
    t_imobiliario_default.ilum_publica,
    t_imobiliario_default.aguas_pluviais,
    t_imobiliario_default.status,
    (t_imobiliario_default.codred)::text AS cdc,
    t_imobiliario_default.md_add,
    t_imobiliario_default.md_alt,
    t_imobiliario_default.md_usr,
    t_imobiliario_default.md_usr_last,
    t_imobiliario_default.fuid,
    t_imobiliario_default.uid
   FROM app.t_imobiliario_default;


--
-- TOC entry 361 (class 1259 OID 904172)
-- Name: view_categ_propriedade; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_categ_propriedade AS
 SELECT DISTINCT t_imobiliario_default.categ_propriedade
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.categ_propriedade;


--
-- TOC entry 362 (class 1259 OID 904177)
-- Name: view_cobranca; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_cobranca AS
 SELECT DISTINCT t_imobiliario_default.cobranca
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.cobranca;


--
-- TOC entry 363 (class 1259 OID 904182)
-- Name: view_conservacao; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_conservacao AS
 SELECT DISTINCT t_imobiliario_default.conservacao
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.conservacao;


--
-- TOC entry 364 (class 1259 OID 904187)
-- Name: view_geometrias; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_geometrias AS
 SELECT geometry_columns.f_table_name,
    geometry_columns.f_geometry_column,
    geometry_columns.f_table_schema
   FROM public.geometry_columns
  WHERE (geometry_columns.f_table_schema = 'app'::name)
  ORDER BY geometry_columns.f_table_name;


--
-- TOC entry 365 (class 1259 OID 904191)
-- Name: view_gestao_inmap; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_gestao_inmap AS
 SELECT acesso_audit.action AS "Ação",
    acesso_audit."user" AS "Usuário",
    acesso_audit."table" AS "Tabela",
    "right"((acesso_audit.datetime)::text, 8) AS "Hora",
    "left"((acesso_audit.datetime)::text, 10) AS "Data",
    t_users_groups.name_groups AS "Grupo"
   FROM (app.acesso_audit
     LEFT JOIN app.t_users_groups ON (((acesso_audit."user")::text = t_users_groups.name_users)))
  WHERE ((((acesso_audit.action)::text = 'login'::text) OR ((acesso_audit.action)::text = 'logout'::text) OR ((acesso_audit.action)::text = 'failed login'::text) OR ((acesso_audit.action)::text = 'add'::text) OR ((acesso_audit.action)::text = 'delete'::text) OR ((acesso_audit.action)::text = 'edit'::text) OR ((acesso_audit.action)::text = 'change password'::text)) AND (acesso_audit.datetime > '2024-01-01 00:00:00'::timestamp without time zone) AND ((acesso_audit."user")::text <> 'admin'::text) AND ((acesso_audit."user")::text <> ''::text) AND ((acesso_audit."user")::text <> ' '::text) AND ((acesso_audit."table")::text <> 'app.t_users'::text))
  ORDER BY acesso_audit."user", acesso_audit.datetime, ("right"((acesso_audit.datetime)::text, 8));


--
-- TOC entry 366 (class 1259 OID 904196)
-- Name: view_layers_access; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_layers_access AS
 SELECT t_pack_layer_grupo.name_group,
        CASE
            WHEN ("left"((t_pack_layer_grupo.name_tema)::text, 5) = 'Mapas'::text) THEN 'Mapas Iniciais'::character varying
            ELSE t_pack_layer_grupo.name_tema
        END AS name_categ,
        CASE
            WHEN ("left"((t_pack_layer.name_pack)::text, 5) = 'Mapas'::text) THEN 'Mapas'::character varying
            ELSE t_pack_layer.name_pack
        END AS name_pack,
    t_pack_layer.ds_enable,
    t_pack_layer.ds_name,
    t_pack_layer.ds_type,
    t_pack_layer.ws_name,
    t_pack_layer.type,
    t_pack_layer.srs,
    t_pack_layer.projection_policy,
    t_pack_layer.enabled,
    t_pack_layer.name,
    t_pack_layer.title,
    t_pack_layer.native_name,
    t_pack_layer.prefixed_name,
    COALESCE(t_tema.ordem_tema, 0) AS ordem_categ,
    COALESCE(t_pack.ordem_pack, 0) AS ordem_pack,
    COALESCE(t_pack_layer.ordem_layer, 0) AS ordem_layer
   FROM (((app.t_pack_layer_grupo
     LEFT JOIN app.t_pack_layer ON ((t_pack_layer_grupo.fuid_pack = t_pack_layer.fuid_pack)))
     LEFT JOIN app.t_tema ON (((t_pack_layer_grupo.name_tema)::text = (t_tema.tema)::text)))
     LEFT JOIN app.t_pack ON ((t_pack_layer_grupo.fuid_pack = t_pack.uid)))
  ORDER BY t_pack_layer_grupo.name_group, t_tema.ordem_tema, t_pack.ordem_pack, t_pack_layer.title;


--
-- TOC entry 367 (class 1259 OID 904201)
-- Name: view_layers_detalhes; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_layers_detalhes AS
 SELECT DISTINCT
        CASE
            WHEN ("left"((t_pack_layer_grupo.name_tema)::text, 5) = 'Mapas'::text) THEN 'Mapas Base'::character varying
            ELSE t_pack_layer_grupo.name_tema
        END AS name_categ,
        CASE
            WHEN ("left"((t_pack_layer.name_pack)::text, 5) = 'Mapas'::text) THEN 'Mapas'::character varying
            ELSE t_pack_layer.name_pack
        END AS name_pack,
    t_pack_layer.ds_enable,
    t_pack_layer.ds_name,
    t_pack_layer.ds_type,
    t_pack_layer.ws_name,
    t_pack_layer.type,
    t_pack_layer.srs,
    t_pack_layer.enabled,
    t_pack_layer.name,
    t_pack_layer.title,
    t_pack_layer.native_name,
    t_pack_layer.prefixed_name
   FROM (((app.t_pack_layer_grupo
     LEFT JOIN app.t_pack_layer ON ((t_pack_layer_grupo.fuid_pack = t_pack_layer.fuid_pack)))
     LEFT JOIN app.t_tema ON (((t_pack_layer_grupo.name_tema)::text = (t_tema.tema)::text)))
     LEFT JOIN app.t_pack ON ((t_pack_layer_grupo.fuid_pack = t_pack.uid)))
  WHERE (t_pack_layer.name_pack IS NOT NULL)
  ORDER BY t_pack_layer.title;


--
-- TOC entry 368 (class 1259 OID 904220)
-- Name: view_ocupacao; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_ocupacao AS
 SELECT DISTINCT t_imobiliario_default.ocupacao
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.ocupacao;


--
-- TOC entry 369 (class 1259 OID 904225)
-- Name: view_padrao_const; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_padrao_const AS
 SELECT DISTINCT t_imobiliario_default.padrao_const
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.padrao_const;


--
-- TOC entry 370 (class 1259 OID 904230)
-- Name: view_padrao_const_new; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_padrao_const_new AS
 SELECT DISTINCT t_imobiliario_recad.cpadraonew
   FROM app.t_imobiliario_recad
  WHERE (t_imobiliario_recad.cpadraonew IS NOT NULL)
  ORDER BY t_imobiliario_recad.cpadraonew;


--
-- TOC entry 371 (class 1259 OID 904250)
-- Name: view_situacao; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_situacao AS
 SELECT DISTINCT t_imobiliario_default.situacao
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.situacao;


--
-- TOC entry 372 (class 1259 OID 904263)
-- Name: view_tabelas_alfa; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_tabelas_alfa AS
 SELECT pg_tables.schemaname AS esquema,
    pg_tables.tablename AS tabela,
    pg_tables.tableowner AS proprietario
   FROM (pg_tables
     LEFT JOIN public.geometry_columns ON ((pg_tables.tablename = geometry_columns.f_table_name)))
  WHERE ((pg_tables.schemaname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name, 'pg_toast'::name])) AND (pg_tables.schemaname = 'app'::name) AND (geometry_columns.f_geometry_column IS NULL) AND (pg_tables.tablename !~~ 'TBL%'::text) AND (pg_tables.tablename !~~ 'acesso%'::text) AND (pg_tables.tablename !~~ 't_pack%'::text) AND (pg_tables.tablename !~~ 't_cius%'::text) AND (pg_tables.tablename !~~ 't_depart%'::text) AND (pg_tables.tablename !~~ 't_sistema%'::text) AND (pg_tables.tablename !~~ 't_tema%'::text) AND (pg_tables.tablename !~~ 't_user%'::text) AND (pg_tables.tablename !~~ 't_group%'::text) AND (pg_tables.tablename !~~ '%copy%'::text) AND (pg_tables.tablename !~~ '%anexos%'::text) AND (pg_tables.tablename !~~ 't_stage_manager%'::text) AND (pg_tables.tablename !~~ 't_reuniao%'::text) AND (pg_tables.tablename !~~ 't_memo_registro%'::text) AND (pg_tables.tablename !~~ '%mensagens%'::text) AND (pg_tables.tablename !~~ '%_old%'::text) AND (pg_tables.tablename !~~ 'tdirfoto%'::text))
  ORDER BY pg_tables.tablename;


--
-- TOC entry 373 (class 1259 OID 904268)
-- Name: view_tabela_atrib_alfa; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_tabela_atrib_alfa AS
 SELECT view_tabelas_alfa.tabela,
    view_atributos.column_name AS coluna
   FROM (app.view_tabelas_alfa
     LEFT JOIN app.view_atributos ON ((view_tabelas_alfa.tabela = (view_atributos.table_name)::name)))
  WHERE (((view_atributos.column_name)::text <> 'md_add'::text) AND ((view_atributos.column_name)::text <> 'md_alt'::text) AND ((view_atributos.column_name)::text <> 'md_usr'::text) AND ((view_atributos.column_name)::text <> 'md_usr_last'::text))
  ORDER BY view_tabelas_alfa.tabela, view_atributos.column_name;


--
-- TOC entry 374 (class 1259 OID 904272)
-- Name: view_tabela_atrib_geom; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_tabela_atrib_geom AS
 SELECT view_geometrias.f_table_name,
    view_atributos.column_name
   FROM (app.view_geometrias
     JOIN app.view_atributos ON (((view_geometrias.f_table_name)::text = (view_atributos.table_name)::text)))
  WHERE (((view_atributos.column_name)::text <> 'md_add'::text) AND ((view_atributos.column_name)::text <> 'md_alt'::text) AND ((view_atributos.column_name)::text <> 'md_usr'::text) AND ((view_atributos.column_name)::text <> 'md_usr_last'::text) AND ((view_atributos.column_name)::text <> 'geom'::text) AND ((view_atributos.column_name)::text !~~ '%shape_len%'::text) AND ((view_atributos.column_name)::text <> 'shape_area'::text) AND ((view_atributos.column_name)::text !~~ '%bservacao%'::text) AND ((view_atributos.column_name)::text !~~ '%buffer%'::text) AND ((view_atributos.column_name)::text !~~ '%descricao%'::text) AND ((view_atributos.column_name)::text !~~ '%fuid%'::text) AND ((view_atributos.column_name)::text !~~ '%uid%'::text) AND ((view_atributos.column_name)::text !~~ '%fid%'::text) AND ((view_atributos.column_name)::text !~~ 'tt_%'::text) AND ((view_atributos.column_name)::text !~~ 'length%'::text));


--
-- TOC entry 375 (class 1259 OID 904277)
-- Name: view_temas_access; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_temas_access AS
 SELECT t_depart_cadastro_grupo.fuid_group,
    t_depart_cadastro_grupo.name_group,
    t_depart_cadastro_grupo.fuid_depart,
    t_depart_cadastro_grupo.depart,
    t_depart_cadastro_grupo.fuid_cadastro,
    t_depart_tabela.cadastro,
    t_depart_tabela.descricao,
    t_depart_tabela.chave_cadastro,
    t_depart_tabela.camada,
    t_depart_tabela.chave_camada,
    t_depart_tabela.url_link,
    COALESCE((t_depart.ordem_depart)::integer, 0) AS ordem_depart,
    COALESCE(t_depart_tabela.ordem_cadastro, 0) AS ordem_cadastro
   FROM ((app.t_depart_cadastro_grupo
     LEFT JOIN app.t_depart ON ((t_depart_cadastro_grupo.fuid_depart = t_depart.uid)))
     LEFT JOIN app.t_depart_tabela ON ((t_depart_cadastro_grupo.fuid_cadastro = t_depart_tabela.uid)))
  ORDER BY t_depart_cadastro_grupo.fuid_group, COALESCE((t_depart.ordem_depart)::integer, 0), COALESCE(t_depart_tabela.ordem_cadastro, 0);


--
-- TOC entry 376 (class 1259 OID 904282)
-- Name: view_tipo_const; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_tipo_const AS
 SELECT DISTINCT t_imobiliario_default.tipo_const
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.tipo_const;


--
-- TOC entry 377 (class 1259 OID 904287)
-- Name: view_topografia; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_topografia AS
 SELECT DISTINCT t_imobiliario_default.topografia
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.topografia;


--
-- TOC entry 378 (class 1259 OID 904292)
-- Name: view_users_groups; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_users_groups AS
 SELECT t_groups.name,
    t_users_groups.name_users,
    t_users_groups.fuid_groups,
    t_users_groups.name_groups,
    t_groups.tipo
   FROM (app.t_users_groups
     JOIN app.t_groups ON ((t_users_groups.fuid_groups = t_groups.uid)))
  ORDER BY t_groups.name;


--
-- TOC entry 379 (class 1259 OID 904296)
-- Name: view_uso_terreno; Type: VIEW; Schema: app; Owner: -
--

CREATE VIEW app.view_uso_terreno AS
 SELECT DISTINCT t_imobiliario_default.uso_terreno
   FROM app.t_imobiliario_default
  ORDER BY t_imobiliario_default.uso_terreno;


--
-- TOC entry 4877 (class 2604 OID 904813)
-- Name: TBL_TEMP uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_TEMP" ALTER COLUMN uid SET DEFAULT nextval('app."TBL_TEMP_uid_seq"'::regclass);


--
-- TOC entry 4879 (class 2604 OID 904814)
-- Name: TBL_THEMES objectid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_THEMES" ALTER COLUMN objectid SET DEFAULT nextval('app."TBL_THEMES_objectid_seq"'::regclass);


--
-- TOC entry 4881 (class 2604 OID 904815)
-- Name: TBL_THEMES uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_THEMES" ALTER COLUMN uid SET DEFAULT nextval('app."TBL_THEMES_uid_seq"'::regclass);


--
-- TOC entry 4884 (class 2604 OID 904816)
-- Name: TBL_THEMETYPES uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_THEMETYPES" ALTER COLUMN uid SET DEFAULT nextval('app."TBL_THEMETYPES_uid_seq"'::regclass);


--
-- TOC entry 4886 (class 2604 OID 904817)
-- Name: acesso_audit id; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.acesso_audit ALTER COLUMN id SET DEFAULT nextval('app.acesso_audit_id_seq'::regclass);


--
-- TOC entry 4892 (class 2604 OID 904818)
-- Name: acesso_tbl_link_acesso ident; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.acesso_tbl_link_acesso ALTER COLUMN ident SET DEFAULT nextval('app.acesso_tbl_link_acesso_ident_seq'::regclass);


--
-- TOC entry 4898 (class 2604 OID 904883)
-- Name: geo_lote_31983 uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.geo_lote_31983 ALTER COLUMN uid SET DEFAULT nextval('app.geo_lote_31983_uid2_seq1'::regclass);


--
-- TOC entry 4899 (class 2604 OID 904937)
-- Name: t_anexos uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_anexos ALTER COLUMN uid SET DEFAULT nextval('app.t_anexos_ident_seq'::regclass);


--
-- TOC entry 4902 (class 2604 OID 904938)
-- Name: t_arquivos_anexos uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_arquivos_anexos ALTER COLUMN uid SET DEFAULT nextval('app.t_arquivos_anexos_uid_seq'::regclass);


--
-- TOC entry 4903 (class 2604 OID 904939)
-- Name: t_cius_atividades ordem; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_atividades ALTER COLUMN ordem SET DEFAULT nextval('app.t_cius_atividades_ordem_seq'::regclass);


--
-- TOC entry 4904 (class 2604 OID 904940)
-- Name: t_cius_atividades uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_atividades ALTER COLUMN uid SET DEFAULT nextval('app.t_cius_atividades_uid_seq'::regclass);


--
-- TOC entry 4895 (class 2604 OID 904941)
-- Name: t_cius_consulta id; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_consulta ALTER COLUMN id SET DEFAULT nextval('app.cons_uso_e_ocupacao_id_seq1'::regclass);


--
-- TOC entry 4897 (class 2604 OID 904942)
-- Name: t_cius_consulta uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_consulta ALTER COLUMN uid SET DEFAULT nextval('app.uid_t_cius_consulta_pk_seq'::regclass);


--
-- TOC entry 4913 (class 2604 OID 904943)
-- Name: t_cius_status_certidao id; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_status_certidao ALTER COLUMN id SET DEFAULT nextval('app.tbl_status_certidao_id_seq'::regclass);


--
-- TOC entry 4916 (class 2604 OID 904944)
-- Name: t_cius_uso_geral id; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_uso_geral ALTER COLUMN id SET DEFAULT nextval('app.tbl_uso_geral_id_seq'::regclass);


--
-- TOC entry 4919 (class 2604 OID 904945)
-- Name: t_depart uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart ALTER COLUMN uid SET DEFAULT nextval('app.t_depart_uid_seq'::regclass);


--
-- TOC entry 4921 (class 2604 OID 904946)
-- Name: t_depart_cadastro uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_cadastro ALTER COLUMN uid SET DEFAULT nextval('app.t_depart_cadastro_uid_seq'::regclass);


--
-- TOC entry 4923 (class 2604 OID 904947)
-- Name: t_depart_cadastro_grupo uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_cadastro_grupo ALTER COLUMN uid SET DEFAULT nextval('app.t_depart_cadastro_grupo_uid_seq'::regclass);


--
-- TOC entry 4925 (class 2604 OID 904948)
-- Name: t_depart_link_docs uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_link_docs ALTER COLUMN uid SET DEFAULT nextval('app.t_depart_link_docs_uid_seq'::regclass);


--
-- TOC entry 4928 (class 2604 OID 904949)
-- Name: t_estim_area_const uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_estim_area_const ALTER COLUMN uid SET DEFAULT nextval('app.t_estim_area_const_uid_seq'::regclass);


--
-- TOC entry 4930 (class 2604 OID 904950)
-- Name: t_estim_area_const_vistoria uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_estim_area_const_vistoria ALTER COLUMN uid SET DEFAULT nextval('app.t_estim_area_const_vistoria_uid_seq'::regclass);


--
-- TOC entry 4933 (class 2604 OID 904951)
-- Name: t_face_quadra uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_face_quadra ALTER COLUMN uid SET DEFAULT nextval('app.t_face_quadra_uid_seq'::regclass);


--
-- TOC entry 4936 (class 2604 OID 904952)
-- Name: t_groups uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_groups ALTER COLUMN uid SET DEFAULT nextval('app.t_groups_uid_seq'::regclass);


--
-- TOC entry 4938 (class 2604 OID 904953)
-- Name: t_groups_permissao uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_groups_permissao ALTER COLUMN uid SET DEFAULT nextval('app.t_groups_permissao_uid_seq'::regclass);


--
-- TOC entry 4875 (class 2604 OID 904954)
-- Name: t_imobiliario_default uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_imobiliario_default ALTER COLUMN uid SET DEFAULT nextval('app.t_imobiliario_default_uid_seq1'::regclass);


--
-- TOC entry 4939 (class 2604 OID 904955)
-- Name: t_imobiliario_recad uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_imobiliario_recad ALTER COLUMN uid SET DEFAULT nextval('app.t_imobiliario_recad_uid_seq'::regclass);


--
-- TOC entry 4943 (class 2604 OID 904956)
-- Name: t_logradouros uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_logradouros ALTER COLUMN uid SET DEFAULT nextval('app.t_logradouros_uid_seq'::regclass);


--
-- TOC entry 4948 (class 2604 OID 904957)
-- Name: t_mensagens uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mensagens ALTER COLUMN uid SET DEFAULT nextval('app.t_mensagens_uid_seq'::regclass);


--
-- TOC entry 4950 (class 2604 OID 904958)
-- Name: t_mensagens_anexos uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mensagens_anexos ALTER COLUMN uid SET DEFAULT nextval('app.t_mensagens_anexos_uid_seq'::regclass);


--
-- TOC entry 4952 (class 2604 OID 904959)
-- Name: t_metadados_print uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_metadados_print ALTER COLUMN uid SET DEFAULT nextval('app.t_metadados_print_uid_seq'::regclass);


--
-- TOC entry 4954 (class 2604 OID 904960)
-- Name: t_mobiliario_empresa uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mobiliario_empresa ALTER COLUMN uid SET DEFAULT nextval('app.t_mobiliario_empresa_uid_seq'::regclass);


--
-- TOC entry 4956 (class 2604 OID 904961)
-- Name: t_mobiliario_servicos uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mobiliario_servicos ALTER COLUMN uid SET DEFAULT nextval('app.t_mobiliario_servicos_uid_seq'::regclass);


--
-- TOC entry 4934 (class 2604 OID 904962)
-- Name: t_pack uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_pack ALTER COLUMN uid SET DEFAULT nextval('app.t_pack_uid_seq'::regclass);


--
-- TOC entry 4941 (class 2604 OID 904963)
-- Name: t_pack_layer_grupo uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_pack_layer_grupo ALTER COLUMN uid SET DEFAULT nextval('app.t_layer_group_uid_seq'::regclass);


--
-- TOC entry 4963 (class 2604 OID 904964)
-- Name: t_renum_logradouros uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_renum_logradouros ALTER COLUMN uid SET DEFAULT nextval('app.t_renum_logradouros_uid_seq'::regclass);


--
-- TOC entry 4966 (class 2604 OID 904965)
-- Name: t_renum_planilha uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_renum_planilha ALTER COLUMN uid SET DEFAULT nextval('app.t_renum_planilha_uid_seq'::regclass);


--
-- TOC entry 4967 (class 2604 OID 904966)
-- Name: t_reuniao uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_reuniao ALTER COLUMN uid SET DEFAULT nextval('app.t_reuniao_uid_seq'::regclass);


--
-- TOC entry 4969 (class 2604 OID 904967)
-- Name: t_sistema_bool uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_sistema_bool ALTER COLUMN uid SET DEFAULT nextval('app.t_sistema_bool_uid_seq'::regclass);


--
-- TOC entry 4971 (class 2604 OID 904968)
-- Name: t_sistema_demanda uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_sistema_demanda ALTER COLUMN uid SET DEFAULT nextval('app.t_sistema_demanda_uid_seq'::regclass);


--
-- TOC entry 4975 (class 2604 OID 904969)
-- Name: t_tema uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_tema ALTER COLUMN uid SET DEFAULT nextval('app.t_tema_uid_seq'::regclass);


--
-- TOC entry 4961 (class 2604 OID 904970)
-- Name: t_tema_pack uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_tema_pack ALTER COLUMN uid SET DEFAULT nextval('app.t_pack_tema_uid_seq'::regclass);


--
-- TOC entry 4977 (class 2604 OID 904971)
-- Name: t_users uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_users ALTER COLUMN uid SET DEFAULT nextval('app.t_users_uid_seq'::regclass);


--
-- TOC entry 4981 (class 2604 OID 904972)
-- Name: t_users_groups uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_users_groups ALTER COLUMN uid SET DEFAULT nextval('app.t_users_groups_uid_seq'::regclass);


--
-- TOC entry 4982 (class 2604 OID 904973)
-- Name: t_users_log uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_users_log ALTER COLUMN uid SET DEFAULT nextval('app.t_users_log_uid_seq'::regclass);


--
-- TOC entry 4985 (class 2604 OID 904974)
-- Name: tbl_pesq_rapida uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tbl_pesq_rapida ALTER COLUMN uid SET DEFAULT nextval('app.tbl_pesq_rapida_uid_seq'::regclass);


--
-- TOC entry 4986 (class 2604 OID 904975)
-- Name: tbl_pesq_rapida_permissao uid; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tbl_pesq_rapida_permissao ALTER COLUMN uid SET DEFAULT nextval('app.tbl_pesq_rapida_permissao_uid_seq'::regclass);


--
-- TOC entry 4987 (class 2604 OID 904976)
-- Name: tdirfoto id; Type: DEFAULT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tdirfoto ALTER COLUMN id SET DEFAULT nextval('app.tdirfoto_id_seq'::regclass);


--
-- TOC entry 5290 (class 0 OID 902313)
-- Dependencies: 231
-- Data for Name: TBL_TEMP; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5292 (class 0 OID 902323)
-- Dependencies: 233
-- Data for Name: TBL_THEMES; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5295 (class 0 OID 902335)
-- Dependencies: 236
-- Data for Name: TBL_THEMETYPES; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5298 (class 0 OID 902347)
-- Dependencies: 239
-- Data for Name: acesso_audit; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44046, '2026-07-23 19:24:25', '::1', 'admin', 'app.t_users', 'logout', '', '2026-07-23 14:24:47.391821-03', NULL, NULL, NULL, NULL, 43307);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44047, '2026-07-23 19:24:30', '::1', 'admin', 'app.t_users', 'login', '', '2026-07-23 14:24:52.218306-03', NULL, NULL, NULL, NULL, 43308);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44048, '2026-07-23 19:50:56', '::1', 'admin', 'app.t_users', 'logout', '', '2026-07-23 14:51:18.93089-03', NULL, NULL, NULL, NULL, 43309);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44049, '2026-07-23 19:51:01', '::1', 'admin', 'app.t_users', 'login', '', '2026-07-23 14:51:23.776329-03', NULL, NULL, NULL, NULL, 43310);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44050, '2026-07-23 19:55:32', '::1', 'admin', 'app.t_depart_cadastro', 'delete', '---Keys
uid : 1
---Fields
fuid_depart [old]: 1
depart [old]: Finanças
fuid_cad [old]: 1
cadastro [old]: Imobiliário
md_add [old]: 2026-05-14 15:38:26.855197-03
link [old]: Imobiliario 1
name_link [old]: t_imobiliario_default
', '2026-07-23 14:55:54.89625-03', NULL, NULL, NULL, NULL, 43311);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44051, '2026-07-23 19:55:32', '::1', 'admin', 'app.t_depart_cadastro', 'delete', '---Keys
uid : 2
---Fields
fuid_depart [old]: 1
depart [old]: Finanças
fuid_cad [old]: 2
cadastro [old]: Empresas
md_add [old]: 2021-11-24 23:19:52.499283-03
link [old]: Empresa 1
name_link [old]: t_mobiliario_empresa
', '2026-07-23 14:55:54.903648-03', NULL, NULL, NULL, NULL, 43312);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44052, '2026-07-23 19:55:32', '::1', 'admin', 'app.t_depart_cadastro', 'delete', '---Keys
uid : 3
---Fields
fuid_depart [old]: 1
depart [old]: Finanças
fuid_cad [old]: 4
cadastro [old]: Faces de Quadra
md_add [old]: 2021-11-24 23:20:07.424057-03
link [old]: Faces de Quadra 1
name_link [old]: t_face_quadra
', '2026-07-23 14:55:54.908555-03', NULL, NULL, NULL, NULL, 43313);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44053, '2026-07-23 19:55:32', '::1', 'admin', 'app.t_depart_cadastro', 'delete', '---Keys
uid : 4
---Fields
fuid_depart [old]: 2
depart [old]: Planejamento
fuid_cad [old]: 3
cadastro [old]: Logradouros
md_add [old]: 2021-11-24 23:21:00.380898-03
link [old]: Logradouros 1
name_link [old]: t_logradouros
', '2026-07-23 14:55:54.914395-03', NULL, NULL, NULL, NULL, 43314);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44054, '2026-07-23 19:55:32', '::1', 'admin', 'app.t_depart_cadastro', 'delete', '---Keys
uid : 5
---Fields
fuid_depart [old]: 3
depart [old]: Produtos
fuid_cad [old]: 5
cadastro [old]: Recad. Imobiliário
md_add [old]: 2021-11-24 23:22:24.042505-03
link [old]: Recad. Imobiliário 1
name_link [old]: t_imobiliario_recad
', '2026-07-23 14:55:54.919007-03', NULL, NULL, NULL, NULL, 43315);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44055, '2026-07-23 20:58:03', '::1', 'admin', 'app.t_users', 'logout', '', '2026-07-23 15:58:25.553916-03', NULL, NULL, NULL, NULL, 43316);
INSERT INTO app.acesso_audit (id, datetime, ip, "user", "table", action, description, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (44056, '2026-07-23 20:58:07', '::1', 'admin', 'app.t_users', 'login', '', '2026-07-23 15:58:29.872576-03', NULL, NULL, NULL, NULL, 43317);


--
-- TOC entry 5301 (class 0 OID 902359)
-- Dependencies: 242
-- Data for Name: acesso_settings; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5305 (class 0 OID 902374)
-- Dependencies: 246
-- Data for Name: acesso_tbl_link_acesso; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.acesso_tbl_link_acesso (ident, descricao, link_acesso, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (2, 'CIUS', 'http://sp.maua.devs.millenio.com.br/apps/sp.osasco/consultacius/app_cons_uso_e_ocupacao_list.php?goto=4&orderby=ddata_consulta', '2021-08-04 01:05:32.147631-03', NULL, NULL, NULL, NULL, 3);
INSERT INTO app.acesso_tbl_link_acesso (ident, descricao, link_acesso, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (1, 'Webgis Maua', '../web', '2021-08-04 01:05:32.147631-03', NULL, NULL, NULL, NULL, 1);
INSERT INTO app.acesso_tbl_link_acesso (ident, descricao, link_acesso, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (3, 'admin', '../forms', '2021-08-04 01:05:32.147631-03', NULL, NULL, NULL, NULL, 2);


--
-- TOC entry 5310 (class 0 OID 903098)
-- Dependencies: 252
-- Data for Name: geo_lote_31983; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5312 (class 0 OID 903668)
-- Dependencies: 255
-- Data for Name: t_anexo_IV_12_03_2026; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Industrial MZI', 'ZDE 1 A', 'Não incômodo;Incômodo I, II e III', 'Proibido
Residencial;Anexo VI', '250', '10', '0.7', '0.15', '0.2', '2', '2', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Industrial MZI', 'ZDE 1 B', 'Não incômodo;Incômodo I, II e III', 'Proibido
Residencial;Anexo VI', '250', '10', '0.7', '0.15', '0.2', '2', '2', '5m      (1)(6)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Industrial MZI', 'ZDE 2', 'Não incômodo;Incômodo I, II e III', 'Proibido
Residencial;Anexo VI', '250', '10', '0.7', '0.15', '0.2', '2', '5', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Industrial MZI', 'ZUD I', 'Não incômodo;Incômodo I e II compatíveis com Residencial', 'Não permitido
Multifamiliar;Anexo VI', '125;250 para o uso industrial', '5;10 industrial', '0.7', 'Lote ≤ 500 m² 5%
Lote  > 500 m² 15%', '0.2', '1.5', '1.5', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Central
 MZC', 'ZC', 'Não incômodo;Incômodo', '-;Anexo VI', '125|250 para o uso industrial', '5;10 industrial', '70% Residencial e Industrial
75% Diversificados e Mistos', 'Lote ≤ 500 m² 5%
Lote  > 500 m² 15% (5)', '0.2', 'Unifamiliar 2
Multifamiliar, Misto, Diversificados e Outros 2,5', '5', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Central
 MZC', 'ZCB', 'Não incômodo;Incômodo I e II compatíveis com Residencial', '-;Anexo VI', '125;250 para o uso industrial', '5;10 industrial', '70% Residencial e Industrial
75% Diversificados e Mistos', 'Lote ≤ 500 m² 5%
Lote  > 500 m² 15%', '0.2', 'Unifamiliar 2
Multifamiliar 2,55 Diversificados, Misto e Outros 2,60', '5', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Central
 MZC', 'ZUD 1', 'Não incômodo;Incômodo I', '-;Anexo VI', '125;250 para o uso industrial', '5;10 industrial', '0.7', 'Lote ≤ 500 m² 5%
Lote  > 500 m² 15%', '0.2', 'Unifamiliar 2
Multifamiliar, Misto, Diversificados e outros 2,5', '5', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Central 
MZC', 'ZUD 2 A', 'Não incômodo;Incômodo I', '-;Anexo VI', '125;250 para o uso industrial', '5;10 industrial', '0.7', 'Lote ≤ 500 m² 5%
Lote  > 500 m² 15%', '0.2', '1.5', '1.5', '5m       (1)(6)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Central 
MZC', 'ZUD 2 B', 'Não incômodo;Incômodo I', 'Não permitido
Multifamiliar;Anexo VI', '125;250 para o uso
industrial', '5;10 industrial', '0.7', 'Lote ≤ 500 m² 5%
Lote  > 500 m² 15%', '0.2', '1.5', '1.5', '5m (1) (6) (7)
Altura 15m:
R = (H/15,00) + 4,00 >5,00m', 'R = (H/15,00) + 0,5>1,50m
Altura até 7m: dispensado Recuo mediante condições', 'R = (H/15,00) + 0,5 > 1,5m
Altura até 15m: dispensado Recuo mediante condições');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Ecológica
 MZE', 'ZDS', 'Não incômodo', 'Anexo VI', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Ecológica 
MZE', 'ZUD- A', 'Não incômodo', 'Anexo VI', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica');
INSERT INTO app."t_anexo_IV_12_03_2026" ("Macrozonas", "Zonas", "Categorias de uso permitidas (8)", "Exigência / Controle de Impacto", "Lote mínimo (m²)", "Testada Mínima (m)", "Taxa de Ocupação %", "Taxa de Permeabilidade (TP)
(3) (4)", "Coeficiente de Aproveitamento - CAMínimo", "Coeficiente de Aproveitamento - CA Básico", "Coeficiente de Aproveitamento - CA Máximo
(2)", "Recuo Frontal
(*) ver art 33 a 35", "Recuo Fundos
(*) Ver Art.36 à 37", "Recuo Lateral
(*) Ver Art.38 e 39") VALUES ('Ecológica
 MZE', 'ZPA', 'Não incômodo', 'Anexo VI', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica', 'A ser regulamentada por legislação específica');


--
-- TOC entry 5313 (class 0 OID 903674)
-- Dependencies: 256
-- Data for Name: t_anexo_V_12_03_2026; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app."t_anexo_V_12_03_2026" (tipo_empre, lt_min_declivi_0_30, lt_min_declivi_30_50, lt_max, testada, recuo_frente, recuo_fundos, recuo_lateral, tx_perme_declivi_0_20, tx_perme_declivi_20_50, tx_ocupacao, ca, "Categoria de Uso [6]", vaga_his1_zeis_ap, vaga_his1_fzeis) VALUES ('Multifamiliar Horizontal (por Unidade Habitacional)', '60', '90', '125', '3.5', 'R=(H/15)+0,5 ≥ 1,5', 'R=(H/15)+0,5 ≥ 1,5', 'R=(H/15)+0,5 ≥ 1,5', '5', '0', '0.75', '2', 'Não incomodo', '1 vaga p/ cada 3 UHs (1:3)', '1 vaga p/ cada UHs (1:1)');
INSERT INTO app."t_anexo_V_12_03_2026" (tipo_empre, lt_min_declivi_0_30, lt_min_declivi_30_50, lt_max, testada, recuo_frente, recuo_fundos, recuo_lateral, tx_perme_declivi_0_20, tx_perme_declivi_20_50, tx_ocupacao, ca, "Categoria de Uso [6]", vaga_his1_zeis_ap, vaga_his1_fzeis) VALUES ('Multifamiliar Vertical', 'Para qualquer declividade 125', 'Para qualquer declividade 125', '20000', '5', 'R=(H/15)+0,5 ≥ 1,5', 'R=(H/15)+0,5 ≥ 1,5', 'R=(H/15)+0,5 ≥ 1,5', 'Para qualquer declividade 5% para lotes ≤  500 m² ; Para qualquer declividade 15% para lotes > 500 m2', 'Para qualquer declividade 5% para lotes ≤  500 m² ; Para qualquer declividade 15% para lotes > 500 m2', '0.75', '5', 'Não incomodo', '1 vaga p/ cada 3 UHs (1:3)', '1 vaga p/ cada UHs (1:1)');
INSERT INTO app."t_anexo_V_12_03_2026" (tipo_empre, lt_min_declivi_0_30, lt_min_declivi_30_50, lt_max, testada, recuo_frente, recuo_fundos, recuo_lateral, tx_perme_declivi_0_20, tx_perme_declivi_20_50, tx_ocupacao, ca, "Categoria de Uso [6]", vaga_his1_zeis_ap, vaga_his1_fzeis) VALUES ('Unifamiliar', '60', '90', '125', '3.5', 'R=(H/15)+0,5 ≥ 1,5', 'R=(H/15)+0,5 ≥ 1,5', 'R=(H/15)+0,5 ≥ 1,5', '5', '0', '0.75', '2', 'Não incomodo', '1 vaga p/ cada 3 UHs (1:3)', '1 vaga p/ cada UHs (1:1)');


--
-- TOC entry 5314 (class 0 OID 903680)
-- Dependencies: 257
-- Data for Name: t_anexos; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5316 (class 0 OID 903689)
-- Dependencies: 259
-- Data for Name: t_arquivos_anexos; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5318 (class 0 OID 903698)
-- Dependencies: 261
-- Data for Name: t_cius_atividades; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5322 (class 0 OID 903710)
-- Dependencies: 265
-- Data for Name: t_cius_cnae; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5324 (class 0 OID 903720)
-- Dependencies: 267
-- Data for Name: t_cius_cnae_denominacao; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5326 (class 0 OID 903730)
-- Dependencies: 269
-- Data for Name: t_cius_cnae_grupo; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5328 (class 0 OID 903740)
-- Dependencies: 271
-- Data for Name: t_cius_cnae_secao; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5308 (class 0 OID 902846)
-- Dependencies: 250
-- Data for Name: t_cius_consulta; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5330 (class 0 OID 903757)
-- Dependencies: 273
-- Data for Name: t_cius_status_certidao; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5332 (class 0 OID 903767)
-- Dependencies: 275
-- Data for Name: t_cius_uso_geral; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5333 (class 0 OID 903775)
-- Dependencies: 276
-- Data for Name: t_config_system; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5334 (class 0 OID 903781)
-- Dependencies: 277
-- Data for Name: t_depart; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5335 (class 0 OID 903788)
-- Dependencies: 278
-- Data for Name: t_depart_cadastro; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5336 (class 0 OID 903795)
-- Dependencies: 279
-- Data for Name: t_depart_cadastro_grupo; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5339 (class 0 OID 903806)
-- Dependencies: 282
-- Data for Name: t_depart_link_docs; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_depart_link_docs (uid, tipo, permissao) VALUES (1, 'PRIVADO', 'Sim');
INSERT INTO app.t_depart_link_docs (uid, tipo, permissao) VALUES (2, 'PÚBLICO', 'Não');


--
-- TOC entry 5341 (class 0 OID 903814)
-- Dependencies: 284
-- Data for Name: t_depart_tabela; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5344 (class 0 OID 903826)
-- Dependencies: 287
-- Data for Name: t_end_storage; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5345 (class 0 OID 903832)
-- Dependencies: 288
-- Data for Name: t_estim_area_const; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5347 (class 0 OID 903841)
-- Dependencies: 290
-- Data for Name: t_estim_area_const_vistoria; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5349 (class 0 OID 903850)
-- Dependencies: 292
-- Data for Name: t_face_quadra; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5353 (class 0 OID 903868)
-- Dependencies: 296
-- Data for Name: t_groups; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (2, 'PÚBLICO', '{"module": "Sefin", "police": "R"}', '2018-01-26 13:15:07.164241-02', NULL, 'default', NULL, NULL, 'All', 'R', 'Público');
INSERT INTO app.t_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (1, 'Administradores', '{"module": "All", "police": "CRUD"}', '2018-01-26 13:15:07.164241-02', NULL, 'default', NULL, NULL, 'All', 'CRUD', 'PRIVADO');
INSERT INTO app.t_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (3, 'Servidor', '{"module": "All", "police": "CRUD"}', '2019-12-13 12:15:07.164-03', NULL, 'admin', NULL, NULL, 'All', 'CRUD', 'PRIVADO');
INSERT INTO app.t_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (4, 'Treinamento', '{"module": "Sefin", "police": "R"}', '2018-01-26 13:15:07.164241-02', NULL, 'default', NULL, NULL, 'All', 'R', 'PRIVADO');


--
-- TOC entry 5354 (class 0 OID 903875)
-- Dependencies: 297
-- Data for Name: t_groups_permissao; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_groups_permissao (uid, permissao, regra, tipo) VALUES (1, 'Leitura', '{"module": "All", "police": "R"}', 'R');
INSERT INTO app.t_groups_permissao (uid, permissao, regra, tipo) VALUES (2, 'Escrita', '{"module": "All", "police": "CRUD"}', 'CRUD');


--
-- TOC entry 5289 (class 0 OID 902287)
-- Dependencies: 229
-- Data for Name: t_imobiliario_default; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5359 (class 0 OID 903889)
-- Dependencies: 302
-- Data for Name: t_imobiliario_recad; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5363 (class 0 OID 903907)
-- Dependencies: 306
-- Data for Name: t_logradouros; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5366 (class 0 OID 903918)
-- Dependencies: 309
-- Data for Name: t_memo_registro; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5367 (class 0 OID 903927)
-- Dependencies: 310
-- Data for Name: t_mensagens; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5368 (class 0 OID 903934)
-- Dependencies: 311
-- Data for Name: t_mensagens_anexos; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5371 (class 0 OID 903945)
-- Dependencies: 314
-- Data for Name: t_metadados_print; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5373 (class 0 OID 903954)
-- Dependencies: 316
-- Data for Name: t_mobiliario_empresa; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5375 (class 0 OID 903963)
-- Dependencies: 318
-- Data for Name: t_mobiliario_servicos; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5351 (class 0 OID 903859)
-- Dependencies: 294
-- Data for Name: t_pack; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_pack (uid, pack, descricao, ordem_pack, md_add, md_alt, md_usr, md_usr_last, fuid, "order") VALUES (1, 'Mapas', 'Mapas Base', 1, '2021-10-02 08:42:49.619373-03', NULL, NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack (uid, pack, descricao, ordem_pack, md_add, md_alt, md_usr, md_usr_last, fuid, "order") VALUES (2, 'Temáticos', 'Temáticos Administradore', 13, '2021-11-24 21:50:32.510451-03', NULL, NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack (uid, pack, descricao, ordem_pack, md_add, md_alt, md_usr, md_usr_last, fuid, "order") VALUES (3, 'Temáticos', 'Temáticos Servidor', 14, '2021-11-24 21:50:37.124314-03', NULL, NULL, NULL, NULL, NULL);


--
-- TOC entry 5378 (class 0 OID 903982)
-- Dependencies: 321
-- Data for Name: t_pack_layer; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5361 (class 0 OID 903898)
-- Dependencies: 304
-- Data for Name: t_pack_layer_grupo; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (18, NULL, NULL, 1, 'Administradores', 1, 'Mapas', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Mapas Base', 6, 1, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (19, NULL, NULL, 1, 'Administradores', 2, 'Base2010', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 17, 3, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (20, NULL, NULL, 1, 'Administradores', 3, 'Base2000', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 5, 4, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (22, NULL, NULL, 1, 'Administradores', 5, 'Base1997', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 2, 5, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (23, NULL, NULL, 1, 'Administradores', 6, 'Equipamentos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 4, 6, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (24, NULL, NULL, 1, 'Administradores', 7, 'Temáticos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Temáticos Administradores', 9, 13, '2021-10-06 07:22:43.836329-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (26, NULL, NULL, 2, 'PÚBLICO', 1, 'Mapas', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Mapas Base', 6, 1, '2021-11-24 17:54:48.978636-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (28, NULL, NULL, 3, 'Servidor', 1, 'Mapas', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Mapas Base', 6, 1, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (29, NULL, NULL, 3, 'Servidor', 2, 'Base2010', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 17, 3, '2021-10-02 05:40:51.866763-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (30, NULL, NULL, 3, 'Servidor', 3, 'Base2000', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 5, 4, '2021-10-06 07:23:31.046068-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (32, NULL, NULL, 3, 'Servidor', 5, 'Base1997', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 2, 5, '2021-10-06 07:24:08.64037-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (33, NULL, NULL, 3, 'Servidor', 6, 'Equipamentos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 4, 6, '2021-11-22 16:52:52.950446-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (34, NULL, NULL, 3, 'Servidor', 8, 'Temáticos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Temáticos Servidor', 14, 13, '2021-11-24 15:09:50.451084-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (133, NULL, NULL, 1, 'Administradores', 10, 'Infraestrutura', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 18, 7, '2022-01-13 06:59:17.139832-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (134, NULL, NULL, 1, 'Administradores', 11, 'Ambiental', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 15, 2, '2022-01-13 06:59:49.919828-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (136, NULL, NULL, 1, 'Administradores', 14, 'Parcelamento', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 13, 8, '2022-01-27 10:43:35.594099-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (137, NULL, NULL, 1, 'Administradores', 15, 'Planejamento', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 7, 9, '2022-01-27 10:44:07.808141-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (138, NULL, NULL, 1, 'Administradores', 16, 'Miscelania', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 16, 10, '2022-01-27 10:45:05.164608-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (143, NULL, NULL, 3, 'Servidor', 10, 'Infraestrutura', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 18, 7, '2022-01-27 10:54:56.375076-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (144, NULL, NULL, 3, 'Servidor', 11, 'Ambiental', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 15, 2, '2022-01-27 10:55:06.718035-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (145, NULL, NULL, 3, 'Servidor', 14, 'Parcelamento', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 13, 8, '2022-01-27 10:55:13.832794-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (146, NULL, NULL, 3, 'Servidor', 15, 'Planejamento', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 7, 9, '2022-01-27 10:55:23.678441-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (147, NULL, NULL, 3, 'Servidor', 16, 'Miscelania', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo Servidores', 16, 10, '2022-01-27 10:55:41.314804-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (262, NULL, NULL, 2, 'PÚBLICO', 2, 'Base2010', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo publico', 17, NULL, '2022-02-10 13:10:59.013328-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (266, NULL, NULL, 2, 'PÚBLICO', 6, 'Equipamentos', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo publico', 4, NULL, '2022-03-09 11:32:57.733233-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (269, NULL, NULL, 2, 'PÚBLICO', 10, 'Infraestrutura', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo publico', 18, NULL, '2022-03-09 11:42:10.899361-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (270, NULL, NULL, 2, 'PÚBLICO', 11, 'Ambiental', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo publico', 15, NULL, '2022-03-09 11:43:02.843442-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (271, NULL, NULL, 2, 'PÚBLICO', 14, 'Parcelamento', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo publico', 13, NULL, '2022-03-09 11:43:21.624144-03', NULL, NULL, NULL, NULL);
INSERT INTO app.t_pack_layer_grupo (uid, fuid_user, name_user, fuid_group, name_group, fuid_pack, name_pack, ds_enable, ds_name, ds_type, ws_name, type, srs, projection_policy, enabled, name, title, native_name, prefixed_name, abstract, name_tema, fuid_tema_pack, ordem, md_add, md_alt, md_usr, md_usr_last, fuid) VALUES (272, NULL, NULL, 2, 'PÚBLICO', 15, 'Planejamento', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'Grupo publico', 7, NULL, '2022-03-09 11:43:31.313931-03', NULL, NULL, NULL, NULL);


--
-- TOC entry 5381 (class 0 OID 904000)
-- Dependencies: 324
-- Data for Name: t_renum_logradouros; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5383 (class 0 OID 904009)
-- Dependencies: 326
-- Data for Name: t_renum_planilha; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5385 (class 0 OID 904018)
-- Dependencies: 328
-- Data for Name: t_reuniao; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5387 (class 0 OID 904027)
-- Dependencies: 330
-- Data for Name: t_sistema_bool; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5389 (class 0 OID 904036)
-- Dependencies: 332
-- Data for Name: t_sistema_demanda; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5391 (class 0 OID 904045)
-- Dependencies: 334
-- Data for Name: t_stage_manager; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5392 (class 0 OID 904053)
-- Dependencies: 335
-- Data for Name: t_tema; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5379 (class 0 OID 903991)
-- Dependencies: 322
-- Data for Name: t_tema_pack; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5394 (class 0 OID 904078)
-- Dependencies: 337
-- Data for Name: t_users; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_users (uid, fuid_groups, name, alias_name, pass, token, md_add, md_alt, md_usr, md_usr_last, email, ativo, fuid, apikey, reset_token, reset_date, user_type, mostrar_popup, tipo) VALUES (1, 1, 'admin', 'Administrador', 'bbf967c9279cda44550d1b82fe34ac65', NULL, '2018-01-29 04:02:54.604855-02', '2019-06-24 07:44:03.267473-03', 'admin', 'admin', 'admin@millenio.com.br', 1, NULL, NULL, 'ijonmhzweee6e1f6zovh', '2025-04-15 11:26:01', 'admin', 'f', NULL);
INSERT INTO app.t_users (uid, fuid_groups, name, alias_name, pass, token, md_add, md_alt, md_usr, md_usr_last, email, ativo, fuid, apikey, reset_token, reset_date, user_type, mostrar_popup, tipo) VALUES (5, 1, 'convidado', 'Convidado', 'b44caea00f1919925cc85e8aba8e2457', NULL, '2020-10-23 18:07:32.432379-03', '2020-10-23 18:11:08.933987-03', 'admin', 'admin', 'treino@semdominio.com.br', 1, NULL, NULL, NULL, NULL, 'interno_consulta', 'f', NULL);


--
-- TOC entry 5395 (class 0 OID 904086)
-- Dependencies: 338
-- Data for Name: t_users_groups; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.t_users_groups (fuid_users, fuid_groups, name_groups, name_users, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (1, 1, 'Administradores', 'admin', '2021-08-04 01:05:33.718816-03', NULL, NULL, NULL, NULL, 10);
INSERT INTO app.t_users_groups (fuid_users, fuid_groups, name_groups, name_users, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (1, 3, 'Servidor', 'admin', '2021-08-04 01:05:33.718816-03', NULL, NULL, NULL, NULL, 17);
INSERT INTO app.t_users_groups (fuid_users, fuid_groups, name_groups, name_users, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (1, 4, 'Treinamento', 'admin', '2021-08-04 01:05:33.718816-03', NULL, NULL, NULL, NULL, 32);
INSERT INTO app.t_users_groups (fuid_users, fuid_groups, name_groups, name_users, md_add, md_alt, md_usr, md_usr_last, fuid, uid) VALUES (5, 1, 'Administradores', 'convidado', '2025-04-14 11:23:36.166953-03', NULL, NULL, NULL, NULL, 236);


--
-- TOC entry 5397 (class 0 OID 904095)
-- Dependencies: 340
-- Data for Name: t_users_log; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5400 (class 0 OID 904105)
-- Dependencies: 343
-- Data for Name: tbl_groups; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.tbl_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (2, 'PÚBLICO', '{"module": "Sefin", "police": "R"}', '2018-01-26 13:15:07.164241-02', NULL, 'default', NULL, NULL, 'All', 'R', 'PÚBLICO');
INSERT INTO app.tbl_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (3, 'Servidor', '{"module": "All", "police": "CRUD"}', '2019-12-13 12:15:07.164-03', NULL, 'admin', NULL, NULL, 'All', 'CRUD', 'PRIVADO');
INSERT INTO app.tbl_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (1, 'Administradores', '{"module": "All", "police": "CRUD"}', '2018-01-26 13:15:07.164241-02', NULL, 'default', NULL, NULL, 'All', 'CRUD', 'PRIVADO');
INSERT INTO app.tbl_groups (uid, name, jbrules, md_add, md_alt, md_usr, md_usr_last, fuid, modulo, permissao, tipo) VALUES (6, 'Treinamento', '{"module": "Sefin", "police": "R"}', '2018-01-26 13:15:07.164241-02', NULL, 'default', NULL, NULL, 'All', 'R', 'PRIVADO');


--
-- TOC entry 5401 (class 0 OID 904113)
-- Dependencies: 344
-- Data for Name: tbl_pesq_rapida; Type: TABLE DATA; Schema: app; Owner: -
--

INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (1, 'Inscrição');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (2, 'Código');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (3, 'Matrícula');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (4, 'Endereço');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (5, 'Proprietário');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (6, 'CPF');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (7, 'CNPJ');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (8, 'Quadra');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (9, 'Lote');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (10, 'Logradouro');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (11, 'Bairro');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (12, 'Loteamento');
INSERT INTO app.tbl_pesq_rapida (uid, pesquisa) VALUES (13, NULL);


--
-- TOC entry 5402 (class 0 OID 904116)
-- Dependencies: 345
-- Data for Name: tbl_pesq_rapida_permissao; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5408 (class 0 OID 904132)
-- Dependencies: 351
-- Data for Name: tdirfoto; Type: TABLE DATA; Schema: app; Owner: -
--



--
-- TOC entry 5538 (class 0 OID 0)
-- Dependencies: 232
-- Name: TBL_TEMP_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app."TBL_TEMP_uid_seq"', 1, false);


--
-- TOC entry 5539 (class 0 OID 0)
-- Dependencies: 234
-- Name: TBL_THEMES_objectid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app."TBL_THEMES_objectid_seq"', 290, true);


--
-- TOC entry 5540 (class 0 OID 0)
-- Dependencies: 235
-- Name: TBL_THEMES_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app."TBL_THEMES_uid_seq"', 290, true);


--
-- TOC entry 5541 (class 0 OID 0)
-- Dependencies: 237
-- Name: TBL_THEMETYPES_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app."TBL_THEMETYPES_uid_seq"', 1, false);


--
-- TOC entry 5542 (class 0 OID 0)
-- Dependencies: 240
-- Name: acesso_audit_id_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.acesso_audit_id_seq', 44056, true);


--
-- TOC entry 5543 (class 0 OID 0)
-- Dependencies: 243
-- Name: acesso_settings_ID_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app."acesso_settings_ID_seq"', 2, false);


--
-- TOC entry 5544 (class 0 OID 0)
-- Dependencies: 244
-- Name: acesso_settings_id_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.acesso_settings_id_seq', 3, false);


--
-- TOC entry 5545 (class 0 OID 0)
-- Dependencies: 247
-- Name: acesso_tbl_link_acesso_ident_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.acesso_tbl_link_acesso_ident_seq', 4, true);


--
-- TOC entry 5546 (class 0 OID 0)
-- Dependencies: 249
-- Name: app_tdirfoto_id; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.app_tdirfoto_id', 2, false);


--
-- TOC entry 5547 (class 0 OID 0)
-- Dependencies: 251
-- Name: cons_uso_e_ocupacao_id_seq1; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.cons_uso_e_ocupacao_id_seq1', 60601, true);


--
-- TOC entry 5548 (class 0 OID 0)
-- Dependencies: 253
-- Name: geo_lote_31983_uid2_seq1; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.geo_lote_31983_uid2_seq1', 183987, true);


--
-- TOC entry 5549 (class 0 OID 0)
-- Dependencies: 258
-- Name: t_anexos_ident_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_anexos_ident_seq', 181497, true);


--
-- TOC entry 5550 (class 0 OID 0)
-- Dependencies: 260
-- Name: t_arquivos_anexos_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_arquivos_anexos_uid_seq', 194629, true);


--
-- TOC entry 5551 (class 0 OID 0)
-- Dependencies: 262
-- Name: t_cius_atividades_ordem_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_cius_atividades_ordem_seq', 1043, true);


--
-- TOC entry 5552 (class 0 OID 0)
-- Dependencies: 263
-- Name: t_cius_atividades_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_cius_atividades_uid_seq', 1044, true);


--
-- TOC entry 5553 (class 0 OID 0)
-- Dependencies: 280
-- Name: t_depart_cadastro_grupo_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_depart_cadastro_grupo_uid_seq', 47, true);


--
-- TOC entry 5554 (class 0 OID 0)
-- Dependencies: 281
-- Name: t_depart_cadastro_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_depart_cadastro_uid_seq', 9, true);


--
-- TOC entry 5555 (class 0 OID 0)
-- Dependencies: 283
-- Name: t_depart_link_docs_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_depart_link_docs_uid_seq', 2, true);


--
-- TOC entry 5556 (class 0 OID 0)
-- Dependencies: 285
-- Name: t_depart_tabela_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_depart_tabela_uid_seq', 11, true);


--
-- TOC entry 5557 (class 0 OID 0)
-- Dependencies: 286
-- Name: t_depart_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_depart_uid_seq', 5, true);


--
-- TOC entry 5558 (class 0 OID 0)
-- Dependencies: 289
-- Name: t_estim_area_const_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_estim_area_const_uid_seq', 87795, true);


--
-- TOC entry 5559 (class 0 OID 0)
-- Dependencies: 291
-- Name: t_estim_area_const_vistoria_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_estim_area_const_vistoria_uid_seq', 45578, true);


--
-- TOC entry 5560 (class 0 OID 0)
-- Dependencies: 293
-- Name: t_face_quadra_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_face_quadra_uid_seq', 6645, true);


--
-- TOC entry 5561 (class 0 OID 0)
-- Dependencies: 295
-- Name: t_group_layer_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_group_layer_uid_seq', 8, true);


--
-- TOC entry 5562 (class 0 OID 0)
-- Dependencies: 298
-- Name: t_groups_permissao_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_groups_permissao_uid_seq', 2, true);


--
-- TOC entry 5563 (class 0 OID 0)
-- Dependencies: 299
-- Name: t_groups_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_groups_uid_seq', 19, true);


--
-- TOC entry 5564 (class 0 OID 0)
-- Dependencies: 300
-- Name: t_imobiliario_default_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_imobiliario_default_uid_seq', 216853, true);


--
-- TOC entry 5565 (class 0 OID 0)
-- Dependencies: 301
-- Name: t_imobiliario_default_uid_seq1; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_imobiliario_default_uid_seq1', 123584, true);


--
-- TOC entry 5566 (class 0 OID 0)
-- Dependencies: 303
-- Name: t_imobiliario_recad_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_imobiliario_recad_uid_seq', 208873, true);


--
-- TOC entry 5567 (class 0 OID 0)
-- Dependencies: 305
-- Name: t_layer_group_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_layer_group_uid_seq', 365, true);


--
-- TOC entry 5568 (class 0 OID 0)
-- Dependencies: 307
-- Name: t_logradouros_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_logradouros_uid_seq', 5344, true);


--
-- TOC entry 5569 (class 0 OID 0)
-- Dependencies: 312
-- Name: t_mensagens_anexos_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_mensagens_anexos_uid_seq', 1, false);


--
-- TOC entry 5570 (class 0 OID 0)
-- Dependencies: 313
-- Name: t_mensagens_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_mensagens_uid_seq', 1, true);


--
-- TOC entry 5571 (class 0 OID 0)
-- Dependencies: 315
-- Name: t_metadados_print_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_metadados_print_uid_seq', 2, true);


--
-- TOC entry 5572 (class 0 OID 0)
-- Dependencies: 317
-- Name: t_mobiliario_empresa_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_mobiliario_empresa_uid_seq', 49461, true);


--
-- TOC entry 5573 (class 0 OID 0)
-- Dependencies: 319
-- Name: t_mobiliario_servicos_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_mobiliario_servicos_uid_seq', 46151, true);


--
-- TOC entry 5574 (class 0 OID 0)
-- Dependencies: 323
-- Name: t_pack_tema_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_pack_tema_uid_seq', 50, true);


--
-- TOC entry 5575 (class 0 OID 0)
-- Dependencies: 320
-- Name: t_pack_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_pack_uid_seq', 34, true);


--
-- TOC entry 5576 (class 0 OID 0)
-- Dependencies: 325
-- Name: t_renum_logradouros_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_renum_logradouros_uid_seq', 1983, true);


--
-- TOC entry 5577 (class 0 OID 0)
-- Dependencies: 327
-- Name: t_renum_planilha_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_renum_planilha_uid_seq', 167108, true);


--
-- TOC entry 5578 (class 0 OID 0)
-- Dependencies: 329
-- Name: t_reuniao_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_reuniao_uid_seq', 1, false);


--
-- TOC entry 5579 (class 0 OID 0)
-- Dependencies: 331
-- Name: t_sistema_bool_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_sistema_bool_uid_seq', 2, true);


--
-- TOC entry 5580 (class 0 OID 0)
-- Dependencies: 333
-- Name: t_sistema_demanda_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_sistema_demanda_uid_seq', 117, true);


--
-- TOC entry 5581 (class 0 OID 0)
-- Dependencies: 336
-- Name: t_tema_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_tema_uid_seq', 45, true);


--
-- TOC entry 5582 (class 0 OID 0)
-- Dependencies: 339
-- Name: t_users_groups_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_users_groups_uid_seq', 295, true);


--
-- TOC entry 5583 (class 0 OID 0)
-- Dependencies: 341
-- Name: t_users_log_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_users_log_uid_seq', 218, true);


--
-- TOC entry 5584 (class 0 OID 0)
-- Dependencies: 342
-- Name: t_users_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.t_users_uid_seq', 3975, true);


--
-- TOC entry 5585 (class 0 OID 0)
-- Dependencies: 346
-- Name: tbl_pesq_rapida_permissao_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.tbl_pesq_rapida_permissao_uid_seq', 141, true);


--
-- TOC entry 5586 (class 0 OID 0)
-- Dependencies: 347
-- Name: tbl_pesq_rapida_uid_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.tbl_pesq_rapida_uid_seq', 12, true);


--
-- TOC entry 5587 (class 0 OID 0)
-- Dependencies: 348
-- Name: tbl_status_certidao_id_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.tbl_status_certidao_id_seq', 6, true);


--
-- TOC entry 5588 (class 0 OID 0)
-- Dependencies: 349
-- Name: tbl_uso_geral_id_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.tbl_uso_geral_id_seq', 8, true);


--
-- TOC entry 5589 (class 0 OID 0)
-- Dependencies: 352
-- Name: tdirfoto_id_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.tdirfoto_id_seq', 241, true);


--
-- TOC entry 5590 (class 0 OID 0)
-- Dependencies: 238
-- Name: uid_acesso_audit_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_acesso_audit_pk_seq', 43317, true);


--
-- TOC entry 5591 (class 0 OID 0)
-- Dependencies: 241
-- Name: uid_acesso_settings_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_acesso_settings_pk_seq', 1, false);


--
-- TOC entry 5592 (class 0 OID 0)
-- Dependencies: 245
-- Name: uid_acesso_tbl_link_acesso_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_acesso_tbl_link_acesso_pk_seq', 3, true);


--
-- TOC entry 5593 (class 0 OID 0)
-- Dependencies: 266
-- Name: uid_t_cius_cnae_denominacao_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_cnae_denominacao_pk_seq', 673, true);


--
-- TOC entry 5594 (class 0 OID 0)
-- Dependencies: 268
-- Name: uid_t_cius_cnae_grupo_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_cnae_grupo_pk_seq', 285, true);


--
-- TOC entry 5595 (class 0 OID 0)
-- Dependencies: 264
-- Name: uid_t_cius_cnae_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_cnae_pk_seq', 673, true);


--
-- TOC entry 5596 (class 0 OID 0)
-- Dependencies: 270
-- Name: uid_t_cius_cnae_secao_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_cnae_secao_pk_seq', 21, true);


--
-- TOC entry 5597 (class 0 OID 0)
-- Dependencies: 353
-- Name: uid_t_cius_consulta_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_consulta_pk_seq', 60597, true);


--
-- TOC entry 5598 (class 0 OID 0)
-- Dependencies: 272
-- Name: uid_t_cius_status_certidao_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_status_certidao_pk_seq', 4, true);


--
-- TOC entry 5599 (class 0 OID 0)
-- Dependencies: 274
-- Name: uid_t_cius_uso_geral_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_cius_uso_geral_pk_seq', 5, true);


--
-- TOC entry 5600 (class 0 OID 0)
-- Dependencies: 354
-- Name: uid_t_estim_area_const_old_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_estim_area_const_old_pk_seq', 1, false);


--
-- TOC entry 5601 (class 0 OID 0)
-- Dependencies: 308
-- Name: uid_t_memo_registro_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_memo_registro_pk_seq', 54, true);


--
-- TOC entry 5602 (class 0 OID 0)
-- Dependencies: 355
-- Name: uid_t_renum_planilha_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_t_renum_planilha_pk_seq', 1, false);


--
-- TOC entry 5603 (class 0 OID 0)
-- Dependencies: 350
-- Name: uid_tdirfoto_pk_seq; Type: SEQUENCE SET; Schema: app; Owner: -
--

SELECT pg_catalog.setval('app.uid_tdirfoto_pk_seq', 40, true);


--
-- TOC entry 4993 (class 2606 OID 910509)
-- Name: TBL_TEMP TBL_TEMP_uid_pk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_TEMP"
    ADD CONSTRAINT "TBL_TEMP_uid_pk" PRIMARY KEY (uid);


--
-- TOC entry 4998 (class 2606 OID 910511)
-- Name: TBL_THEMES TBL_THEMES_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_THEMES"
    ADD CONSTRAINT "TBL_THEMES_pkey" PRIMARY KEY (objectid);


--
-- TOC entry 5003 (class 2606 OID 910513)
-- Name: TBL_THEMETYPES TBL_THEMETYPES_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app."TBL_THEMETYPES"
    ADD CONSTRAINT "TBL_THEMETYPES_pkey" PRIMARY KEY (objectid);


--
-- TOC entry 5014 (class 2606 OID 910679)
-- Name: geo_lote_31983 geo_lote_31983_new01_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.geo_lote_31983
    ADD CONSTRAINT geo_lote_31983_new01_pkey PRIMARY KEY (uid);


--
-- TOC entry 5019 (class 2606 OID 910809)
-- Name: t_anexos t_anexos_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_anexos
    ADD CONSTRAINT t_anexos_pkey PRIMARY KEY (inscricao);


--
-- TOC entry 5021 (class 2606 OID 910811)
-- Name: t_cius_atividades t_cius_atividades_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_atividades
    ADD CONSTRAINT t_cius_atividades_pkey PRIMARY KEY (ordem);


--
-- TOC entry 5012 (class 2606 OID 910813)
-- Name: t_cius_consulta t_cius_consulta_copy_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_consulta
    ADD CONSTRAINT t_cius_consulta_copy_pkey PRIMARY KEY (uid);


--
-- TOC entry 5035 (class 2606 OID 910817)
-- Name: t_config_system t_config_system_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_config_system
    ADD CONSTRAINT t_config_system_pkey PRIMARY KEY (uid);


--
-- TOC entry 5041 (class 2606 OID 910819)
-- Name: t_depart_cadastro_grupo t_depart_cad_grupo_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_cadastro_grupo
    ADD CONSTRAINT t_depart_cad_grupo_pkey PRIMARY KEY (uid);


--
-- TOC entry 5045 (class 2606 OID 910821)
-- Name: t_depart_tabela t_depart_cad_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_tabela
    ADD CONSTRAINT t_depart_cad_pkey PRIMARY KEY (uid);


--
-- TOC entry 5039 (class 2606 OID 910823)
-- Name: t_depart_cadastro t_depart_cadastro_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_cadastro
    ADD CONSTRAINT t_depart_cadastro_pkey PRIMARY KEY (uid);


--
-- TOC entry 5043 (class 2606 OID 910825)
-- Name: t_depart_link_docs t_depart_link_docs_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart_link_docs
    ADD CONSTRAINT t_depart_link_docs_pkey PRIMARY KEY (uid);


--
-- TOC entry 5037 (class 2606 OID 910827)
-- Name: t_depart t_depart_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_depart
    ADD CONSTRAINT t_depart_pkey PRIMARY KEY (uid);


--
-- TOC entry 5047 (class 2606 OID 910829)
-- Name: t_end_storage t_end_storage_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_end_storage
    ADD CONSTRAINT t_end_storage_pkey PRIMARY KEY (uid);


--
-- TOC entry 5049 (class 2606 OID 910831)
-- Name: t_estim_area_const t_estim_area_const_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_estim_area_const
    ADD CONSTRAINT t_estim_area_const_pkey PRIMARY KEY (uid);


--
-- TOC entry 5052 (class 2606 OID 910833)
-- Name: t_estim_area_const_vistoria t_estim_area_const_vistoria_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_estim_area_const_vistoria
    ADD CONSTRAINT t_estim_area_const_vistoria_pkey PRIMARY KEY (uid);


--
-- TOC entry 5054 (class 2606 OID 910835)
-- Name: t_pack t_group_layer_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_pack
    ADD CONSTRAINT t_group_layer_pkey PRIMARY KEY (uid);


--
-- TOC entry 5060 (class 2606 OID 910837)
-- Name: t_groups_permissao t_groups_permissao_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_groups_permissao
    ADD CONSTRAINT t_groups_permissao_pkey PRIMARY KEY (uid);


--
-- TOC entry 5057 (class 2606 OID 910839)
-- Name: t_groups t_groups_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_groups
    ADD CONSTRAINT t_groups_pkey PRIMARY KEY (uid);


--
-- TOC entry 5063 (class 2606 OID 910841)
-- Name: t_imobiliario_recad t_imobiliario_recad_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_imobiliario_recad
    ADD CONSTRAINT t_imobiliario_recad_pkey PRIMARY KEY (cidinscricao);


--
-- TOC entry 5066 (class 2606 OID 910843)
-- Name: t_memo_registro t_memo_registro_copy1_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_memo_registro
    ADD CONSTRAINT t_memo_registro_copy1_pkey PRIMARY KEY (uid);


--
-- TOC entry 5071 (class 2606 OID 910845)
-- Name: t_mensagens_anexos t_mensagens_anexos_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mensagens_anexos
    ADD CONSTRAINT t_mensagens_anexos_pkey PRIMARY KEY (uid);


--
-- TOC entry 5068 (class 2606 OID 910847)
-- Name: t_mensagens t_mensagens_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mensagens
    ADD CONSTRAINT t_mensagens_pkey PRIMARY KEY (uid);


--
-- TOC entry 5074 (class 2606 OID 910849)
-- Name: t_metadados_print t_metadados_print_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_metadados_print
    ADD CONSTRAINT t_metadados_print_pkey PRIMARY KEY (uid);


--
-- TOC entry 5077 (class 2606 OID 910851)
-- Name: t_mobiliario_empresa t_mobiliario_empresa_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mobiliario_empresa
    ADD CONSTRAINT t_mobiliario_empresa_pkey PRIMARY KEY (uid);


--
-- TOC entry 5080 (class 2606 OID 910853)
-- Name: t_mobiliario_servicos t_mobiliario_servicos_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_mobiliario_servicos
    ADD CONSTRAINT t_mobiliario_servicos_pkey PRIMARY KEY (uid);


--
-- TOC entry 5082 (class 2606 OID 910857)
-- Name: t_pack_layer t_pack_layer_pkey1; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_pack_layer
    ADD CONSTRAINT t_pack_layer_pkey1 PRIMARY KEY (fuid_pack, prefixed_name);


--
-- TOC entry 5101 (class 2606 OID 910859)
-- Name: t_tema t_pack_tema_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_tema
    ADD CONSTRAINT t_pack_tema_pkey PRIMARY KEY (uid);


--
-- TOC entry 5084 (class 2606 OID 910861)
-- Name: t_tema_pack t_pack_tema_pkey1; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_tema_pack
    ADD CONSTRAINT t_pack_tema_pkey1 PRIMARY KEY (uid);


--
-- TOC entry 5087 (class 2606 OID 910863)
-- Name: t_renum_logradouros t_renum_logradouros_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_renum_logradouros
    ADD CONSTRAINT t_renum_logradouros_pkey PRIMARY KEY (cod_log_geo);


--
-- TOC entry 5091 (class 2606 OID 910865)
-- Name: t_renum_planilha t_renum_planilha_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_renum_planilha
    ADD CONSTRAINT t_renum_planilha_pkey PRIMARY KEY (uid);


--
-- TOC entry 5094 (class 2606 OID 910867)
-- Name: t_reuniao t_reuniao_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_reuniao
    ADD CONSTRAINT t_reuniao_pkey PRIMARY KEY (uid);


--
-- TOC entry 5097 (class 2606 OID 910869)
-- Name: t_sistema_bool t_sistema_bool_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_sistema_bool
    ADD CONSTRAINT t_sistema_bool_pkey PRIMARY KEY (uid);


--
-- TOC entry 5099 (class 2606 OID 910871)
-- Name: t_sistema_demanda t_sistema_demanda_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_sistema_demanda
    ADD CONSTRAINT t_sistema_demanda_pkey PRIMARY KEY (uid);


--
-- TOC entry 5107 (class 2606 OID 910877)
-- Name: t_users_groups t_users_groups_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_users_groups
    ADD CONSTRAINT t_users_groups_pkey PRIMARY KEY (fuid_users, fuid_groups);


--
-- TOC entry 5110 (class 2606 OID 910879)
-- Name: t_users_log t_users_log_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_users_log
    ADD CONSTRAINT t_users_log_pkey PRIMARY KEY (uid);


--
-- TOC entry 5104 (class 2606 OID 910881)
-- Name: t_users t_users_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_users
    ADD CONSTRAINT t_users_pkey PRIMARY KEY (name);


--
-- TOC entry 5114 (class 2606 OID 910883)
-- Name: tbl_pesq_rapida_permissao tbl_pesq_rapida_permissao_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tbl_pesq_rapida_permissao
    ADD CONSTRAINT tbl_pesq_rapida_permissao_pkey PRIMARY KEY (uid);


--
-- TOC entry 5112 (class 2606 OID 910885)
-- Name: tbl_pesq_rapida tbl_pesq_rapida_pkey; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tbl_pesq_rapida
    ADD CONSTRAINT tbl_pesq_rapida_pkey PRIMARY KEY (uid);


--
-- TOC entry 5006 (class 2606 OID 910887)
-- Name: acesso_audit uid_acesso_audit_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.acesso_audit
    ADD CONSTRAINT uid_acesso_audit_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5008 (class 2606 OID 910889)
-- Name: acesso_settings uid_acesso_settings_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.acesso_settings
    ADD CONSTRAINT uid_acesso_settings_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5010 (class 2606 OID 910891)
-- Name: acesso_tbl_link_acesso uid_acesso_tbl_link_acesso_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.acesso_tbl_link_acesso
    ADD CONSTRAINT uid_acesso_tbl_link_acesso_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5025 (class 2606 OID 910893)
-- Name: t_cius_cnae_denominacao uid_t_cius_cnae_denominacao_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_cnae_denominacao
    ADD CONSTRAINT uid_t_cius_cnae_denominacao_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5027 (class 2606 OID 910895)
-- Name: t_cius_cnae_grupo uid_t_cius_cnae_grupo_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_cnae_grupo
    ADD CONSTRAINT uid_t_cius_cnae_grupo_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5023 (class 2606 OID 910897)
-- Name: t_cius_cnae uid_t_cius_cnae_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_cnae
    ADD CONSTRAINT uid_t_cius_cnae_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5029 (class 2606 OID 910899)
-- Name: t_cius_cnae_secao uid_t_cius_cnae_secao_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_cnae_secao
    ADD CONSTRAINT uid_t_cius_cnae_secao_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5031 (class 2606 OID 910901)
-- Name: t_cius_status_certidao uid_t_cius_status_certidao_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_status_certidao
    ADD CONSTRAINT uid_t_cius_status_certidao_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5033 (class 2606 OID 910903)
-- Name: t_cius_uso_geral uid_t_cius_uso_geral_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.t_cius_uso_geral
    ADD CONSTRAINT uid_t_cius_uso_geral_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 5116 (class 2606 OID 910905)
-- Name: tdirfoto uid_tdirfoto_pk_chk; Type: CONSTRAINT; Schema: app; Owner: -
--

ALTER TABLE ONLY app.tdirfoto
    ADD CONSTRAINT uid_tdirfoto_pk_chk PRIMARY KEY (uid);


--
-- TOC entry 4990 (class 1259 OID 910914)
-- Name: TBL_TEMP_fuid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX "TBL_TEMP_fuid_uindex" ON app."TBL_TEMP" USING btree (fuid);


--
-- TOC entry 4991 (class 1259 OID 910915)
-- Name: TBL_TEMP_objectid_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX "TBL_TEMP_objectid_idx" ON app."TBL_TEMP" USING btree (objectid);


--
-- TOC entry 4994 (class 1259 OID 910916)
-- Name: TBL_TEMP_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX "TBL_TEMP_uid_uindex" ON app."TBL_TEMP" USING btree (uid);


--
-- TOC entry 4995 (class 1259 OID 910917)
-- Name: TBL_THEMES_fuid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX "TBL_THEMES_fuid_uindex" ON app."TBL_THEMES" USING btree (fuid);


--
-- TOC entry 4996 (class 1259 OID 910918)
-- Name: TBL_THEMES_objectid_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX "TBL_THEMES_objectid_idx" ON app."TBL_THEMES" USING btree (objectid);


--
-- TOC entry 4999 (class 1259 OID 910919)
-- Name: TBL_THEMES_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX "TBL_THEMES_uid_uindex" ON app."TBL_THEMES" USING btree (uid);


--
-- TOC entry 5000 (class 1259 OID 910920)
-- Name: TBL_THEMETYPES_fuid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX "TBL_THEMETYPES_fuid_uindex" ON app."TBL_THEMETYPES" USING btree (fuid);


--
-- TOC entry 5001 (class 1259 OID 910921)
-- Name: TBL_THEMETYPES_objectid_idx; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX "TBL_THEMETYPES_objectid_idx" ON app."TBL_THEMETYPES" USING btree (objectid);


--
-- TOC entry 5004 (class 1259 OID 910922)
-- Name: TBL_THEMETYPES_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX "TBL_THEMETYPES_uid_uindex" ON app."TBL_THEMETYPES" USING btree (uid);


--
-- TOC entry 5108 (class 1259 OID 910923)
-- Name: UNIQUE; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX "UNIQUE" ON app.t_users_log USING btree (uid);


--
-- TOC entry 5064 (class 1259 OID 910924)
-- Name: idx_cons_uso_e_ocupacao_id_copy_copy1; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_cons_uso_e_ocupacao_id_copy_copy1 ON app.t_memo_registro USING btree (id);


--
-- TOC entry 5088 (class 1259 OID 910925)
-- Name: idx_ident; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_ident ON app.t_renum_planilha USING btree (ident);


--
-- TOC entry 5061 (class 1259 OID 910926)
-- Name: idx_imob_recad; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_imob_recad ON app.t_imobiliario_recad USING btree (cidinscricao);


--
-- TOC entry 5089 (class 1259 OID 910927)
-- Name: idx_ordem; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_ordem ON app.t_renum_planilha USING btree (ordem);


--
-- TOC entry 5016 (class 1259 OID 910928)
-- Name: idx_t_anexos_insc; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_t_anexos_insc ON app.t_anexos USING btree (inscricao);


--
-- TOC entry 5017 (class 1259 OID 910929)
-- Name: idx_t_anexos_uid; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_t_anexos_uid ON app.t_anexos USING btree (uid);


--
-- TOC entry 5050 (class 1259 OID 910930)
-- Name: idx_t_estim_area_const; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_t_estim_area_const ON app.t_estim_area_const_vistoria USING btree (uid);


--
-- TOC entry 5078 (class 1259 OID 910931)
-- Name: idx_t_mob_service; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_t_mob_service ON app.t_mobiliario_servicos USING btree (uid);


--
-- TOC entry 5085 (class 1259 OID 910932)
-- Name: idx_t_renum_log_uid; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_t_renum_log_uid ON app.t_renum_logradouros USING btree (uid);


--
-- TOC entry 5075 (class 1259 OID 910933)
-- Name: idx_tmob_empresa; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX idx_tmob_empresa ON app.t_mobiliario_empresa USING btree (uid);


--
-- TOC entry 5015 (class 1259 OID 911023)
-- Name: sidx_geo_lote_31983_new01_geom; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX sidx_geo_lote_31983_new01_geom ON app.geo_lote_31983 USING gist (geom);


--
-- TOC entry 5055 (class 1259 OID 911093)
-- Name: t_groups_fuid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX t_groups_fuid_uindex ON app.t_groups USING btree (fuid);


--
-- TOC entry 5058 (class 1259 OID 911094)
-- Name: t_groups_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX t_groups_uid_uindex ON app.t_groups USING btree (uid);


--
-- TOC entry 5072 (class 1259 OID 911095)
-- Name: t_mensagens_anexos_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX t_mensagens_anexos_uid_uindex ON app.t_mensagens_anexos USING btree (uid);


--
-- TOC entry 5069 (class 1259 OID 911096)
-- Name: t_mensagens_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX t_mensagens_uid_uindex ON app.t_mensagens USING btree (uid);


--
-- TOC entry 5092 (class 1259 OID 911097)
-- Name: t_reuniao_fuid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX t_reuniao_fuid_uindex ON app.t_reuniao USING btree (fuid);


--
-- TOC entry 5095 (class 1259 OID 911098)
-- Name: t_reuniao_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX t_reuniao_uid_uindex ON app.t_reuniao USING btree (uid);


--
-- TOC entry 5102 (class 1259 OID 911099)
-- Name: t_users_fuid_groups_index; Type: INDEX; Schema: app; Owner: -
--

CREATE INDEX t_users_fuid_groups_index ON app.t_users USING btree (fuid_groups);


--
-- TOC entry 5105 (class 1259 OID 911100)
-- Name: t_users_uid_uindex; Type: INDEX; Schema: app; Owner: -
--

CREATE UNIQUE INDEX t_users_uid_uindex ON app.t_users USING btree (uid);


-- Completed on 2026-07-24 16:07:53 UTC

--
-- PostgreSQL database dump complete
--

