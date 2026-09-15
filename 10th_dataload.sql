-- =========================================================
--SCRIPT DATALOAD - BANCO DE DADOS REAIS/CONHECIDOS
-- =========================================================

-- =========================================================
--TRUNCATE DE SEGURANÇA, TIRAR DO MODO COMENTÁRIO APÓS RODAR SCRIPT TESTE
/*TRUNCATE TABLE
  addresses,
  companies,
  units,
  telephone_companies,
  sectors,
  permission_groups,
  administrators,
  employees,
  employee_telephones,
  contracts,
  inventories,
  plans,
  subscriptions,
  payments,
  roi_analyses,
  roi_projection_years,
  gases,
  sector_gases,
  gas_reductions,
  reduction_gases,
  gas_reduction_inventories,
  gas_reduction_sector,
  parana_climate_seals,
  contains,
  company_addresses,
  unit_addresses,
  permissions,
  permission_group_permissions
RESTART IDENTITY CASCADE;*/
-- =========================================================

-- =========================================================
--GASES
-- =========================================================
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES  ("Óxido Nitroso", "Gás de efeito estufa", "Alto", 273);
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES ("Hexafluoreto de Enxofre", "Gás de efeito estufa", "Extremo", 23500);
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES ("Trifluorometano", "Gás de efeito estufa", "Extremo", 14800);
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES ("Tetrafluoroetano", "Gás de efeito estufa", "Alto", 1430);
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES ("Óxido de Nitrogênio", "Gás de efeito estufa", "Alto", 298);
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES ("Monóxido de Carbono", "Gás de efeito estufa", "Moderado (GWP indireto)", NULL);
INSERT INTO TABLE gases(name, type, measurement, gwp) 
  VALUES ("Óxido de Nitrogênio", "Gás de efeito estufa", "Alto", 298);

-- =========================================================
--PLANOS
-- =========================================================

INSERT INTO TABLE plans(name, description, price) 
  VALUES("Aether Pulse", "Mensal: Para líderes de indústria", 3300);
INSERT INTO TABLE plans(name, description, price)
  VALUES("Aether Horizon", "Trimestral: Para planos customizados", 9500);

-- =========================================================
-- FIM DO DATALOAD
-- =========================================================


-- =========================================================
-- DATALOAD - BANCO DE TESTES
-- USA-LO PRIMEIRO DO QUE O SCRIPT REAL
-- =========================================================


-- =========================================================
-- 1. ADDRESSES
-- =========================================================

INSERT INTO addresses
(street, number, complement, city, state, country)
VALUES
('Av. Paulista', '1000', 'Sala 101', 'São Paulo', 'SP', 'Brasil'),
('Rua Augusta', '250', NULL, 'São Paulo', 'SP', 'Brasil'),
('Av. Brasil', '1500', 'Bloco A', 'Campinas', 'SP', 'Brasil'),
('Rua das Flores', '321', NULL, 'Curitiba', 'PR', 'Brasil'),
('Av. Atlântica', '500', 'Sala 20', 'Rio de Janeiro', 'RJ', 'Brasil');


-- =========================================================
-- 2. COMPANIES
-- =========================================================

INSERT INTO companies
(name, size, registration_date, tax_id, email)
VALUES
('EcoTech Solutions', 350, '2018-05-12',
 '12.345.678/0001-01', 'contato@ecotech.com'),

('Green Industries', 820, '2015-08-20',
 '23.456.789/0001-02', 'contato@greenindustries.com'),

('Nova Energia', 120, '2021-02-10',
 '34.567.890/0001-03', 'contato@novaenergia.com'),

('CarbonFree Brasil', 560, '2017-11-03',
 '45.678.901/0001-04', 'contato@carbonfree.com'),

('BioFuture', 75, '2023-01-15',
 '56.789.012/0001-05', 'contato@biofuture.com');


-- =========================================================
-- 3. UNITS
-- =========================================================

INSERT INTO units
(name, company_id, cnpj, cnae)
VALUES
('Unidade Paulista', 1,
 '12.345.678/0002-01', '6201-5/01'),

