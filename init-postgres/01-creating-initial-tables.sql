BEGIN;

CREATE TYPE payment_status AS ENUM (
    'PENDING',
    'PAID',
    'OVERDUE',
    'CANCELED'
);

CREATE TYPE storage_file_type AS ENUM (
    'PNG',
    'JPG',
    'JPEG',
    'PDF',
    'DOC',
    'DOCX'
);

CREATE TYPE employee_status AS ENUM (
    'ACTIVE',
    'INACTIVE',
    'VACATION'
);


CREATE TABLE plan (
    id SERIAL PRIMARY KEY,
    description VARCHAR(255),
    price NUMERIC,
    is_active BOOLEAN,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE address (
    id SERIAL PRIMARY KEY,
    zip_code CHAR(8),
    street VARCHAR(255),
    neighborhood VARCHAR(255),
    city VARCHAR(100),
    state CHAR(2),
    number INTEGER,
    complement VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE enterprise (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    trade_name VARCHAR(255) NOT NULL,
    cnpj CHAR(14) UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_address INTEGER NOT NULL REFERENCES address (id)
);

CREATE TABLE plan_subscription (
    id SERIAL PRIMARY KEY,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    installments INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deactivated_at TIMESTAMP,
    id_plan INTEGER NOT NULL REFERENCES plan (id) ON DELETE CASCADE,
    id_enterprise INTEGER NOT NULL REFERENCES enterprise (id)
);

  CREATE TABLE payment (
    id SERIAL PRIMARY KEY,
    value NUMERIC NOT NULL,
    term TIMESTAMP,
    status payment_status NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_plan_subscription INTEGER NOT NULL REFERENCES plan_subscription (id) ON DELETE RESTRICT
  );

CREATE TABLE unit (
    id SERIAL PRIMARY KEY,
    cnae CHAR(7) UNIQUE NOT NULL,
    cnpj CHAR(14) UNIQUE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_enterprise INTEGER NOT NULL REFERENCES enterprise (id),
    id_address INTEGER NOT NULL REFERENCES address (id)
);

CREATE TABLE department (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_unit INTEGER NOT NULL REFERENCES unit (id) ON DELETE RESTRICT
);

CREATE TABLE permission_group (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description VARCHAR(255)
);

CREATE TABLE permission (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255)
);

CREATE TABLE permission_group_permission (
    id SERIAL PRIMARY KEY,
    id_permission INTEGER NOT NULL REFERENCES permission (id),
    id_permission_group INTEGER NOT NULL REFERENCES permission_group (id),
    UNIQUE (id_permission, id_permission_group)
);

CREATE TABLE parana_seal_forecast (
    id SERIAL PRIMARY KEY,
    score NUMERIC,
    level INTEGER,
    valid_until TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_unit INTEGER NOT NULL REFERENCES unit (id) ON DELETE CASCADE
);

CREATE TABLE gas (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    formula VARCHAR(255),
    gwp NUMERIC,
    description VARCHAR(255),
    type VARCHAR(50),
    scope VARCHAR(50)
);

CREATE TABLE gas_reduction (
    id SERIAL PRIMARY KEY,
    estimated_reduction NUMERIC NOT NULL,
    estimated_roi NUMERIC,
    initial_emission NUMERIC NOT NULL,
    current_emission NUMERIC NOT NULL,
    unit VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_gas INTEGER NOT NULL REFERENCES gas (id) ON DELETE CASCADE
);

CREATE TABLE projection_years (
    id SERIAL PRIMARY KEY,
    prediction NUMERIC,
    actual NUMERIC,
    year INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_gas_reduction INTEGER NOT NULL REFERENCES gas_reduction (id) ON DELETE CASCADE
);

CREATE TABLE administrator (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE storage_file (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    path VARCHAR(400),
    size_bytes BIGINT,
    file_type storage_file_type NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE employee (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(15),
    password_hash VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status employee_status NOT NULL DEFAULT 'ACTIVE',
    id_storage_file INTEGER REFERENCES storage_file (id)
);

CREATE TABLE report (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    type VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_department INTEGER NOT NULL REFERENCES department (id),
    id_gas_reduction INTEGER NOT NULL REFERENCES gas_reduction (id),
    id_storage_file INTEGER NOT NULL REFERENCES storage_file (id),
    id_owner_employee INTEGER NOT NULL REFERENCES employee (id),
    id_validator_employee INTEGER REFERENCES employee (id),
    id_input_report INTEGER REFERENCES report (id)
);

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
CREATE INDEX idx_gas_reduction_id_gas ON gas_reduction (id_gas);
CREATE INDEX idx_projection_years_id_gas_reduction ON projection_years (id_gas_reduction);  
CREATE INDEX idx_employee_id_storage_file ON employee (id_storage_file);
CREATE INDEX idx_report_id_department ON report (id_department);
CREATE INDEX idx_report_id_gas_reduction ON report (id_gas_reduction);
CREATE INDEX idx_report_id_storage_file ON report (id_storage_file);
CREATE INDEX idx_report_id_owner_employee ON report (id_owner_employee);
CREATE INDEX idx_report_id_validator_employee ON report (id_validator_employee);
CREATE INDEX idx_report_id_input_report ON report (id_input_report);

COMMIT;