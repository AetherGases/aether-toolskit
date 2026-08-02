BEGIN;

-- =========================================================
-- Enums
-- =========================================================

CREATE TYPE PAYMENT_STATUS AS ENUM (
    'PAID',
    'CANCELLED',
    'WAITING'
);

CREATE TYPE REPORT_TYPE AS ENUM (
    'INVENTORY',
    'PARANA_CLIMATE_SEAL_SUBSCRIPTION'
);

CREATE TYPE CATEGORY_CLASSIFICATION AS ENUM (
    'DOWNSTREAM',
    'UPSTREAM'
);

-- =========================================================
-- Tabelas administrativas / institucionais
-- =========================================================

CREATE TABLE plan (
    name VARCHAR(50),
    id SERIAL,
    description VARCHAR(255),
    price NUMERIC,
    duration_days INTEGER,
    is_active BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT pk_plan PRIMARY KEY (id)
);

CREATE TABLE address (
    id SERIAL,
    zip_code CHAR(8),
    number INTEGER,
    complement VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT pk_address PRIMARY KEY (id)
);

CREATE TABLE enterprise (
    id SERIAL,
    name VARCHAR(255),
    trade_name VARCHAR(255),
    cnpj CHAR(14),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_address INTEGER,
    CONSTRAINT pk_enterprise PRIMARY KEY (id)
);

CREATE TABLE plan_subscription (
    id SERIAL,
    is_active BOOLEAN,
    installments INTEGER,
    created_at TIMESTAMP,
    deactivated_at TIMESTAMP,
    id_plan INTEGER,
    id_enterprise INTEGER,
    CONSTRAINT pk_plan_subscription PRIMARY KEY (id)
);

CREATE TABLE payment (
    id SERIAL,
    value NUMERIC,
    term TIMESTAMP,
    status PAYMENT_STATUS,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    additional_use_value NUMERIC,
    id_plan_subscription INTEGER,
    CONSTRAINT pk_payment PRIMARY KEY (id)
);

CREATE TABLE unit (
    id SERIAL,
    cnae CHAR(7),
    cnpj CHAR(14),
    is_active BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_enterprise INTEGER,
    id_address INTEGER,
    CONSTRAINT pk_unit PRIMARY KEY (id)
);

CREATE TABLE department (
    id SERIAL,
    name VARCHAR(255),
    description VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_unit INTEGER,
    CONSTRAINT pk_department PRIMARY KEY (id)
);

CREATE TABLE permission_group (
    id SERIAL,
    description VARCHAR(255),
    CONSTRAINT pk_permission_group PRIMARY KEY (id)
);

CREATE TABLE permission (
    id SERIAL,
    name VARCHAR(255),
    description VARCHAR(255),
    CONSTRAINT pk_permission PRIMARY KEY (id)
);

CREATE TABLE permission_group_permission (
    id SERIAL,
    id_permission INTEGER,
    id_permission_group INTEGER,
    CONSTRAINT pk_permission_group_permission PRIMARY KEY (id),
    CONSTRAINT uq_permission_group_permission UNIQUE (id_permission, id_permission_group)
);

CREATE TABLE parana_seal_forecast (
    id SERIAL,
    score NUMERIC,
    level INTEGER,
    valid_until TIMESTAMP,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_unit INTEGER,
    CONSTRAINT pk_parana_seal_forecast PRIMARY KEY (id)
);

CREATE TABLE administrator (
    id SERIAL,
    email VARCHAR(255),
    password_hash VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT pk_administrator PRIMARY KEY (id)
);

CREATE TABLE storage_file (
    id SERIAL,
    name VARCHAR(255),
    path VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT pk_storage_file PRIMARY KEY (id)
);

CREATE TABLE employee (
    id SERIAL,
    name VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(20),
    password_hash VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_storage_file INTEGER,
    CONSTRAINT pk_employee PRIMARY KEY (id)
);

-- =========================================================
-- Tabelas do domínio GHG
-- =========================================================

-- Escopo: Scope 1 / Scope 2 / Scope 3 (Tabela 1 e 7 do template)
CREATE TABLE scope (
    id SERIAL,
    name VARCHAR(100),
    CONSTRAINT pk_scope PRIMARY KEY (id)
);

