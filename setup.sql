-- Greenmask Issue #396 — Minimal reproduction schema
-- Polymorphic association with NO DATABASE FKs (all virtual references)
--
-- Mirrors a Rails app where belongs_to associations have no DB constraints.
-- Greenmask must rely entirely on virtual_references for the subset graph.
--
-- Graph (all edges are virtual references, no DB FKs):
--   accounts (subset root)
--     → projects (account_id)
--         → audits (project_id)
--             → controls (audit_id)
--         → confirmations (project_id)
--             → confirmation_items (confirmation_id)
--   comments (polymorphic: commentable_type/id → controls | confirmation_items)

CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL, -- NO FK constraint
    name TEXT NOT NULL
);

CREATE TABLE audits (
    id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL, -- NO FK constraint
    name TEXT NOT NULL
);

CREATE TABLE controls (
    id SERIAL PRIMARY KEY,
    audit_id INTEGER NOT NULL, -- NO FK constraint
    name TEXT NOT NULL
);

CREATE TABLE confirmations (
    id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL, -- NO FK constraint
    name TEXT NOT NULL
);

CREATE TABLE confirmation_items (
    id SERIAL PRIMARY KEY,
    confirmation_id INTEGER NOT NULL, -- NO FK constraint
    name TEXT NOT NULL
);

CREATE TABLE comments (
    id SERIAL PRIMARY KEY,
    commentable_type TEXT NOT NULL,
    commentable_id INTEGER NOT NULL,
    body TEXT NOT NULL
);

-- Account 1 (in subset), Account 2 (not in subset)
INSERT INTO accounts (name) VALUES ('Acme Corp'), ('Other Corp');

-- Projects: 1 per account
INSERT INTO projects (account_id, name) VALUES
    (1, 'Project Alpha'),  -- id=1
    (2, 'Project Beta');   -- id=2

-- Audits: 1 per project
INSERT INTO audits (project_id, name) VALUES
    (1, 'Audit 2024'),   -- id=1 (account 1)
    (2, 'Audit 2025');   -- id=2 (account 2)

-- Controls: 2 per audit
INSERT INTO controls (audit_id, name) VALUES
    (1, 'Control A1'),  -- id=1 (account 1)
    (1, 'Control A2'),  -- id=2 (account 1)
    (2, 'Control B1');  -- id=3 (account 2)

-- Confirmations: 1 per project
INSERT INTO confirmations (project_id, name) VALUES
    (1, 'XBA 2024'),   -- id=1 (account 1)
    (2, 'XBA 2025');   -- id=2 (account 2)

-- Confirmation items: 2 per confirmation
INSERT INTO confirmation_items (confirmation_id, name) VALUES
    (1, 'Item X1'),  -- id=1 (account 1)
    (1, 'Item X2'),  -- id=2 (account 1)
    (2, 'Item Y1');  -- id=3 (account 2)

-- Comments: polymorphic to controls and confirmation_items
INSERT INTO comments (commentable_type, commentable_id, body) VALUES
    ('Control',          1, 'Comment on Control A1'),  -- id=1, EXPECT: included
    ('Control',          2, 'Comment on Control A2'),  -- id=2, EXPECT: included
    ('Control',          3, 'Comment on Control B1'),  -- id=3, EXPECT: excluded
    ('ConfirmationItem', 1, 'Comment on Item X1'),     -- id=4, EXPECT: included
    ('ConfirmationItem', 2, 'Comment on Item X2'),     -- id=5, EXPECT: included
    ('ConfirmationItem', 3, 'Comment on Item Y1');     -- id=6, EXPECT: excluded