('Unidade Campinas', 1,
 '12.345.678/0003-01', '6201-5/01'),

('Unidade Curitiba', 2,
 '23.456.789/0002-02', '2019-3/99'),

('Unidade Industrial RJ', 4,
 '45.678.901/0002-04', '2099-1/99'),

('Unidade Central', 5,
 '56.789.012/0002-05', '3511-5/01');


-- =========================================================
-- 4. TELEPHONES - COMPANIES
-- =========================================================

INSERT INTO telephone_companies
(telephone, company_id)
VALUES
('(11) 3000-1000', 1),
('(11) 3000-2000', 1),
('(19) 3200-3000', 2),
('(41) 3300-4000', 3),
('(21) 3400-5000', 4),
('(11) 3500-6000', 5);


-- =========================================================
-- 5. SECTORS
-- =========================================================

INSERT INTO sectors
(description, unit_id, company_id)
VALUES
('Tecnologia da Informação', 1, 1),
('Produção', 1, 1),
('Pesquisa e Desenvolvimento', 2, 1),
('Produção Industrial', 3, 2),
('Logística', 3, 2),
('Energia', 4, 4),
('Sustentabilidade', 5, 5);


-- =========================================================
-- 6. PERMISSION GROUPS
-- =========================================================

INSERT INTO permission_groups
(name)
VALUES
('Administrador'),
('Gestor'),
('Analista'),
('Operador'),
('Visualizador');


-- =========================================================
-- 7. ADMINISTRATORS
-- =========================================================

INSERT INTO administrators
(email, password)
VALUES
('admin@ecotech.com', 'teste123'),
('admin@greenindustries.com', 'teste123'),
('admin@carbonfree.com', 'teste123');


-- =========================================================
-- 8. PERMISSIONS
-- =========================================================

INSERT INTO permissions
(name, description)
VALUES
('CREATE_INVENTORY', 'Criar inventários'),
('READ_INVENTORY', 'Visualizar inventários'),
('UPDATE_INVENTORY', 'Atualizar inventários'),
('DELETE_INVENTORY', 'Excluir inventários'),
('VIEW_ROI', 'Visualizar análises de ROI'),
('MANAGE_USERS', 'Gerenciar usuários'),
('MANAGE_COMPANIES', 'Gerenciar empresas');


-- =========================================================
-- 9. PERMISSION GROUP PERMISSIONS
-- =========================================================

INSERT INTO permission_group_permissions
(permission_group_id, permission_id)
VALUES
-- Administrador
(1, 1),
(1, 2),
(1, 3),
(1, 4),
(1, 5),
(1, 6),
(1, 7),

-- Gestor
(2, 1),
(2, 2),
(2, 3),
(2, 5),
(2, 7),

-- Analista
(3, 1),
(3, 2),
(3, 3),
(3, 5),

-- Operador
(4, 1),
(4, 2),
(4, 3),

-- Visualizador
(5, 2),
(5, 5);


-- =========================================================
-- 10. EMPLOYEES
-- =========================================================

INSERT INTO employees
(company_id, permission_group_id, unit_id,
 name, email, status)
VALUES
(1, 1, 1,
 'Ana Silva', 'ana.silva@ecotech.com', 'active'),

(1, 3, 1,
 'Bruno Costa', 'bruno.costa@ecotech.com', 'active'),

(1, 4, 2,
 'Carlos Oliveira', 'carlos.oliveira@ecotech.com', 'on vacation'),

(2, 2, 3,
 'Daniel Souza', 'daniel.souza@greenindustries.com', 'active'),

(2, 3, 3,
 'Mariana Santos', 'mariana.santos@greenindustries.com', 'on leave'),

(4, 2, 4,
 'Pedro Almeida', 'pedro.almeida@carbonfree.com', 'active'),

(5, 3, 5,
 'Julia Martins', 'julia.martins@biofuture.com', 'active');


-- =========================================================
-- 11. EMPLOYEE TELEPHONES
-- =========================================================

INSERT INTO employee_telephones
(telephone, employee_id)
VALUES
('(11) 98888-1001', 1),
('(11) 98888-1002', 2),
('(19) 98888-1003', 3),
('(41) 98888-1004', 4),
('(41) 98888-1005', 5),
('(21) 98888-1006', 6),
('(11) 98888-1007', 7);