-- Categoria: as 15 categorias de Scope 3 (upstream/downstream) + "Other"
-- classification só é relevante para linhas de Scope 3; nas demais fica NULL.
CREATE TABLE category (
    id SERIAL,
    name VARCHAR(255),
    classification CATEGORY_CLASSIFICATION,
    CONSTRAINT pk_category PRIMARY KEY (id)
);

-- Gas: gases do inventário (CO2, CH4, N2O, HFCs, PFCs, SF6, entre outros)
CREATE TABLE gas (
    id SERIAL,
    name VARCHAR(255),
    formula VARCHAR(255),
    is_biogenic BOOLEAN,
    gwp NUMERIC,
    CONSTRAINT pk_gas PRIMARY KEY (id)
);

-- report: informações descritivas do inventário (Parte 1 do template)
CREATE TABLE report (
    id SERIAL,
    name VARCHAR(255),
    description VARCHAR(255),
    type REPORT_TYPE,
    consolidation_approach VARCHAR(100),
    reporting_period_start DATE,
    reporting_period_end DATE,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_department INTEGER,
    id_storage_file INTEGER,
    id_owner_employee INTEGER,
    id_validator_employee INTEGER,
    CONSTRAINT pk_report PRIMARY KEY (id)
);

-- emission: dados de emissão de GEE (Parte 2 e Parte 3 do template)
-- quantity_co2e é recebido diretamente do report de origem (já convertido);
-- a quantidade original do gás não é armazenada por decisão de negócio,
-- pois pode ser obtida dividindo quantity_co2e pelo gwp do gás em gas.gwp.
CREATE TABLE emission (
    id SERIAL,
    quantity_co2e NUMERIC,
    methodology_description VARCHAR(255),
    supplier_data_percentage NUMERIC,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_gas INTEGER,
    id_scope INTEGER,
    id_category INTEGER,
    id_report INTEGER,
    CONSTRAINT pk_emission PRIMARY KEY (id)
);

-- reduction: iniciativas de redução de emissões, ligadas ao report e à categoria
CREATE TABLE reduction (
    id SERIAL,
    quantity_co2e NUMERIC,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_report INTEGER,
    id_category INTEGER,
    CONSTRAINT pk_reduction PRIMARY KEY (id)
);

-- =========================================================
-- Chaves estrangeiras
-- =========================================================

ALTER TABLE enterprise
    ADD CONSTRAINT fk_enterprise_address
    FOREIGN KEY (id_address) REFERENCES address (id);

ALTER TABLE plan_subscription
    ADD CONSTRAINT fk_plan_subscription_plan
    FOREIGN KEY (id_plan) REFERENCES plan (id)
    ON DELETE CASCADE;

ALTER TABLE plan_subscription
    ADD CONSTRAINT fk_plan_subscription_enterprise
    FOREIGN KEY (id_enterprise) REFERENCES enterprise (id);

ALTER TABLE payment
    ADD CONSTRAINT fk_payment_plan_subscription
    FOREIGN KEY (id_plan_subscription) REFERENCES plan_subscription (id)
    ON DELETE RESTRICT;

ALTER TABLE unit
    ADD CONSTRAINT fk_unit_enterprise
    FOREIGN KEY (id_enterprise) REFERENCES enterprise (id);

ALTER TABLE unit
    ADD CONSTRAINT fk_unit_address
    FOREIGN KEY (id_address) REFERENCES address (id);

ALTER TABLE department
    ADD CONSTRAINT fk_department_unit
    FOREIGN KEY (id_unit) REFERENCES unit (id)
    ON DELETE RESTRICT;

ALTER TABLE permission_group_permission
    ADD CONSTRAINT fk_permission_group_permission_permission
    FOREIGN KEY (id_permission) REFERENCES permission (id);

ALTER TABLE permission_group_permission
    ADD CONSTRAINT fk_permission_group_permission_permission_group
    FOREIGN KEY (id_permission_group) REFERENCES permission_group (id);

ALTER TABLE parana_seal_forecast
    ADD CONSTRAINT fk_parana_seal_forecast_unit
    FOREIGN KEY (id_unit) REFERENCES unit (id)
    ON DELETE CASCADE;

