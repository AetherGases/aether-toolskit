BEGIN;

CREATE TABLE plan (
    id SERIAL,
    description VARCHAR(255),
    price NUMERIC,
    is_active BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT pk_plan PRIMARY KEY (id)
);

CREATE TABLE address (
    id SERIAL,
    zip_code CHAR(8),
    street VARCHAR(255),
    neighborhood VARCHAR(255),
    city VARCHAR(100),
    state CHAR(2),
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
    cnpj CHAR(14) UNIQUE NOT NULL,
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
    status VARCHAR(20) NOT NULL
    CHECK (status IN ('PENDING', 'PAID', 'OVERDUE', 'CANCELED')),
      created_at TIMESTAMP,
      updated_at TIMESTAMP,
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
    name VARCHAR(50),
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
    CONSTRAINT pk_permission_group_permission PRIMARY KEY (id)
);

CREATE TABLE parana_seal_forecast (
    id SERIAL,
    score NUMERIC,
    level INTEGER,
    valid_until TIMESTAMP,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    fk_unit_id INTEGER,
    CONSTRAINT pk_parana_seal_forecast PRIMARY KEY (id)
);

CREATE TABLE gas (
    id SERIAL,
    name VARCHAR(255),
    formula VARCHAR(255),
    gwp NUMERIC,
    description VARCHAR(255),
    type VARCHAR(50),
    scope VARCHAR(50),
    CONSTRAINT pk_gas PRIMARY KEY (id)
);

CREATE TABLE gas_reduction (
    id SERIAL,
    estimated_reduction NUMERIC,
    estimated_roi NUMERIC,
    initial_emission NUMERIC,
    current_emission NUMERIC,
    measure_unit VARCHAR(50),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_gas INTEGER,
    CONSTRAINT pk_gas_reduction PRIMARY KEY (id)
);

CREATE TABLE projection_years (
    id SERIAL,
    prediction NUMERIC,
    actual NUMERIC,
    year INTEGER,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_gas_reduction INTEGER,
    CONSTRAINT pk_projection_years PRIMARY KEY (id)
);

CREATE TABLE administrator (
    id SERIAL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CONSTRAINT pk_administrator PRIMARY KEY (id)
);

CREATE TABLE storage_file (
    id SERIAL,
    name VARCHAR(255),
    path VARCHAR(400),
    size_bytes BIGINT,
    file_type VARCHAR(12) NOT NULL
        CHECK (file_type IN ('PNG', 'JPG', 'JPEG', 'PDF', 'DOC', 'DOCX')),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,

    CONSTRAINT pk_storage_file PRIMARY KEY (id)
);

CREATE TABLE employee (
    id SERIAL,
    name VARCHAR(255),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(15),
    password_hash VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_storage_file INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'INACTIVE', 'VACATION')),
    CONSTRAINT pk_employee PRIMARY KEY (id)
);

CREATE TABLE report (
    id SERIAL,
    name VARCHAR(255),
    description VARCHAR(255),
    type VARCHAR(50),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    id_department INTEGER,
    id_gas_reduction INTEGER,
    id_storage_file INTEGER,
    id_owner_employee INTEGER,
    id_validator_employee INTEGER,
    id_input_report INTEGER,
    CONSTRAINT pk_report PRIMARY KEY (id)
);

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
    FOREIGN KEY (fk_unit_id) REFERENCES unit (id)
    ON DELETE CASCADE;

ALTER TABLE gas_reduction
    ADD CONSTRAINT fk_gas_reduction_gas
    FOREIGN KEY (id_gas) REFERENCES gas (id)
    ON DELETE CASCADE;

ALTER TABLE projection_years
    ADD CONSTRAINT fk_projection_years_gas_reduction
    FOREIGN KEY (id_gas_reduction) REFERENCES gas_reduction (id)
    ON DELETE CASCADE;

ALTER TABLE employee
    ADD CONSTRAINT fk_employee_storage_file
    FOREIGN KEY (id_storage_file) REFERENCES storage_file (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_department
    FOREIGN KEY (id_department) REFERENCES department (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_gas_reduction
    FOREIGN KEY (id_gas_reduction) REFERENCES gas_reduction (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_storage_file
    FOREIGN KEY (id_storage_file) REFERENCES storage_file (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_owner_employee
    FOREIGN KEY (id_owner_employee) REFERENCES employee (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_validator_employee
    FOREIGN KEY (id_validator_employee) REFERENCES employee (id);

ALTER TABLE report
    ADD CONSTRAINT fk_report_input_report
    FOREIGN KEY (id_input_report) REFERENCES report (id);

CREATE INDEX idx_enterprise_id_address ON enterprise (id_address);
CREATE INDEX idx_plan_subscription_id_plan ON plan_subscription (id_plan);
CREATE INDEX idx_plan_subscription_id_enterprise ON plan_subscription (id_enterprise);
CREATE INDEX idx_payment_id_plan_subscription ON payment (id_plan_subscription);
CREATE INDEX idx_unit_id_enterprise ON unit (id_enterprise);
CREATE INDEX idx_unit_id_address ON unit (id_address);
CREATE INDEX idx_department_id_unit ON department (id_unit);
CREATE INDEX idx_permission_group_permission_id_permission ON permission_group_permission (id_permission);
CREATE INDEX idx_permission_group_permission_id_permission_group ON permission_group_permission (id_permission_group);
CREATE INDEX idx_parana_seal_forecast_fk_unit_id ON parana_seal_forecast (fk_unit_id);
CREATE INDEX idx_gas_reduction_id_gas ON gas_reduction (id_gas);
CREATE INDEX idx_projection_years_id_gas_reduction ON projection_years (id_gas_reduction);
CREATE INDEX idx_employee_id_storage_file ON employee (id_storage_file);
CREATE INDEX idx_report_id_department ON report (id_department);
CREATE INDEX idx_report_id_gas_reduction ON report (id_gas_reduction);
CREATE INDEX idx_report_id_storage_file ON report (id_storage_file);
CREATE INDEX idx_report_id_owner_employee ON report (id_owner_employee);
CREATE INDEX idx_report_id_validator_employee ON report (id_validator_employee);
CREATE INDEX idx_report_id_input_report ON report (id_input_report);

COMMENT ON COLUMN enterprise.cnjp IS 'Column name preserved from logical model; check if cnpj was intended.';
COMMENT ON COLUMN payment.status IS 'Logical model type: ENUM. Values were not defined in source file; represented as VARCHAR(50).';
COMMENT ON COLUMN gas.type IS 'Logical model type: ENUM. Values were not defined in source file; represented as VARCHAR(50).';
COMMENT ON COLUMN gas.scope IS 'Logical model type: ENUM. Values were not defined in source file; represented as VARCHAR(50).';
COMMENT ON COLUMN gas_reduction.unit IS 'Logical model type: ENUM. Values were not defined in source file; represented as VARCHAR(50).';
COMMENT ON COLUMN report.type IS 'Logical model type: ENUM. Values were not defined in source file; represented as VARCHAR(50).';

COMMIT;