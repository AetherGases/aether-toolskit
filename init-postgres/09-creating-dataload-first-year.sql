/*
============================================================
DATALOAD - DADOS REAIS 
============================================================
*/ 

BEGIN;

-- PLANOS
INSERT INTO plans (id, name, description, price, duration_days, currency)
VALUES
(1,'Aether Pulse','Quantidade de cadastro limitada a 10 funcionários; quantidade de analistas e administradores limitada a 2; acompanhamento mensal',3300.00,30,'Reais'),
(2,'Aether Horizon','Tudo do plano Aether Pulse; quantidade de cadastro de funcionários ilimitada; acompanhamento trimestral',9400.00,90,'Reais');


-- GASES 
INSERT INTO gases (id, name, type, measurement, gwp)
VALUES
(1,'Monóxido de Carbono','Gás de emissão poluente','Moderado',2),
(2,'Óxido Nitroso','Gás de emissão poluente','Alto',273),
(3,'Hexafluoreto de Enxofre','Gás de emissão poluente','Extremo',23500),
(4,'Trifluorometano','Gás de emissão poluente','Extremo',14800),
(5,'Tetrafluoroetano','Gás de emissão poluente','Alto',1430),
(6,'Óxidos de Nitrogênio','Gás de emissão poluente','Alto',298);


--PERMISSOES
INSERT INTO permission (id, name, description, pattern) VALUES
    (1, 'user:analytics:visibility:high', 'High analytics visibility across the enterprise hierarchy', 'user:analytics:visibility:high'),
    (2, 'inventory:analysis', 'Inventory analysis access', '/api/inventories/(count|pending(/\d+/(approve|reject))?|reviewed(/(last|\d+))?)'),
    (3, 'inventory:register', 'Inventory create and edit access', '/api/inventories(/(count|mine(/(last|\d+))?))?'),
    (4, 'inventory:generate', 'Generate an output report', '/api/inventories/generate'),
    (5, 'calculator:gases', 'Gases forecast calculator access', '(/api/calculator)?/(gases|reduction/forecast)'),
    (6, 'calculator:roi', 'Investment forecast calculator access', '(/api/calculator)?/cost-reduction/forecast'),
    (7, 'chatbot', 'Chatbot access', 'chatbot');

