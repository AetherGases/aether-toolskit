/*
============================================================
DATALOAD 1 - DADOS REAIS 
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

BEGIN;


INSERT INTO addresses (id, zip_code, street, number, complement, city, neighborhood, state, country) VALUES
(1, '01001000', 'Praça da Sé', '100', NULL, 'São Paulo', 'Sé', 'SP', 'Brasil'),
(2, '01310100', 'Avenida Paulista', '1000', 'Bloco A', 'São Paulo', 'Bela Vista', 'SP', 'Brasil'),
(3, '80010000', 'Rua XV de Novembro', '250', NULL, 'Curitiba', 'Centro', 'PR', 'Brasil');

INSERT INTO storage_files (id, name, path) VALUES
(1, 'logo-aether.png', '/uploads/mock/logo-aether.png'),
(2, 'inventario-2025.pdf', '/uploads/mock/inventario-2025.pdf'),
(3, 'relatorio-emissoes-2025.pdf', '/uploads/mock/relatorio-emissoes-2025.pdf');

INSERT INTO plans (id, name, description, price, duration_days, currency) VALUES
(1, 'Aether Pulse', 'Até 10 funcionários, até 2 analistas/administradores e acompanhamento mensal.', 3300.00, 30, 'Reais'),
(2, 'Aether Horizon', 'Recursos do Pulse, funcionários ilimitados e acompanhamento trimestral.', 9400.00, 90, 'Reais'),


INSERT INTO gases (id, name, type, measurement, gwp) VALUES
(1, 'Monóxido de Carbono', 'gás de emissão poluente', 'Moderado', 2),
(2, 'Óxido Nitroso', 'gás de emissão poluente', 'Alto', 273),
(3, 'Hexafluoreto de Enxofre', 'gás de emissão poluente', 'Extremo', 23500),
(4, 'Trifluorometano', 'gás de emissão poluente', 'Extremo', 14800),
(5, 'Tetrafluoroetano', 'gás de emissão poluente', 'Alto', 1430),
(6, 'Óxidos de Nitrogênio', 'gás de emissão poluente', 'Alto', 298),
(7, 'Dióxido de Carbono (MOCK)', 'gás de referência para testes', 'Alto', 1),
(8, 'Metano (MOCK)', 'gás de referência para testes', 'Alto', 28),
(9, 'Gás de Teste A (MOCK)', 'dado fictício para testes', 'Baixo', 1.5);

INSERT INTO administrators (id, email, password) VALUES
(1, 'admin.mock@aether.test', '$argon2id$MOCK_HASH_NOT_FOR_AUTHENTICATION');

INSERT INTO permissions (id, name, description, url) VALUES
(1, 'Admin da empresa', 'Cadastrar, consultar e gerenciar relátorios', '/gerente'),
(2, 'Funcionário da empresa', 'Adicionar relatórios e vizualizar métricas', '/funcionarios');

INSERT INTO parana_climate_seals (id, date_achievement, current_score) VALUES
(1, '2024-12-15', 72.5),
(2, '2025-12-15', 81.0);

INSERT INTO companies (id, name, trade_name, cnpj, size, registration_date, tax_id, email, address_id) VALUES
(1, 'Empresa Exemplo Alimentos Ltda. (MOCK)', 'Exemplo Alimentos', '12345678000195', 'grande', '2024-01-15', 'ISENTO-MOCK-001', 'contato@exemplo-alimentos.test', 1),
(2, 'Indústria Modelo Sustentável Ltda. (MOCK)', 'Modelo Sustentável', '98765432000198', 'medio', '2024-06-10', 'ISENTO-MOCK-002', 'contato@modelo-sustentavel.test', 2),
(3, 'Cooperativa Verde Paraná (MOCK)', 'Verde Paraná', '11222333000181', 'pequeno', '2025-02-20', 'ISENTO-MOCK-003', 'contato@verde-parana.test', 3);

INSERT INTO units (id, name, company_id, address_id, cnpj, cnae) VALUES
(1, 'Unidade Industrial São Paulo (MOCK)', 1, 1, '12345678000195', '1011201'),
(2, 'Centro de Distribuição Paulista (MOCK)', 2, 2, '98765432000198', '5211701'),
(3, 'Unidade Curitiba (MOCK)', 3, 3, '11222333000181', '1011201');

INSERT INTO telephone_companies (id, telephone, company_id) VALUES
(1, '+551130001001', 1), (2, '+551130001002', 2), (3, '+554130001003', 3);


INSERT INTO permission_groups (id, name, company_id) VALUES
(1, 'Admin da empresa (MOCK)', 1),
(2, 'Gestor ambiental (MOCK)', 1),
(3, 'Admin da empresa (MOCK)', 2),
(4, 'Gestor ambiental (MOCK)', 2),
(5, 'Admin da empresa (MOCK)', 3),
(6, 'Gestor ambiental (MOCK)', 3);


INSERT INTO sectors (id, name, description, unit_id, company_id) VALUES
(1, 'Produção', 'Área de produção industrial (MOCK)', 1, 1),
(2, 'Logística', 'Transporte e armazenamento (MOCK)', 2, 2),
(3, 'Utilidades', 'Energia, refrigeração e utilidades (MOCK)', 3, 3);



INSERT INTO employees (id, cpf, company_id, permission_group_id, unit_id, sector_id, name, email, phone, password_hash, status, storage_file_id) VALUES
(1, '12345678901', 1, 1, 1, 1, 'Ana Administradora (MOCK)', 'ana.admina@exemplo.test', '+5511990000001', '$argon2id$MOCK_HASH_NOT_FOR_AUTHENTICATION', 'ACTIVE', 1),
(2, '23456789012', 1, 2, 1, 1, 'Bruno Analista (MOCK)', 'bruno.analista@exemplo.test', '+5511990000002', '$argon2id$MOCK_HASH_NOT_FOR_AUTHENTICATION', 'ACTIVE', 2),
(3, '34567890123', 2, 3, 2, 2, 'Carla Administradora (MOCK)', 'carla.admin@modelo.test', '+5511990000003', '$argon2id$MOCK_HASH_NOT_FOR_AUTHENTICATION', 'ACTIVE', 3),
(4, '45678901234', 3, 5, 3, 3, 'Diego Responsável (MOCK)', 'diego.responsavel@verde.test', '+5541990000004', '$argon2id$MOCK_HASH_NOT_FOR_AUTHENTICATION', 'IN_VACATION', NULL);


INSERT INTO employee_telephones (id, telephone, employee_id) VALUES
(1, '+5511988880001', 1), (2, '+5511988880002', 2), (3, '+5511988880003', 3), (4, '+5541988880004', 4);

INSERT INTO contracts (id, employee_id, company_id) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 2), (4, 4, 3);

INSERT INTO password_recoveries (id, employee_id, code_hash, expires_at, attempts, used_at) VALUES
(1, 1, repeat('a', 64), CURRENT_TIMESTAMP + INTERVAL '15 minutes', 0, NULL),
(2, 2, repeat('b', 64), CURRENT_TIMESTAMP + INTERVAL '15 minutes', 1, NULL);


INSERT INTO subscriptions (id, company_id, plan_id, is_active, installments) VALUES
(1, 1, 1, TRUE, TRUE), (2, 2, 2, TRUE, TRUE), (3, 3, 1, TRUE, FALSE);

INSERT INTO payments (id, currency, subscription_id, additional_use_value, due_date, payment_type) VALUES
(1, 'Reais', 1, 250.00, CURRENT_DATE + 7, 'PIX'),
(2, 'Reais', 2, 500.00, CURRENT_DATE + 14, 'TRANSFERENCIA'),
(3, 'Reais', 3, 100.00, CURRENT_DATE + 21, 'CARTAO');

INSERT INTO inventories (id, company_id, employee_id, sector_id, file_size, status, file_path, start_period, end_period, submission_date, type) VALUES
(1, 1, 2, 1, 2.4, 'approved', '/uploads/mock/inventario-2024.pdf', '2024-01-01', '2024-12-31', '2025-01-15', 'Inventário anual (MOCK)'),
(2, 2, 3, 2, 1.8, 'in review', '/uploads/mock/inventario-2025.pdf', '2025-01-01', '2025-12-31', '2026-01-20', 'Inventário anual (MOCK)'),
(3, 3, 4, 3, 0.9, 'pending', '/uploads/mock/inventario-parcial.pdf', '2025-01-01', '2025-06-30', NULL, 'Inventário semestral (MOCK)');


INSERT INTO roi_analyses (id, inventory_id, calculation_date, years_along, annual_operating_savings, estimated_payback_month, carbon_credit_revenue, annual_rate_technology_degradation, wacc) VALUES
(1, 1, '2025-02-01', 5, 125000.00, 18.5, 15000.00, 0.02, 0.10),
(2, 2, '2026-02-01', 7, 98000.00, 24.0, 12000.00, 0.025, 0.11),
(3, 3, '2026-03-01', 3, 25000.00, 30.0, 3000.00, 0.03, 0.12);

INSERT INTO roi_projection_years (id, roi_analysis_id, year, value) VALUES
(1, 1, 2025, 125000), (2, 1, 2026, 127500), (3, 1, 2027, 130050),
(4, 2, 2026, 98000), (5, 2, 2027, 100450), (6, 3, 2026, 25000);

-- 6. Gases, setores e alternativas de redução
INSERT INTO sector_gases (id, sector_id, gas_id) VALUES
(1, 1, 1), (2, 1, 2), (3, 1, 3), (4, 2, 4), (5, 2, 5), (6, 3, 6), (7, 3, 7), (8, 3, 8);

INSERT INTO gas_reductions (id, gas_id, unit, current_emission, estimated_days, estimated_reduction, estimated_roi, init_emission) VALUES
(1, 1, 'tCO2e', 125.5, 180, 20.0, 12500.00, 150.0),
(2, 2, 'tCO2e', 80.0, 240, 35.0, 18750.00, 120.0),
(3, 3, 'tCO2e', 12.5, 365, 40.0, 25000.00, 20.8),
(4, 8, 'tCO2e', 210.0, 120, 15.0, 7500.00, 247.0);

INSERT INTO reduction_gases (id, gas_reduction_id, gas_id) VALUES
(1, 1, 1), (2, 2, 2), (3, 3, 3), (4, 4, 8);

INSERT INTO gas_reduction_inventories (id, gas_reduction_id, inventory_id) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 2), (4, 4, 3);

INSERT INTO gas_reduction_sectors (id, gas_reduction_id, sector_id) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 3);


INSERT INTO contains (id, parana_climate_seal_id, company_id) VALUES
(1, 1, 1), (2, 1, 3), (3, 2, 1), (4, 2, 2);


INSERT INTO permission_group_permissions (id, permission_group_id, permission_id) VALUES
(1, 1, 1), (2, 2, 2), (3, 3, 1), (4, 4, 2), (5, 5, 1), (6, 6, 2);

SELECT setval(pg_get_serial_sequence('addresses', 'id'), COALESCE((SELECT MAX(id) FROM addresses), 1), true);
SELECT setval(pg_get_serial_sequence('storage_files', 'id'), COALESCE((SELECT MAX(id) FROM storage_files), 1), true);
SELECT setval(pg_get_serial_sequence('companies', 'id'), COALESCE((SELECT MAX(id) FROM companies), 1), true);
SELECT setval(pg_get_serial_sequence('units', 'id'), COALESCE((SELECT MAX(id) FROM units), 1), true);
SELECT setval(pg_get_serial_sequence('telephone_companies', 'id'), COALESCE((SELECT MAX(id) FROM telephone_companies), 1), true);
SELECT setval(pg_get_serial_sequence('sectors', 'id'), COALESCE((SELECT MAX(id) FROM sectors), 1), true);
SELECT setval(pg_get_serial_sequence('permission_groups', 'id'), COALESCE((SELECT MAX(id) FROM permission_groups), 1), true);
SELECT setval(pg_get_serial_sequence('administrators', 'id'), COALESCE((SELECT MAX(id) FROM administrators), 1), true);
SELECT setval(pg_get_serial_sequence('employees', 'id'), COALESCE((SELECT MAX(id) FROM employees), 1), true);
SELECT setval(pg_get_serial_sequence('employee_telephones', 'id'), COALESCE((SELECT MAX(id) FROM employee_telephones), 1), true);
SELECT setval(pg_get_serial_sequence('password_recoveries', 'id'), COALESCE((SELECT MAX(id) FROM password_recoveries), 1), true);
SELECT setval(pg_get_serial_sequence('contracts', 'id'), COALESCE((SELECT MAX(id) FROM contracts), 1), true);
SELECT setval(pg_get_serial_sequence('inventories', 'id'), COALESCE((SELECT MAX(id) FROM inventories), 1), true);
SELECT setval(pg_get_serial_sequence('plans', 'id'), COALESCE((SELECT MAX(id) FROM plans), 1), true);
SELECT setval(pg_get_serial_sequence('subscriptions', 'id'), COALESCE((SELECT MAX(id) FROM subscriptions), 1), true);
SELECT setval(pg_get_serial_sequence('payments', 'id'), COALESCE((SELECT MAX(id) FROM payments), 1), true);
SELECT setval(pg_get_serial_sequence('roi_analyses', 'id'), COALESCE((SELECT MAX(id) FROM roi_analyses), 1), true);
SELECT setval(pg_get_serial_sequence('roi_projection_years', 'id'), COALESCE((SELECT MAX(id) FROM roi_projection_years), 1), true);
SELECT setval(pg_get_serial_sequence('gases', 'id'), COALESCE((SELECT MAX(id) FROM gases), 1), true);
SELECT setval(pg_get_serial_sequence('sector_gases', 'id'), COALESCE((SELECT MAX(id) FROM sector_gases), 1), true);
SELECT setval(pg_get_serial_sequence('gas_reductions', 'id'), COALESCE((SELECT MAX(id) FROM gas_reductions), 1), true);
SELECT setval(pg_get_serial_sequence('reduction_gases', 'id'), COALESCE((SELECT MAX(id) FROM reduction_gases), 1), true);
SELECT setval(pg_get_serial_sequence('gas_reduction_inventories', 'id'), COALESCE((SELECT MAX(id) FROM gas_reduction_inventories), 1), true);
SELECT setval(pg_get_serial_sequence('gas_reduction_sectors', 'id'), COALESCE((SELECT MAX(id) FROM gas_reduction_sectors), 1), true);
SELECT setval(pg_get_serial_sequence('parana_climate_seals', 'id'), COALESCE((SELECT MAX(id) FROM parana_climate_seals), 1), true);
SELECT setval(pg_get_serial_sequence('contains', 'id'), COALESCE((SELECT MAX(id) FROM contains), 1), true);
SELECT setval(pg_get_serial_sequence('permissions', 'id'), COALESCE((SELECT MAX(id) FROM permissions), 1), true);
SELECT setval(pg_get_serial_sequence('permission_group_permissions', 'id'), COALESCE((SELECT MAX(id) FROM permission_group_permissions), 1), true);

COMMIT;

SELECT 'addresses' AS tabela, COUNT(*) AS registros FROM addresses
UNION ALL SELECT 'companies', COUNT(*) FROM companies
UNION ALL SELECT 'employees', COUNT(*) FROM employees
UNION ALL SELECT 'plans', COUNT(*) FROM plans
UNION ALL SELECT 'subscriptions', COUNT(*) FROM subscriptions
UNION ALL SELECT 'gases', COUNT(*) FROM gases
UNION ALL SELECT 'inventories', COUNT(*) FROM inventories
UNION ALL SELECT 'roi_analyses', COUNT(*) FROM roi_analyses;