ALTER TABLE employee
    ADD CONSTRAINT fk_employee_storage_file
    FOREIGN KEY (id_storage_file) REFERENCES storage_file (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_department
    FOREIGN KEY (id_department) REFERENCES department (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_storage_file
    FOREIGN KEY (id_storage_file) REFERENCES storage_file (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_owner_employee
    FOREIGN KEY (id_owner_employee) REFERENCES employee (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_validator_employee
    FOREIGN KEY (id_validator_employee) REFERENCES employee (id);

-- Auto-relacionamento: impede exclusão de um report usado como base de outro
ALTER TABLE report
    ADD CONSTRAINT fk_report_input_report
    FOREIGN KEY (id_input_report) REFERENCES report (id)
    ON DELETE RESTRICT;

ALTER TABLE emission
    ADD CONSTRAINT fk_emission_gas
    FOREIGN KEY (id_gas) REFERENCES gas (id)
    ON DELETE RESTRICT;

ALTER TABLE emission
    ADD CONSTRAINT fk_emission_scope
    FOREIGN KEY (id_scope) REFERENCES scope (id)
    ON DELETE RESTRICT;

ALTER TABLE emission
    ADD CONSTRAINT fk_emission_category
    FOREIGN KEY (id_category) REFERENCES category (id)
    ON DELETE RESTRICT;

ALTER TABLE emission
    ADD CONSTRAINT fk_emission_report
    FOREIGN KEY (id_report) REFERENCES report (id)
    ON DELETE CASCADE;

ALTER TABLE reduction
    ADD CONSTRAINT fk_reduction_report
    FOREIGN KEY (id_report) REFERENCES report (id)
    ON DELETE CASCADE;

ALTER TABLE reduction
    ADD CONSTRAINT fk_reduction_category
    FOREIGN KEY (id_category) REFERENCES category (id)
    ON DELETE RESTRICT;

-- =========================================================
-- Índices
-- =========================================================

CREATE INDEX idx_enterprise_id_address ON enterprise (id_address);
CREATE INDEX idx_plan_subscription_id_plan ON plan_subscription (id_plan);
CREATE INDEX idx_plan_subscription_id_enterprise ON plan_subscription (id_enterprise);
CREATE INDEX idx_payment_id_plan_subscription ON payment (id_plan_subscription);
CREATE INDEX idx_unit_id_enterprise ON unit (id_enterprise);
CREATE INDEX idx_unit_id_address ON unit (id_address);
CREATE INDEX idx_department_id_unit ON department (id_unit);
CREATE INDEX idx_permission_group_permission_id_permission ON permission_group_permission (id_permission);
CREATE INDEX idx_permission_group_permission_id_permission_group ON permission_group_permission (id_permission_group);
CREATE INDEX idx_parana_seal_forecast_id_unit ON parana_seal_forecast (id_unit);
CREATE INDEX idx_employee_id_storage_file ON employee (id_storage_file);
CREATE INDEX idx_report_id_department ON report (id_department);
CREATE INDEX idx_report_id_storage_file ON report (id_storage_file);
CREATE INDEX idx_report_id_owner_employee ON report (id_owner_employee);
CREATE INDEX idx_report_id_validator_employee ON report (id_validator_employee);
CREATE INDEX idx_report_id_input_report ON report (id_input_report);
CREATE INDEX idx_emission_id_gas ON emission (id_gas);
CREATE INDEX idx_emission_id_scope ON emission (id_scope);
CREATE INDEX idx_emission_id_category ON emission (id_category);
CREATE INDEX idx_emission_id_report ON emission (id_report);
CREATE INDEX idx_reduction_id_report ON reduction (id_report);
CREATE INDEX idx_reduction_id_category ON reduction (id_category);

-- =========================================================
-- Comentários
-- =========================================================

COMMENT ON COLUMN category.classification IS 'Indicates whether the category is upstream, downstream, or another category, according to the GHG Protocol Scope 3 categories. Applicable only when the emission belongs to Scope 3.';
COMMENT ON COLUMN emission.quantity_co2e IS 'Emission quantity received from the source report, already expressed in metric tons of CO2 equivalent (CO2e). The original gas quantity, when needed, can be derived by dividing this value by the corresponding GWP in gas.gwp.';
COMMENT ON COLUMN gas.is_biogenic IS 'Indicates whether the gas emissions are of biogenic origin, according to Part 3 of the GHG template.';
COMMENT ON COLUMN gas.gwp IS 'Global Warming Potential (GWP) factor of the gas, used to convert its physical quantity into CO2e.';

COMMIT;
