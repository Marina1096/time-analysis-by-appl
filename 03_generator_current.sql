/* ============================================================
  0.  Очистка прежних объектов
============================================================ */
DROP PROCEDURE IF EXISTS generate_march25_data();
DROP FUNCTION  IF EXISTS add_work_hours(timestamp, integer, date[]);
DROP PROCEDURE IF EXISTS close_at_month_end ();

/* ============================================================
  1.  add_work_hours(ts_start, hrs, holidays[])
      рабочие часы: 09:00-18:00 (М-Пт)
      гарантирует end_time ≤ 17:59:59 и только рабочие дни
============================================================ */
CREATE OR REPLACE FUNCTION add_work_hours(
    ts_start TIMESTAMP,
    hrs      INTEGER,
    hol      DATE[]
) RETURNS TIMESTAMP
LANGUAGE plpgsql AS
$$
DECLARE
    cur_ts  TIMESTAMP := ts_start;
    remain  INTEGER   := hrs;
    wrk_end TIME      := TIME '18:00';
    secs    INTEGER;
BEGIN
    WHILE remain > 0 LOOP
        IF extract(ISODOW FROM cur_ts) IN (6,7)
           OR cur_ts::date = ANY(hol) THEN         -- выходной/праздник
            cur_ts := (cur_ts::date + 1) + TIME '09:00';
            CONTINUE;
        END IF;

        IF cur_ts::time < TIME '09:00' THEN
            cur_ts := date_trunc('day',cur_ts) + TIME '09:00';
        ELSIF cur_ts::time >= wrk_end THEN
            cur_ts := (cur_ts::date + 1) + TIME '09:00';
            CONTINUE;
        END IF;

        secs := EXTRACT(EPOCH FROM (wrk_end - cur_ts::time));

        IF remain*3600 <= secs THEN
            cur_ts := cur_ts + make_interval(secs := remain*3600);
            IF cur_ts::time = TIME '18:00' THEN        -- 18:00 → 17:59:59
                cur_ts := cur_ts - INTERVAL '1 second';
            END IF;
            RETURN cur_ts;
        END IF;

        remain := remain - CEIL(secs/3600.0)::INT;
        cur_ts := (cur_ts::date + 1) + TIME '09:00';
    END LOOP;
    RETURN cur_ts;
END;
$$;

/* ============================================================
  2.  Генератор данных за март-2025
     ----------------------------------------------------------
     • «Возврат на доработку» = stage_result_id 5
     • «Отклонено» (недостоверные документы) = id 7
============================================================ */
CREATE OR REPLACE PROCEDURE generate_march25_data()
LANGUAGE plpgsql
AS $$
DECLARE
    credit_types TEXT[] := ARRAY['Потребительский кредит','Автокредит','Кредитные карты'];
    holidays     DATE[] := ARRAY['2025-03-08'];
    credit_min   INT[]  := ARRAY[  50000,  500000,   20000];
    credit_max   INT[]  := ARRAY[ 500000, 5000000,  300000];

    doc_return   TEXT[] := ARRAY[
        'Скан паспорта нечитабелен','Нет справки 2-НДФЛ',
        'Указан истёкший срок паспорта','ФИО в заявке не совпадает с паспортом','Нет трудового договора'];
    doc_fix_ok CONSTANT TEXT := 'После доработки исправления успешно приняты';
    cond_comments TEXT[] := ARRAY[
        'Одобрено с увеличением ставки','Одобрено с уменьшением срока',
        'Одобрено с увеличением срока','Одобрено при залоге',
        'Одобрено при страховании','Одобрено при созаемщике',
        'Одобрено при уменьшении суммы'];

    work_day DATE; br RECORD; app_cnt INT;
    cl_id INT; mgr_id INT; app_id INT; is_online BOOLEAN;
    next_start TIMESTAMP; end_ts TIMESTAMP;
    fast_app BOOLEAN; returned_docs BOOLEAN;
    stage_idx INT; dur_min INT; dur_max INT; dur_h INT;
    score INT; res_name TEXT; res_id INT; comment_txt TEXT;
    rnd REAL;
