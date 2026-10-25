/*
============================================================
DATALOAD 1 - SOMENTE DADOS REAIS INFORMADOS
============================================================

/*
-- PLANOS
INSERT INTO plans (id, name, description, price, duration_days, currency)
VALUES
(
    1,
    'Aether Pulse',
    'Quantidade de cadastro limitada a 10 funcionários; quantidade de analistas e administradores limitada a 2; acompanhamento mensal',
    3300.00,
    30,
    'Reais'
),
(
    2,
    'Aether Horizon',
    'Tudo do plano Aether Pulse; quantidade de cadastro de funcionários ilimitada; acompanhamento trimestral',
    9400.00,
    90,
    'Reais'
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    price = EXCLUDED.price,
    duration_days = EXCLUDED.duration_days,
    currency = EXCLUDED.currency,
    updated_at = CURRENT_TIMESTAMP;


-- GASES 
INSERT INTO gases (id, name, type, measurement, gwp)
VALUES
(
    1,
    'Monóxido de Carbono',
    'Gás de emissão poluente',
    'Moderado',
    2
),
(
    2,
    'Óxido Nitroso',
    'Gás de emissão poluente',
    'Alto',
    273
),
(
    3,
    'Hexafluoreto de Enxofre',
    'Gás de emissão poluente',
    'Extremo',
    23500
),
(
    4,
    'Trifluorometano',
    'Gás de emissão poluente',
    'Extremo',
    14800
),
(
    5,
    'Tetrafluoroetano',
    'Gás de emissão poluente',
    'Alto',
    1430
),
(
    6,
    'Óxidos de Nitrogênio',
    'Gás de emissão poluente',
    'Alto',
    298
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    type = EXCLUDED.type,
    measurement = EXCLUDED.measurement,
    gwp = EXCLUDED.gwp,
    updated_at = CURRENT_TIMESTAMP;



SELECT setval(
    pg_get_serial_sequence('plans', 'id'),
    COALESCE((SELECT MAX(id) FROM plans), 1),
    EXISTS (SELECT 1 FROM plans)
);

SELECT setval(
    pg_get_serial_sequence('gases', 'id'),
    COALESCE((SELECT MAX(id) FROM gases), 1),
    EXISTS (SELECT 1 FROM gases)
);
*/


/*
============================================================
FIM DO DATALOAD REAL
============================================================
*/


-- ==========================================================
-- DATALOAD 2 - DADOS REAIS + MOCKS PARA TESTES
-- ==========================================================


-- ----------------------------------------------------------
-- PLANOS REAIS
-- ----------------------------------------------------------

INSERT INTO plans (id, name, description, price, duration_days, currency)
VALUES
(
    1,
    'Aether Pulse',
    'Quantidade de cadastro limitada a 10 funcionários; quantidade de analistas e administradores limitada a 2; acompanhamento mensal',
    3300.00,
    30,
    'Reais'
),
(
    2,
    'Aether Horizon',
    'Tudo do plano Aether Pulse; quantidade de cadastro de funcionários ilimitada; acompanhamento trimestral',
    9400.00,
    90,
    'Reais'
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    price = EXCLUDED.price,
    duration_days = EXCLUDED.duration_days,
    currency = EXCLUDED.currency,
    updated_at = CURRENT_TIMESTAMP;


-- ----------------------------------------------------------
-- PLANOS FICTÍCIOS (MOCK)
-- Criados exclusivamente para testes.
-- ----------------------------------------------------------

INSERT INTO plans (id, name, description, price, duration_days, currency)
VALUES
(
    3,
    'Aether Essencial (MOCK)',
    'Plano fictício para testes; limite de 5 funcionários; acompanhamento mensal',
    1500.00,
    30,
    'Reais'
),
(
    4,
    'Aether Enterprise (MOCK)',
    'Plano fictício para testes; funcionários ilimitados; acompanhamento mensal personalizado',
    15000.00,
    30,
    'Reais'
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    price = EXCLUDED.price,
    duration_days = EXCLUDED.duration_days,
    currency = EXCLUDED.currency,
    updated_at = CURRENT_TIMESTAMP;


-- ----------------------------------------------------------
-- GASES REAIS INFORMADOS
-- IDs ajustados para evitar duplicidade.
-- ----------------------------------------------------------

INSERT INTO gases (id, name, type, measurement, gwp)
VALUES
(
    1,
    'Monóxido de Carbono',
    'Gás de emissão poluente',
    'Moderado',
    2
),
(
    2,
    'Óxido Nitroso',
    'Gás de emissão poluente',
    'Alto',
    273
),
(
    3,
    'Hexafluoreto de Enxofre',
    'Gás de emissão poluente',
    'Extremo',
    23500
),
(
    4,
    'Trifluorometano',
    'Gás de emissão poluente',
    'Extremo',
    14800
),
(
    5,
    'Tetrafluoroetano',
    'Gás de emissão poluente',
    'Alto',
    1430
),
(
    6,
    'Óxidos de Nitrogênio',
    'Gás de emissão poluente',
    'Alto',
    298
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    type = EXCLUDED.type,
    measurement = EXCLUDED.measurement,
    gwp = EXCLUDED.gwp,
    updated_at = CURRENT_TIMESTAMP;


-- ----------------------------------------------------------
-- GASES FICTÍCIOS (MOCK)
-- Registros artificiais para testar consultas e telas.
-- Não representam dados científicos reais.
-- ----------------------------------------------------------

INSERT INTO gases (id, name, type, measurement, gwp)
VALUES
(
    7,
    'Gás de Teste A (MOCK)',
    'Dado fictício para teste',
    'Baixo',
    1.5
),
(
    8,
    'Gás de Teste B (MOCK)',
    'Dado fictício para teste',
    'Alto',
    120
),
(
    9,
    'Gás de Teste C (MOCK)',
    'Dado fictício para teste',
    'Extremo',
    5000
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    type = EXCLUDED.type,
    measurement = EXCLUDED.measurement,
    gwp = EXCLUDED.gwp,
    updated_at = CURRENT_TIMESTAMP;


-- ----------------------------------------------------------
-- SINCRONIZA AS SEQUÊNCIAS DE IDs
-- Necessário porque os IDs foram inseridos manualmente.
-- ----------------------------------------------------------

SELECT setval(
    pg_get_serial_sequence('plans', 'id'),
    COALESCE((SELECT MAX(id) FROM plans), 1),
    EXISTS (SELECT 1 FROM plans)
);

SELECT setval(
    pg_get_serial_sequence('gases', 'id'),
    COALESCE((SELECT MAX(id) FROM gases), 1),
    EXISTS (SELECT 1 FROM gases)
);


-- ----------------------------------------------------------
-- CONSULTAS PARA CONFERIR O DATALOAD
-- ----------------------------------------------------------

SELECT *
FROM plans
ORDER BY id;

SELECT *
FROM gases
ORDER BY id;