-- =========================================================
-- 12. CONTRACTS
-- =========================================================

INSERT INTO contracts
(employee_id, company_id)
VALUES
(1, 1),
(2, 1),
(3, 1),
(4, 2),
(5, 2),
(6, 4),
(7, 5);


-- =========================================================
-- 13. PLANS
-- =========================================================

INSERT INTO plans
(name, description, price, currency)
VALUES
('Basic',
 'Plano para pequenas empresas',
 499.90, 'Reais'),

('Professional',
 'Plano para empresas de médio porte',
 1299.90, 'Reais'),

('Enterprise',
 'Plano completo para grandes empresas',
 2999.90, 'Reais'),

('Sustainability',
 'Plano focado em análise ambiental',
 1899.90, 'Reais');


-- =========================================================
-- 14. SUBSCRIPTIONS
-- =========================================================

INSERT INTO subscriptions
(company_id, plan_id, installments)
VALUES
(1, 2, TRUE),
(2, 3, TRUE),
(3, 1, FALSE),
(4, 3, TRUE),
(5, 4, FALSE);


-- =========================================================
-- 15. PAYMENTS
-- =========================================================

INSERT INTO payments
(currency, subscription_id, additional_use_value,
 due_date, payment_type)
VALUES
('Reais', 1, 150.00, '2026-09-10', 'Credit Card'),

('Reais', 2, 450.00, '2026-09-15', 'Bank Transfer'),

('Reais', 3, NULL, '2026-09-20', 'Pix'),

('Reais', 4, 780.50, '2026-09-05', 'Credit Card'),

('Reais', 5, NULL, '2026-09-25', 'Pix');


-- =========================================================
-- 16. GASES
-- =========================================================

INSERT INTO gases
(name, type, measurement, gwp)
VALUES
('CO2', 'Greenhouse Gas', 'ton', 1),
('SO2', 'Pollutant', 'ton', NULL),
('SF6', 'Greenhouse Gas', 'kg', 25200),
('CH4', 'Greenhouse Gas', 'ton', 27.2),
('N2O', 'Greenhouse Gas', 'ton', 273),
('HFC-134a', 'Greenhouse Gas', 'kg', 1530);


-- =========================================================
-- 17. SECTOR_GASES
-- =========================================================

INSERT INTO sector_gases
(sector_id, gas_id)
VALUES
(1, 1),
(2, 1),
(2, 2),
(3, 3),
(4, 1),
(4, 4),
(5, 1),
(6, 3),
(6, 5),
(7, 1),
(7, 4);


-- =========================================================
-- 18. INVENTORIES
-- =========================================================

INSERT INTO inventories
(company_id, employee_id, sector_id,
 file_size, status, file_path,
 start_period, end_period, submission_date, type)
VALUES
(1, 2, 1,
 15.5, 'approved',
 '/inventories/ecotech_2025.csv',
 '2025-01-01', '2025-12-31', '2026-01-15',
 'Emissions'),

(1, 3, 2,
 22.8, 'in review',
 '/inventories/ecotech_production.csv',
 '2026-01-01', '2026-06-30', '2026-07-05',
 'Industrial'),

(2, 4, 4,
 45.2, 'approved',
 '/inventories/green_2025.csv',
 '2025-01-01', '2025-12-31', '2026-01-20',
 'Emissions'),

(2, 5, 5,
 18.7, 'pending',
 '/inventories/green_logistics.csv',
 '2026-01-01', '2026-06-30', '2026-07-10',
 'Logistics'),

(4, 6, 6,
 63.4, 'approved',
 '/inventories/carbonfree_2025.csv',
 '2025-01-01', '2025-12-31', '2026-01-12',
 'Industrial'),

(5, 7, 7,
 12.3, 'approved',
 '/inventories/biofuture_2025.csv',
 '2025-01-01', '2025-12-31', '2026-01-18',
 'Sustainability');


-- =========================================================
-- 19. ROI ANALYSES
-- =========================================================

