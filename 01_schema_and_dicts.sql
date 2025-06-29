DROP TABLE IF EXISTS branch_dict CASCADE;
CREATE TABLE branch_dict (
    branch_id        SERIAL PRIMARY KEY,
    region_name      VARCHAR(200) NOT NULL,
    branch_city_name VARCHAR(200) NOT NULL
);


DROP TABLE IF EXISTS manager_dict CASCADE;
CREATE TABLE manager_dict (
    manager_id  SERIAL PRIMARY KEY,
    first_name        VARCHAR(50) NOT NULL,
    last_name     VARCHAR(50) NOT NULL,
    second_name  VARCHAR(50),
    branch_id   INT NOT NULL REFERENCES branch_dict(branch_id) ON DELETE CASCADE
);


DROP TABLE IF EXISTS client_dict CASCADE;
CREATE TABLE client_dict (
    client_id     SERIAL PRIMARY KEY,
    first_name    VARCHAR(50) NOT NULL,
    last_name     VARCHAR(50) NOT NULL,
    second_name   VARCHAR(50)
);


DROP TABLE IF EXISTS loan_applications CASCADE;
CREATE TABLE loan_applications (
    application_id    SERIAL PRIMARY KEY,
    client_id         INT  NOT NULL REFERENCES client_dict(client_id)   ON DELETE RESTRICT,
    credit_type       VARCHAR(100) NOT NULL,
    is_online         BOOLEAN      NOT NULL,
    amount_requested  NUMERIC      CHECK (amount_requested > 0),
    branch_id         INT  NOT NULL REFERENCES branch_dict(branch_id)   ON DELETE RESTRICT,
    manager_id        INT          REFERENCES manager_dict(manager_id)  ON DELETE SET NULL,
    creation_date     TIMESTAMP    NOT NULL );


DROP TABLE IF EXISTS stage_dict CASCADE;
CREATE TABLE stage_dict (
    stage_id    SERIAL PRIMARY KEY,
    stage_name  VARCHAR(200) UNIQUE NOT NULL
);


DROP TABLE IF EXISTS stage_result_dict CASCADE;
CREATE TABLE stage_result_dict (
    stage_result_id   SERIAL PRIMARY KEY,
    stage_id          INT NOT NULL REFERENCES stage_dict(stage_id) ON DELETE CASCADE,
    stage_result_name VARCHAR(200) NOT NULL,
    CONSTRAINT uq_stage_result UNIQUE (stage_id, stage_result_name)
);


DROP TABLE IF EXISTS application_processing_log CASCADE;
CREATE TABLE application_processing_log (
    log_id          SERIAL PRIMARY KEY,
    application_id  INT NOT NULL REFERENCES loan_applications(application_id) ON DELETE CASCADE,
    stage_id        INT NOT NULL REFERENCES stage_dict(stage_id)              ON DELETE RESTRICT,
    stage_result_id INT NOT NULL REFERENCES stage_result_dict(stage_result_id) ON DELETE RESTRICT,
    start_date      TIMESTAMP NOT NULL,
    end_date        TIMESTAMP,
    comments        TEXT,
    CONSTRAINT chk_time_order CHECK (end_date IS NULL OR end_date >= start_date)
);


DROP TABLE IF EXISTS scoring_results CASCADE;
CREATE TABLE scoring_results (
    scoring_id     SERIAL PRIMARY KEY,
    client_id      INT NOT NULL REFERENCES client_dict(client_id) ON DELETE CASCADE,
    scoring_grade  NUMERIC      NOT NULL,
    scoring_date   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);


-- Заполнение этапов заявки
INSERT INTO stage_dict (stage_name) VALUES
    ('Подача заявки'),
    ('Проверка документов'),
    ('Скоринг'),
    ('Принятие решения');

-- Заполнение результатов этапа
-- 1. Подача заявки (id = 1)
INSERT INTO stage_result_dict (stage_id, stage_result_name) VALUES
    (1, 'завершено'),
    (1, 'отозвана клиентом');

