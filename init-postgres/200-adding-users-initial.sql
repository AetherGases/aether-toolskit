\connect dbAether2Year

BEGIN;

-- Dados demonstrativos. As senhas abaixo são hashes fictícios para ambiente de desenvolvimento.

INSERT INTO plan (id, name, description, price, duration_days, is_active) VALUES
(1, 'Plano Essencial', 'Inventário corporativo básico', 499.90, 365, true),
(2, 'Plano Profissional', 'Inventário e acompanhamento de reduções', 999.90, 365, true),
(3, 'Plano Empresarial', 'Gestão multiunidade e validação', 1999.90, 365, true);

INSERT INTO address (id, zip_code, state, city, neighborhood, street, number, complement) VALUES
(1, '80010000', 'Paraná', 'Curitiba', 'Centro', 'Rua XV de Novembro', 100, 'Sala 401'),
(2, '81200000', 'Paraná', 'Curitiba', 'Mossunguê', 'Rua Paulo Gorski', 500, NULL),
(3, '87010000', 'Paraná', 'Maringá', 'Zona 01', 'Avenida Brasil', 1200, 'Bloco B'),
(4, '80030000', 'Paraná', 'Curitiba', 'Rebouças', 'Avenida Sete de Setembro', 2200, NULL),
(5, '81250100', 'Paraná', 'Curitiba', 'Cidade Industrial', 'Rua João Bettega', 3000, NULL);

INSERT INTO enterprise (id, name, trade_name, cnpj, id_address) VALUES
(1, 'Aether Tecnologia Ambiental Ltda.', 'Aether Ambiental', '12345678000190', 1),
(2, 'Indústria Paranaense de Alimentos S.A.', 'IPA Alimentos', '98765432000110', 2);

INSERT INTO plan_subscription (id, is_active, installments, deactivated_at, id_plan, id_enterprise) VALUES
(1, true, 12, NULL, 2, 1),
(2, true, 12, NULL, 3, 2);

INSERT INTO payment (id, value, term, status, additional_use_value, due_date, id_plan_subscription) VALUES
(1, 999.90, '2026-01-10 10:00:00', 'PAID', 0, '2026-01-10', 1),
(2, 999.90, '2026-02-10 10:00:00', 'PAID', 49.90, '2026-02-10', 1),
(3, 999.90, '2026-03-10 10:00:00', 'WAITING', 0, '2026-03-10', 1),
(4, 1999.90, '2026-01-15 10:00:00', 'PAID', 0, '2026-01-15', 2),
(5, 1999.90, '2026-02-15 10:00:00', 'CANCELLED', 0, '2026-02-15', 2);

INSERT INTO unit (id, cnae, cnpj, is_active, id_enterprise, id_address) VALUES
(1, '6201500', '12345678000270', true, 1, 4),
(2, '6201500', '12345678000350', true, 1, 5),
(3, '1091100', '98765432000200', true, 2, 3);

INSERT INTO department (id, name, description, id_unit) VALUES
(1, 'Sustentabilidade', 'Gestão ambiental e inventário de emissões', 1),
(2, 'Operações', 'Operação e consumo de recursos', 1),
(3, 'Sustentabilidade', 'Gestão ambiental corporativa', 3),
(4, 'Logística', 'Transportes e distribuição', 3);

INSERT INTO permission_group (id, description, id_enterprise) VALUES
(1, 'Administradores', 1),
(2, 'Gestores de inventário', 1),
(3, 'Administradores', 2);

INSERT INTO permission (id, name, description, url) VALUES
(1, 'INVENTORY_READ', 'Consultar inventários', '/inventories'),
(2, 'INVENTORY_WRITE', 'Criar e editar inventários', '/inventories'),
(3, 'EMISSION_WRITE', 'Registrar emissões', '/emissions'),
(4, 'REPORT_READ', 'Consultar relatórios', '/reports'),
(5, 'ADMIN_MANAGE', 'Administrar usuários e permissões', '/admin');

INSERT INTO permission_group_permission (id, id_permission, id_permission_group) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 1), (5, 5, 1),
(6, 1, 2), (7, 2, 2), (8, 3, 2), (9, 4, 2),
(10, 1, 3), (11, 2, 3), (12, 3, 3), (13, 4, 3), (14, 5, 3);

INSERT INTO storage_file (id, name, path) VALUES
(1, 'inventario-aether-2025.pdf', '/uploads/inventories/inventario-aether-2025.pdf'),
(2, 'fatura-ipa-2026-01.pdf', '/uploads/payments/fatura-ipa-2026-01.pdf'),
(3, 'fator-emissao-energia.xlsx', '/uploads/references/fator-emissao-energia.xlsx');