BEGIN
    TRUNCATE loan_applications          RESTART IDENTITY CASCADE;
    TRUNCATE application_processing_log RESTART IDENTITY;
    TRUNCATE scoring_results            RESTART IDENTITY;

    FOR work_day IN
        SELECT d::date
        FROM generate_series('2025-03-01'::DATE,'2025-03-31','1 day') g(d)
    LOOP
        FOR br IN SELECT branch_id FROM branch_dict LOOP
            app_cnt := 5 + floor(random()*6)::INT;

            FOR i IN 1..app_cnt LOOP
                /* --- клиент и менеджер --- */
                SELECT client_id  INTO cl_id FROM client_dict  ORDER BY random() LIMIT 1;
                SELECT manager_id INTO mgr_id FROM manager_dict
                 WHERE branch_id = br.branch_id ORDER BY random() LIMIT 1;

                /* --- старт «Подачи заявки» --- */
                is_online := random() < 0.40;

                IF is_online THEN
                    next_start := work_day
                                + make_interval(hours := floor(random()*24)::INT)
                                + make_interval(mins  := floor(random()*60)::INT);
                ELSE
                    next_start := work_day
                                + make_interval(hours := 9 + floor(random()*9)::INT)
                                + make_interval(mins  := floor(random()*60)::INT);
                    IF extract(ISODOW FROM next_start) IN (6,7)
                       OR next_start::date = ANY(holidays) THEN
                        CONTINUE;
                    END IF;
                END IF;

                /* --- шапка заявки --- */
                INSERT INTO loan_applications
                       (client_id, credit_type, is_online,
                        amount_requested, branch_id, manager_id, creation_date)
                SELECT cl_id,
                       credit_types[cidx],
                       is_online,
                       round((random()*(credit_max[cidx]-credit_min[cidx]) + credit_min[cidx])::NUMERIC,2),
                       br.branch_id, mgr_id, next_start
                FROM (SELECT 1 + floor(random()*array_length(credit_types,1))::INT AS cidx) s
                RETURNING application_id INTO app_id;

                fast_app      := random() < 0.70;
                returned_docs := FALSE;
                stage_idx     := 1;

                WHILE stage_idx <= 4 LOOP
                    CASE stage_idx
                        WHEN 1 THEN dur_min := 1; dur_max := 4;
                        WHEN 2 THEN dur_min := 3; dur_max := 9;
                        WHEN 3 THEN dur_min := 1; dur_max := 3;
                        ELSE      dur_min := 3; dur_max := 10;
                    END CASE;

                    dur_h := CASE
                               WHEN fast_app
                                 THEN dur_min + floor(random()*((dur_max-dur_min)/2 + 1))
                               ELSE dur_min + floor(random()*(dur_max-dur_min + 1))
                             END;
                    comment_txt := NULL;

                    /* ---------- ЭТАП 1 ---------- */
                    IF stage_idx = 1 THEN
                        res_name := CASE WHEN random() < 0.05
                                          THEN 'отозвана клиентом'
                                          ELSE 'завершено' END;

                        IF is_online THEN
                            end_ts := next_start + make_interval(hours := dur_h);
                        ELSE
                            IF (next_start + make_interval(hours := dur_h))::date != next_start::date
                               OR (next_start + make_interval(hours := dur_h))::time >= TIME '18:00'
                            THEN
                                end_ts := next_start::date + TIME '18:00' - INTERVAL '1 second';
                            ELSE
                                end_ts := next_start + make_interval(hours := dur_h);
                            END IF;
                        END IF;

                    /* ---------- ЭТАП 2 ---------- */
                    ELSIF stage_idx = 2 THEN
                        rnd := random();

                        IF rnd < 0.05 THEN
                            res_name := 'отозвана клиентом';

                        ELSIF rnd < 0.10 THEN         -- 5 %  ⇒ отклонено (id = 7)
                            res_name    := 'отклонено';
                            comment_txt := 'Отказ: недостоверные документы';

                        ELSIF NOT returned_docs AND rnd < 0.20 THEN
                            res_name      := 'возврат на доработку';
                            returned_docs := TRUE;
                            comment_txt   := doc_return[1 + floor(random()*array_length(doc_return,1))::INT];

                        ELSE
                            res_name := 'завершено';
                            IF returned_docs THEN
                                comment_txt := doc_fix_ok;
                            END IF;
                        END IF;

                        /* выравниваем старт 09-17 */
                        IF next_start::time < TIME '09:00'
                           OR next_start::time >= TIME '18:00' THEN
                            next_start := (CASE
                                              WHEN next_start::time >= TIME '18:00'
                                                   THEN next_start::date + 1
                                              ELSE next_start::date
                                           END) + TIME '09:00';
                        END IF;
                        WHILE extract(ISODOW FROM next_start) IN (6,7)
                              OR next_start::date = ANY(holidays) LOOP
                            next_start := next_start::date + 1 + TIME '09:00';
                        END LOOP;

                        end_ts := add_work_hours(next_start, dur_h, holidays);

                    /* ---------- ЭТАП 3 ---------- */
                    ELSIF stage_idx = 3 THEN
                        score := CASE
                                   WHEN random() < 0.15 THEN 81 + floor(random()*20)::INT
                                   WHEN random() < 0.85 THEN 30 + floor(random()*51)::INT
                                   ELSE floor(random()*30)::INT
                                 END;
                        res_name := 'завершено';
                        end_ts   := next_start + make_interval(hours := dur_h);

                    /* ---------- ЭТАП 4 ---------- */
                    ELSE
                        IF score < 30 OR score > 80 THEN
                            IF score < 30 THEN
                                res_name    := 'отклонено';
                                comment_txt := format('Автоотклонение: скоринг %s < 30',score);
                            ELSE
                                res_name    := 'одобрено';
                                comment_txt := format('Автоодобрение: скоринг %s > 80',score);
                            END IF;
                            end_ts := next_start + INTERVAL '1 hour';
                        ELSE
                            IF next_start::time < TIME '09:00'
                               OR next_start::time >= TIME '18:00' THEN
                                next_start := (CASE
                                                  WHEN next_start::time >= TIME '18:00'
                                                       THEN next_start::date + 1
                                                  ELSE next_start::date
                                               END) + TIME '09:00';
                            END IF;
                            WHILE extract(ISODOW FROM next_start) IN (6,7)
                                  OR next_start::date = ANY(holidays) LOOP
                                next_start := next_start::date + 1 + TIME '09:00';
                            END LOOP;

                            rnd := random();
                            IF rnd < 0.05 THEN
                                res_name    := 'отозвана клиентом';
                                comment_txt := 'Заявка отозвана клиентом';
                            ELSIF rnd < 0.15 THEN
                                res_name    := 'отклонено';
                                comment_txt := 'Отказ: недостаточный подтверждённый доход';
                            ELSIF rnd < 0.65 THEN
                                res_name    := 'одобрено с условиями';
                                comment_txt := cond_comments[1 + floor(random()*array_length(cond_comments,1))::INT];
                            ELSE
                                res_name    := 'одобрено';
                                comment_txt := 'Одобрено менеджером';
                            END IF;
                            end_ts := add_work_hours(next_start, dur_h, holidays);
                        END IF;
                    END IF;

                    /* ---------- выбор id результата ---------- */
                    IF stage_idx = 2 AND res_name = 'отклонено' THEN
                        res_id := 7;          -- фиксация id «7»
                    ELSE
                        SELECT stage_result_id
                          INTO res_id
                          FROM stage_result_dict
                         WHERE stage_id = stage_idx
                           AND stage_result_name = res_name
                         ORDER BY stage_result_id
                         LIMIT 1;             -- «возврат» вернёт id = 5
                    END IF;

                    INSERT INTO application_processing_log
                            (application_id,stage_id,stage_result_id,
                             start_date,end_date,comments)
                    VALUES (app_id,stage_idx,res_id,next_start,end_ts,comment_txt);

                    IF stage_idx = 3 THEN
                        INSERT INTO scoring_results(client_id,scoring_grade,scoring_date)
                        VALUES (cl_id,score,end_ts);
                    END IF;

                    IF res_name IN ('отозвана клиентом','отклонено') THEN EXIT; END IF;

                    IF stage_idx = 2 AND res_name = 'возврат на доработку' THEN
                        next_start := end_ts;
                        stage_idx  := 1;
                        CONTINUE;
                    END IF;

                    next_start := end_ts;
                    stage_idx  := stage_idx + 1;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;