-- 2. Проверка документов (id = 2)
INSERT INTO stage_result_dict (stage_id, stage_result_name) VALUES
    (2, 'в обработке'),
    (2, 'завершено'),
    (2, 'возврат на доработку'),
    (2, 'отозвана клиентом'),
	(2, 'отклонено');

-- 3. Скоринг (id = 3)
INSERT INTO stage_result_dict (stage_id, stage_result_name) VALUES
    (3, 'в обработке'),
    (3, 'завершено');

-- 4. Принятие решения (id = 4)
INSERT INTO stage_result_dict (stage_id, stage_result_name) VALUES
    (4, 'в обработке'),
    (4, 'одобрено'),
    (4, 'одобрено с условиями'),
    (4, 'отклонено'),
    (4, 'отозвана клиентом');

/*--------------------------------------------------------------
Данные филиалов (10 шт.)
--------------------------------------------------------------*/
INSERT INTO branch_dict (region_name, branch_city_name) VALUES
('Москва',               'Москва'),             -- id = 1
('Санкт-Петербург',      'Санкт-Петербург'),    -- id = 2
('Архангельская область','Архангельск'),        -- id = 3
('Ставропольский край', 'Ставрополь'),       -- id = 4
('Республика Татарстан', 'Казань'),             -- id = 5
('Нижегородская область','Нижний Новгород'),    -- id = 6
('Мурманская область',    'Мурманск'),             -- id = 7
('Ростовская область',   'Ростов-на-Дону'),     -- id = 8
('Смоленская область',  'Смоленск'),          -- id = 9
('Краснодарский край',   'Краснодар');          -- id = 10

/*--------------------------------------------------------------
 Данные менеджеров (30 записей, по 3 на филиал)
--------------------------------------------------------------*/
INSERT INTO manager_dict (first_name, last_name, second_name, branch_id) VALUES
-- id_branch = 1 (Москва)
('Иван',      'Иванов',     'Иванович',      1),
('Пётр',      'Петров',     'Петрович',      1),
('Сидор',     'Сидоров',    'Сидорович',     1),

-- id_branch = 2 (Санкт-Петербург)
('Алексей',   'Смирнов',    'Алексеевич',    2),
('Владимир',  'Кузнецов',   'Владимирович',  2),
('Максим',    'Попов',      'Максимович',    2),

-- id_branch = 3 (Новосибирск)
('Егор',      'Васильев',   'Егорович',      3),
('Дмитрий',   'Новиков',    'Дмитриевич',    3),
('Глеб',      'Морозов',    'Глебович',      3),

-- id_branch = 4 (Екатеринбург)
('Илья',      'Волков',     'Ильич',         4),
('Артём',     'Зайцев',     'Артёмьевич',    4),
('Вячеслав',  'Соловьёв',   'Вячеславович',  4),

-- id_branch = 5 (Казань)
('Михаил',    'Павлов',     'Михайлович',    5),
('Сергей',    'Сёмин',      'Сергеевич',     5),
('Андрей',    'Григорьев',  'Андреевич',     5),

-- id_branch = 6 (Нижний Новгород)
('Григорий',  'Мельников',  'Григорьевич',   6),
('Роман',     'Козлов',     'Романович',     6),
('Павел',     'Тихонов',    'Павлович',      6),

-- id_branch = 7 (Самара)
('Виктор',    'Беляев',     'Викторович',    7),
('Ярослав',   'Комаров',    'Ярославович',   7),
('Кирилл',    'Орлов',      'Кириллович',    7),

-- id_branch = 8 (Ростов-на-Дону)
('Никита',    'Киселёв',    'Никитич',       8),
('Олег',      'Макаров',    'Олегович',      8),
('Руслан',    'Андреев',    'Русланович',    8),

-- id_branch = 9 (Челябинск)
('Станислав', 'Гусев',      'Станиславович', 9),
('Валерий',   'Калинин',    'Валерьевич',    9),
('Эдуард',    'Борисов',    'Эдуардович',    9),

-- id_branch = 10 (Краснодар)
('Леонид',    'Абрамов',    'Леонидович',   10),
('Аркадий',   'Суханов',    'Аркадьевич',   10),
('Пётр',      'Семёнов',    'Семёнович',    10);