INSERT INTO employee (id, cpf, name, email, phone, password_hash, employee_status, id_storage_file, id_department) VALUES
(1, '12345678901', 'Marina Costa', 'marina.costa@aether.example', '+5541999990001', '$2b$12$seed.marina.costa.demonstracao', 'ACTIVE', NULL, 1),
(2, '23456789012', 'Rafael Mendes', 'rafael.mendes@aether.example', '+5541999990002', '$2b$12$seed.rafael.mendes.demonstracao', 'ACTIVE', NULL, 2),
(3, '34567890123', 'Beatriz Oliveira', 'beatriz.oliveira@ipa.example', '+5544999990003', '$2b$12$seed.beatriz.oliveira.demonstracao', 'ACTIVE', NULL, 3),
(4, '45678901234', 'Carlos Nogueira', 'carlos.nogueira@ipa.example', '+5544999990004', '$2b$12$seed.carlos.nogueira.demonstracao', 'IN_VACATION', NULL, 4);

INSERT INTO permission_group_employee (id_employee, id_permission_group) VALUES
(1, 1), (2, 2), (3, 3), (4, 3);

INSERT INTO administrator (id, email, password_hash) VALUES
(1, 'admin@aether.example', '$2b$12$seed.administrador.demonstracao');

INSERT INTO scope (id, name) VALUES
(1, 'Scope 1'), (2, 'Scope 2'), (3, 'Scope 3');

INSERT INTO category (id, name, classification) VALUES
(1, 'Combustão estacionária', NULL),
(2, 'Combustão móvel', NULL),
(3, 'Emissões fugitivas', NULL),
(4, 'Energia elétrica adquirida', NULL),
(5, 'Bens e serviços comprados', 'UPSTREAM'),
(6, 'Bens de capital', 'UPSTREAM'),
(7, 'Atividades relacionadas a combustíveis e energia', 'UPSTREAM'),
(8, 'Transporte e distribuição upstream', 'UPSTREAM'),
(9, 'Resíduos gerados nas operações', 'UPSTREAM'),
(10, 'Viagens a negócios', 'UPSTREAM'),
(11, 'Deslocamento de funcionários', 'UPSTREAM'),
(12, 'Ativos arrendados upstream', 'UPSTREAM'),
(13, 'Transporte e distribuição downstream', 'DOWNSTREAM'),
(14, 'Processamento de produtos vendidos', 'DOWNSTREAM'),
(15, 'Uso de produtos vendidos', 'DOWNSTREAM'),
(16, 'Tratamento de fim de vida de produtos vendidos', 'DOWNSTREAM'),
(17, 'Ativos arrendados downstream', 'DOWNSTREAM'),
(18, 'Franquias', 'DOWNSTREAM'),
(19, 'Investimentos', 'DOWNSTREAM'),
(20, 'Other', NULL);

INSERT INTO gas (id, name, formula, is_biogenic, gwp) VALUES
(1, 'Dióxido de carbono', 'CO2', false, 1),
(2, 'Metano', 'CH4', false, 27.2),
(3, 'Óxido nitroso', 'N2O', false, 273),
(4, 'Dióxido de carbono biogênico', 'CO2-BIO', true, 1),
(5, 'HFC-134a', 'HFC-134a', false, 1530),
(6, 'Hexafluoreto de enxofre', 'SF6', false, 25200);

INSERT INTO parana_seal_forecast (id, score, level, valid_until, id_unit) VALUES
(1, 82.50, 4, '2026-12-31', 1),
(2, 68.00, 3, '2026-12-31', 3);

INSERT INTO inventory (id, name, description, consolidation_approach, inventorying_period_start, inventorying_period_end, status, type, id_department, id_storage_file, id_owner_employee, id_validator_employee) VALUES
(1, 'Inventário Aether 2025', 'Inventário anual da unidade Curitiba Centro', 'Controle operacional', '2025-01-01', '2025-12-31', 'APPROVED', 'OUTPUT', 1, 1, 1, 2),
(2, 'Inventário Aether 2026 - parcial', 'Levantamento do primeiro trimestre', 'Controle operacional', '2026-01-01', '2026-03-31', 'UNDER_REVIEW', 'OUTPUT', 1, NULL, 1, 2),
(3, 'Inventário IPA 2025', 'Inventário anual da unidade Maringá', 'Controle operacional', '2025-01-01', '2025-12-31', 'APPROVED', 'OUTPUT', 3, NULL, 3, 4),
(4, 'Dados de energia IPA 2026', 'Dados de entrada para consolidação', 'Controle operacional', '2026-01-01', '2026-03-31', 'PROCESSING', 'INPUT', 3, 3, 3, NULL);