END;
$$;

/* ============================================================
  3.  Пост-процедура: обрезать «апрельские» хвосты
============================================================ */
CREATE OR REPLACE PROCEDURE close_at_month_end()
LANGUAGE plpgsql
AS $$
DECLARE
    app_rec RECORD; first_april_id INT; last_march_id INT; v_in_process INT;
BEGIN
    FOR app_rec IN SELECT DISTINCT application_id FROM application_processing_log LOOP
        SELECT MIN(stage_id)
          INTO first_april_id
          FROM application_processing_log
         WHERE application_id = app_rec.application_id
           AND (start_date >= DATE '2025-04-01'
             OR (end_date IS NOT NULL AND end_date >= DATE '2025-04-01'));

        IF first_april_id IS NULL THEN CONTINUE; END IF;

        SELECT MAX(stage_id)
          INTO last_march_id
          FROM application_processing_log
         WHERE application_id = app_rec.application_id
           AND stage_id < first_april_id;

        DELETE FROM application_processing_log
         WHERE application_id = app_rec.application_id
           AND stage_id >= first_april_id;

        IF last_march_id IS NOT NULL THEN
            SELECT stage_result_id
              INTO v_in_process
              FROM stage_result_dict
             WHERE stage_id = last_march_id
               AND stage_result_name = 'в обработке'
             ORDER BY stage_result_id LIMIT 1;

            IF v_in_process IS NOT NULL THEN
                UPDATE application_processing_log
                   SET stage_result_id = v_in_process,
                       end_date        = NULL,
                       comments        = NULL
                 WHERE application_id = app_rec.application_id
                   AND stage_id       = last_march_id;
            ELSE
                UPDATE application_processing_log
                   SET end_date = NULL
                 WHERE application_id = app_rec.application_id
                   AND stage_id       = last_march_id;
            END IF;
        END IF;
    END LOOP;
END;
$$;

/* ============================================================
  4.  Генерация данных + пост-обработка
============================================================ */
CALL generate_march25_data();
CALL close_at_month_end();