INSERT INTO roi_analyses
(inventory_id, calculation_date, years_along,
 annual_operating_savings, estimated_payback_month,
 carbon_credit_revenue,
 annual_rate_technology_degradation, wacc)
VALUES
(1, '2026-02-01', 3,
 150000.00, 14.5,
 35000.00,
 0.03, 0.10),

(2, '2026-07-15', 3,
 95000.00, 18.2,
 22000.00,
 0.04, 0.11),

(3, '2026-02-05', 5,
 420000.00, 11.8,
 85000.00,
 0.02, 0.09),

(5, '2026-02-03', 4,
 310000.00, 16.4,
 72000.00,
 0.03, 0.095),

(6, '2026-02-10', 3,
 87000.00, 20.1,
 18000.00,
 0.05, 0.12);


-- =========================================================
-- 20. ROI PROJECTION YEARS
-- =========================================================

INSERT INTO roi_projection_years
(roi_analysis_id, year, value)
VALUES
(1, 1, 150000),
(1, 2, 295500),
(1, 3, 436635),

(2, 1, 95000),
(2, 2, 186200),
(2, 3, 273752),

(3, 1, 420000),
(3, 2, 831600),
(3, 3, 1230732),
(3, 4, 1618354),
(3, 5, 1986098),

(4, 1, 310000),
(4, 2, 610700),
(4, 3, 902651),
(4, 4, 1181571),

(5, 1, 87000),
(5, 2, 169650),
(5, 3, 248257);


-- =========================================================
-- 21. GAS REDUCTIONS
-- =========================================================

INSERT INTO gas_reductions
(gas_id, unit, current_emission,
 estimated_days, estimated_reduction,
 estimated_roi, init_emission)
VALUES
(1, 'ton/year',
 1200.5, 180, 35.5,
 150000.00, 1850.0),

(3, 'kg/year',
 85.2, 240, 48.7,
 230000.00, 120.0),

(4, 'ton/year',
 540.8, 150, 28.4,
 98000.00, 755.0),

(5, 'ton/year',
 120.4, 210, 41.2,
 125000.00, 205.0),

(2, 'ton/year',
 350.0, 120, 22.8,
 67000.00, 453.0);


-- =========================================================
-- 22. REDUCTION_GASES
-- =========================================================

INSERT INTO reduction_gases
(gas_reduction_id, gas_id)
VALUES
(1, 4),
(1, 5),
(2, 1),
(3, 1),
(4, 1),
(5, 1);


-- =========================================================
-- 23. GAS_REDUCTION_INVENTORIES
-- =========================================================

INSERT INTO gas_reduction_inventories
(gas_reduction_id, inventory_id)
VALUES
(1, 1),
(2, 1),
(3, 3),
(4, 5),
(5, 6);


-- =========================================================
-- 24. GAS_REDUCTION_SECTOR
-- =========================================================

INSERT INTO gas_reduction_sector
(gas_reduction_id, sector_id)
VALUES
(1, 1),
(1, 2),
(2, 3),
(3, 4),
(4, 6),
(5, 7);


-- =========================================================
-- 25. PARANA CLIMATE SEALS
-- =========================================================

INSERT INTO parana_climate_seals
(date_achievement, current_score)
VALUES
('2025-03-10', 82.5),
('2025-08-15', 91.2),
('2026-02-20', 76.8),
('2026-06-30', 95.4);


-- =========================================================
-- 26. CONTAINS
-- =========================================================

INSERT INTO contains
(parana_climate_seal_id, company_id)
VALUES
(1, 1),
(2, 2),
(3, 4),
(4, 5);


-- =========================================================
-- 27. COMPANY_ADDRESSES
-- =========================================================

INSERT INTO company_addresses
(company_id, address_id)
VALUES
(1, 1),
(2, 3),
(3, 4),
(4, 5),
(5, 2);


-- =========================================================
-- 28. UNIT_ADDRESSES
-- =========================================================

INSERT INTO unit_addresses
(unit_id, address_id)
VALUES
(1, 1),
(2, 3),
(3, 4),
(4, 5),
(5, 2);


-- =========================================================
-- FIM DO DATALOAD
-- =========================================================