INSERT INTO emission (id, quantity_co2e, methodology_description, supplier_data_percentage, id_gas, id_scope, id_category, id_inventory) VALUES
(1, 125.40, 'Consumo de gás natural e fator IPCC', 95.00, 1, 1, 1, 1),
(2, 48.70, 'Combustível de frota própria', 100.00, 1, 1, 2, 1),
(3, 310.20, 'Eletricidade adquirida - localização', 100.00, 1, 2, 4, 1),
(4, 72.30, 'Serviços de nuvem e bens adquiridos', 60.00, 1, 3, 5, 1),
(5, 21.80, 'Transporte contratado de colaboradores', 80.00, 2, 3, 10, 1),
(6, 35.00, 'Consumo de gás natural', 90.00, 1, 1, 1, 2),
(7, 88.40, 'Eletricidade adquirida - localização', 100.00, 1, 2, 4, 2),
(8, 940.00, 'Combustão estacionária industrial', 98.00, 1, 1, 1, 3),
(9, 420.50, 'Energia elétrica adquirida', 100.00, 1, 2, 4, 3),
(10, 155.70, 'Transporte e distribuição upstream', 75.00, 2, 3, 8, 3),
(11, 112.00, 'Resíduos gerados nas operações', 70.00, 2, 3, 9, 3);

INSERT INTO reduction (id, quantity_co2e, id_inventory, id_category) VALUES
(1, 38.50, 1, 4),
(2, 16.20, 1, 2),
(3, 75.00, 3, 4),
(4, 42.30, 3, 9);

-- =========================================================
-- Carga adicional para testes (700 registros)
-- 600 emissões + 100 iniciativas de redução.
-- Os valores são determinísticos e distribuídos entre os dados-base.
-- =========================================================

INSERT INTO emission (
    id, quantity_co2e, methodology_description, supplier_data_percentage,
    id_gas, id_scope, id_category, id_inventory
)
SELECT
    serie AS id,
    ROUND((25 + ((serie * 37) % 18000) / 100.0)::numeric, 2) AS quantity_co2e,
    CASE serie % 4
        WHEN 0 THEN 'Fator de emissão IPCC - consumo energético'
        WHEN 1 THEN 'Dados de atividade informados pela unidade'
        WHEN 2 THEN 'Fator médio de mercado - cadeia de suprimentos'
        ELSE 'Medição operacional consolidada'
    END AS methodology_description,
    (55 + (serie * 7) % 46)::numeric AS supplier_data_percentage,
    1 + (serie % 6) AS id_gas,
    1 + (serie % 3) AS id_scope,
    CASE
        WHEN serie % 3 = 0 THEN 1 + (serie % 4)
        ELSE 5 + (serie % 16)
    END AS id_category,
    1 + (serie % 4) AS id_inventory
FROM generate_series(12, 611) AS serie;

INSERT INTO reduction (id, quantity_co2e, id_inventory, id_category)
SELECT
    serie AS id,
    ROUND((5 + ((serie * 29) % 9500) / 100.0)::numeric, 2) AS quantity_co2e,
    1 + (serie % 4) AS id_inventory,
    CASE
        WHEN serie % 2 = 0 THEN 1 + (serie % 4)
        ELSE 5 + (serie % 16)
    END AS id_category
FROM generate_series(5, 104) AS serie;

-- Mantém as sequências alinhadas aos IDs explícitos deste seed.
SELECT setval(pg_get_serial_sequence('plan', 'id'), 3, true);
SELECT setval(pg_get_serial_sequence('address', 'id'), 5, true);
SELECT setval(pg_get_serial_sequence('enterprise', 'id'), 2, true);
SELECT setval(pg_get_serial_sequence('plan_subscription', 'id'), 2, true);
SELECT setval(pg_get_serial_sequence('payment', 'id'), 5, true);
SELECT setval(pg_get_serial_sequence('unit', 'id'), 3, true);
SELECT setval(pg_get_serial_sequence('department', 'id'), 4, true);
SELECT setval(pg_get_serial_sequence('permission_group', 'id'), 3, true);
SELECT setval(pg_get_serial_sequence('permission', 'id'), 5, true);
SELECT setval(pg_get_serial_sequence('permission_group_permission', 'id'), 14, true);
SELECT setval(pg_get_serial_sequence('storage_file', 'id'), 3, true);
SELECT setval(pg_get_serial_sequence('employee', 'id'), 4, true);
SELECT setval(pg_get_serial_sequence('administrator', 'id'), 1, true);
SELECT setval(pg_get_serial_sequence('scope', 'id'), 3, true);
SELECT setval(pg_get_serial_sequence('category', 'id'), 20, true);
SELECT setval(pg_get_serial_sequence('gas', 'id'), 6, true);
SELECT setval(pg_get_serial_sequence('parana_seal_forecast', 'id'), 2, true);
SELECT setval(pg_get_serial_sequence('inventory', 'id'), 4, true);
SELECT setval(pg_get_serial_sequence('emission', 'id'), 611, true);
SELECT setval(pg_get_serial_sequence('reduction', 'id'), 104, true);

COMMIT;
