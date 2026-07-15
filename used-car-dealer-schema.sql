-- =====================================================================
--  Used Car Dealer Platform — PostgreSQL Schema (optimized)
--  Generated from ERD: cs_detailed_erDiagram_mermaid_code.txt
--  Target engine    : PostgreSQL 13+
--
--  Design notes
--   * UUIDv7 primary keys (per ERD): time-ordered UUIDs — non-guessable like
--     v4, but sort by creation time so indexes stay compact and writes stay
--     fast. See the "Extensions & ID generation" note for version support.
--   * timestamptz everywhere (never bare timestamp); numeric(_,2) for money.
--   * Every foreign key has an explicit ON DELETE rule and a supporting index
--     (Postgres does NOT auto-index FK columns).
--   * status/type columns are guarded by named CHECK constraints. THE VALUE
--     LISTS ARE ASSUMPTIONS (lowercase snake_case) — review the "ASSUMPTION"
--     comments and adjust each list to match your application's vocabulary.
--   * Reference tables gained created_at/updated_at (marked "[+ added]") and a
--     shared updated_at trigger. Append-only tables (price history, images,
--     audit log) intentionally have no updated_at.
--   * This script CREATEs objects only. A DROP/teardown block is provided,
--     commented out, at the very bottom — opt in deliberately.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Extensions & ID generation
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- provides gen_random_uuid() (v4 fallback)

-- Primary keys default to UUIDv7 (time-ordered). Version support:
--   * PostgreSQL 18+ : uuidv7() is built in — nothing else to do.
--   * PostgreSQL < 18: uuidv7() does not exist yet. Pick ONE before running:
--       (a) install pg_uuidv7 and add a thin wrapper so the DEFAULTs resolve:
--             CREATE EXTENSION IF NOT EXISTS pg_uuidv7;
--             CREATE FUNCTION uuidv7() RETURNS uuid
--                 LANGUAGE sql AS 'SELECT uuid_generate_v7()';
--       (b) generate UUIDv7 values in your application and insert them explicitly;
--       (c) fall back to random v4 — find/replace uuidv7() -> gen_random_uuid()
--           below (simplest, but loses the index-locality benefit).
-- Check your version with:  SELECT version();

-- ---------------------------------------------------------------------
-- Shared updated_at trigger function
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
--  1. DEALER  (tenant root)
-- =====================================================================
CREATE TABLE dealer (
    dealer_id           uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_name         text        NOT NULL,
    dealer_slug         text        NOT NULL,
    business_email      text        NOT NULL,
    business_phone      text,
    gst_number          text,
    registration_number text,
    status              text        NOT NULL DEFAULT 'active',
    onboarding_status   text        NOT NULL DEFAULT 'pending',
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_dealer_slug           UNIQUE (dealer_slug),
    CONSTRAINT uq_dealer_business_email UNIQUE (business_email),
    CONSTRAINT uq_dealer_gst_number     UNIQUE (gst_number),
    -- ASSUMPTION: adjust value lists to your domain.
    CONSTRAINT ck_dealer_status
        CHECK (status IN ('active','inactive','suspended')),
    CONSTRAINT ck_dealer_onboarding_status
        CHECK (onboarding_status IN ('pending','in_progress','completed','rejected'))
);


-- =====================================================================
--  2. DEALER_BRANCH
-- =====================================================================
CREATE TABLE dealer_branch (
    branch_id     uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id     uuid        NOT NULL,
    branch_name   text        NOT NULL,
    address_line1 text,
    address_line2 text,
    city          text,
    state         text,
    pincode       text,                       -- text preserves leading zeros
    phone         text,
    email         text,
    is_primary    boolean     NOT NULL DEFAULT false,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT fk_branch_dealer
        FOREIGN KEY (dealer_id) REFERENCES dealer (dealer_id) ON DELETE CASCADE
);


-- =====================================================================
--  3. DEALER_USER
-- =====================================================================
CREATE TABLE dealer_user (
    dealer_user_id uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id      uuid        NOT NULL,
    branch_id      uuid,                        -- nullable: user may be unassigned
    first_name     text        NOT NULL,
    last_name      text,
    email          text        NOT NULL,
    mobile         text,
    role           text        NOT NULL DEFAULT 'sales',
    status         text        NOT NULL DEFAULT 'active',
    last_login_at  timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT uq_dealer_user_email UNIQUE (email),
    CONSTRAINT fk_dealer_user_dealer
        FOREIGN KEY (dealer_id) REFERENCES dealer (dealer_id) ON DELETE CASCADE,
    CONSTRAINT fk_dealer_user_branch
        FOREIGN KEY (branch_id) REFERENCES dealer_branch (branch_id) ON DELETE SET NULL,
    -- ASSUMPTION
    CONSTRAINT ck_dealer_user_role
        CHECK (role IN ('owner','admin','manager','sales','support')),
    CONSTRAINT ck_dealer_user_status
        CHECK (status IN ('active','inactive','invited','suspended'))
);


-- =====================================================================
--  4. DEALER_BRANDING  (1:1 with dealer)
-- =====================================================================
CREATE TABLE dealer_branding (
    branding_id     uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id       uuid        NOT NULL,
    logo_url        text,
    primary_color   text,
    secondary_color text,
    website_title   text,
    custom_domain   text,
    subdomain       text,
    theme_name      text,
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT uq_branding_dealer        UNIQUE (dealer_id),   -- enforces 1:1
    CONSTRAINT uq_branding_custom_domain UNIQUE (custom_domain),
    CONSTRAINT uq_branding_subdomain     UNIQUE (subdomain),
    CONSTRAINT fk_branding_dealer
        FOREIGN KEY (dealer_id) REFERENCES dealer (dealer_id) ON DELETE CASCADE
);


-- =====================================================================
--  5. VEHICLE_MASTER_MANUFACTURER  (reference data)
-- =====================================================================
CREATE TABLE vehicle_master_manufacturer (
    manufacturer_id   uuid        PRIMARY KEY DEFAULT uuidv7(),
    manufacturer_name text        NOT NULL,
    country           text,
    status            text        NOT NULL DEFAULT 'active',
    created_at        timestamptz NOT NULL DEFAULT now(),   -- [+ added]
    updated_at        timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT uq_manufacturer_name UNIQUE (manufacturer_name),
    CONSTRAINT ck_manufacturer_status CHECK (status IN ('active','inactive'))
);


-- =====================================================================
--  6. VEHICLE_MASTER_MODEL
-- =====================================================================
CREATE TABLE vehicle_master_model (
    model_id        uuid        PRIMARY KEY DEFAULT uuidv7(),
    manufacturer_id uuid        NOT NULL,
    model_name      text        NOT NULL,
    body_type       text,
    segment         text,
    status          text        NOT NULL DEFAULT 'active',
    created_at      timestamptz NOT NULL DEFAULT now(),   -- [+ added]
    updated_at      timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT uq_model_per_manufacturer UNIQUE (manufacturer_id, model_name),
    CONSTRAINT fk_model_manufacturer
        FOREIGN KEY (manufacturer_id)
        REFERENCES vehicle_master_manufacturer (manufacturer_id) ON DELETE RESTRICT,
    CONSTRAINT ck_model_status CHECK (status IN ('active','inactive'))
);


-- =====================================================================
--  7. VEHICLE_MASTER_VARIANT
-- =====================================================================
CREATE TABLE vehicle_master_variant (
    variant_id       uuid          PRIMARY KEY DEFAULT uuidv7(),
    model_id         uuid          NOT NULL,
    variant_name     text          NOT NULL,
    fuel_type        text,
    transmission     text,
    engine_capacity  text,                         -- e.g. '1497 cc'
    seating_capacity int,
    mileage          numeric(5,2),                 -- km/l
    ex_showroom_price numeric(12,2),
    status           text          NOT NULL DEFAULT 'active',
    created_at       timestamptz   NOT NULL DEFAULT now(),   -- [+ added]
    updated_at       timestamptz   NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT uq_variant_per_model UNIQUE (model_id, variant_name),
    CONSTRAINT fk_variant_model
        FOREIGN KEY (model_id)
        REFERENCES vehicle_master_model (model_id) ON DELETE RESTRICT,
    CONSTRAINT ck_variant_seating   CHECK (seating_capacity IS NULL OR seating_capacity > 0),
    CONSTRAINT ck_variant_mileage   CHECK (mileage IS NULL OR mileage >= 0),
    CONSTRAINT ck_variant_price     CHECK (ex_showroom_price IS NULL OR ex_showroom_price >= 0),
    -- ASSUMPTION
    CONSTRAINT ck_variant_fuel      CHECK (fuel_type IS NULL OR fuel_type IN
        ('petrol','diesel','cng','lpg','electric','hybrid')),
    CONSTRAINT ck_variant_transmission CHECK (transmission IS NULL OR transmission IN
        ('manual','automatic','amt','cvt','dct')),
    CONSTRAINT ck_variant_status    CHECK (status IN ('active','inactive'))
);


-- =====================================================================
--  8. CUSTOMER  (created before VEHICLE-dependent tables that need it)
-- =====================================================================
CREATE TABLE customer (
    customer_id   uuid        PRIMARY KEY DEFAULT uuidv7(),
    first_name    text        NOT NULL,
    last_name     text,
    mobile        text        NOT NULL,
    email         text,
    customer_type text        NOT NULL DEFAULT 'buyer',
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT uq_customer_mobile UNIQUE (mobile),
    -- ASSUMPTION
    CONSTRAINT ck_customer_type CHECK (customer_type IN ('buyer','seller','both'))
);


-- =====================================================================
--  9. VEHICLE  (listing)
-- =====================================================================
CREATE TABLE vehicle (
    vehicle_id              uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id               uuid        NOT NULL,
    branch_id               uuid,                       -- nullable (SET NULL)
    variant_id              uuid        NOT NULL,
    registration_number     text,
    manufacturing_year      int,
    registration_year       int,
    fuel_type               text,
    transmission            text,
    kilometers_driven       int,
    ownership_count         int,
    asking_price            numeric(12,2),
    expected_price          numeric(12,2),
    color                   text,
    insurance_status        text,
    listing_status          text        NOT NULL DEFAULT 'draft',
    description             text,
    ai_generated_description text,
    listing_quality_score   int,
    listed_at               timestamptz,
    sold_at                 timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_vehicle_dealer
        FOREIGN KEY (dealer_id) REFERENCES dealer (dealer_id) ON DELETE CASCADE,
    CONSTRAINT fk_vehicle_branch
        FOREIGN KEY (branch_id) REFERENCES dealer_branch (branch_id) ON DELETE SET NULL,
    CONSTRAINT fk_vehicle_variant
        FOREIGN KEY (variant_id)
        REFERENCES vehicle_master_variant (variant_id) ON DELETE RESTRICT,
    CONSTRAINT ck_vehicle_km        CHECK (kilometers_driven IS NULL OR kilometers_driven >= 0),
    CONSTRAINT ck_vehicle_ownership CHECK (ownership_count   IS NULL OR ownership_count   >= 0),
    CONSTRAINT ck_vehicle_asking    CHECK (asking_price      IS NULL OR asking_price      >= 0),
    CONSTRAINT ck_vehicle_expected  CHECK (expected_price    IS NULL OR expected_price    >= 0),
    CONSTRAINT ck_vehicle_quality   CHECK (listing_quality_score IS NULL
                                           OR listing_quality_score BETWEEN 0 AND 100),
    CONSTRAINT ck_vehicle_mfg_year  CHECK (manufacturing_year IS NULL
                                           OR manufacturing_year BETWEEN 1900 AND 2100),
    -- ASSUMPTION
    CONSTRAINT ck_vehicle_fuel      CHECK (fuel_type IS NULL OR fuel_type IN
        ('petrol','diesel','cng','lpg','electric','hybrid')),
    CONSTRAINT ck_vehicle_transmission CHECK (transmission IS NULL OR transmission IN
        ('manual','automatic','amt','cvt','dct')),
    CONSTRAINT ck_vehicle_insurance CHECK (insurance_status IS NULL OR insurance_status IN
        ('active','expired','none')),
    CONSTRAINT ck_vehicle_listing_status CHECK (listing_status IN
        ('draft','available','reserved','sold','inactive'))
);


-- =====================================================================
-- 10. VEHICLE_IMAGE  (belongs to a vehicle OR a sale request)
-- =====================================================================
CREATE TABLE vehicle_image (
    image_id        uuid        PRIMARY KEY DEFAULT uuidv7(),
    vehicle_id      uuid,                        -- one of vehicle_id / sale_request_id
    sale_request_id uuid,
    image_url       text        NOT NULL,
    thumbnail_url   text,
    image_type      text,
    display_order   int         NOT NULL DEFAULT 0,
    is_primary      boolean     NOT NULL DEFAULT false,
    ai_quality_status text,
    uploaded_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_image_vehicle
        FOREIGN KEY (vehicle_id) REFERENCES vehicle (vehicle_id) ON DELETE CASCADE,
    -- fk_image_sale_request is added after vehicle_sale_request exists (section 14a)
    -- image must attach to at least one parent
    CONSTRAINT ck_image_parent
        CHECK (vehicle_id IS NOT NULL OR sale_request_id IS NOT NULL),
    -- ASSUMPTION
    CONSTRAINT ck_image_type CHECK (image_type IS NULL OR image_type IN
        ('exterior','interior','engine','document','other')),
    CONSTRAINT ck_image_ai_quality CHECK (ai_quality_status IS NULL OR ai_quality_status IN
        ('pending','approved','rejected'))
);
-- NOTE: fk_image_sale_request references vehicle_sale_request, created below.
--       This FK is added after that table exists (see ALTER at section 14a).


-- =====================================================================
-- 11. VEHICLE_CONDITION_REPORT
-- =====================================================================
CREATE TABLE vehicle_condition_report (
    condition_report_id uuid        PRIMARY KEY DEFAULT uuidv7(),
    vehicle_id          uuid        NOT NULL,
    exterior_condition  text,
    interior_condition  text,
    engine_condition    text,
    tyre_condition      text,
    accident_history    text,
    service_history     text,
    condition_score     int,
    ai_condition_summary text,
    report_status       text        NOT NULL DEFAULT 'draft',
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_condition_vehicle
        FOREIGN KEY (vehicle_id) REFERENCES vehicle (vehicle_id) ON DELETE CASCADE,
    CONSTRAINT ck_condition_score CHECK (condition_score IS NULL
                                         OR condition_score BETWEEN 0 AND 100),
    -- ASSUMPTION
    CONSTRAINT ck_condition_report_status
        CHECK (report_status IN ('draft','completed'))
);


-- =====================================================================
-- 12. VEHICLE_PRICE_HISTORY  (append-only)
-- =====================================================================
CREATE TABLE vehicle_price_history (
    price_history_id uuid        PRIMARY KEY DEFAULT uuidv7(),
    vehicle_id       uuid        NOT NULL,
    old_price        numeric(12,2),
    new_price        numeric(12,2),
    change_reason    text,
    changed_at       timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_price_history_vehicle
        FOREIGN KEY (vehicle_id) REFERENCES vehicle (vehicle_id) ON DELETE CASCADE,
    CONSTRAINT ck_price_history_old CHECK (old_price IS NULL OR old_price >= 0),
    CONSTRAINT ck_price_history_new CHECK (new_price IS NULL OR new_price >= 0)
);


-- =====================================================================
-- 13. LEAD
-- =====================================================================
CREATE TABLE lead (
    lead_id        uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id      uuid        NOT NULL,
    vehicle_id     uuid,                        -- nullable: survives vehicle removal
    customer_id    uuid        NOT NULL,
    lead_type      text,
    lead_source    text,
    lead_status    text        NOT NULL DEFAULT 'new',
    interest_level text,
    message        text,
    follow_up_date timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_lead_dealer
        FOREIGN KEY (dealer_id)  REFERENCES dealer (dealer_id)   ON DELETE CASCADE,
    CONSTRAINT fk_lead_vehicle
        FOREIGN KEY (vehicle_id) REFERENCES vehicle (vehicle_id) ON DELETE SET NULL,
    CONSTRAINT fk_lead_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id) ON DELETE RESTRICT,
    -- ASSUMPTION
    CONSTRAINT ck_lead_type   CHECK (lead_type IS NULL OR lead_type IN
        ('buy','sell','finance','test_drive','enquiry')),
    CONSTRAINT ck_lead_source CHECK (lead_source IS NULL OR lead_source IN
        ('website','walk_in','phone','referral','marketplace','social')),
    CONSTRAINT ck_lead_status CHECK (lead_status IN
        ('new','contacted','qualified','negotiation','won','lost')),
    CONSTRAINT ck_lead_interest CHECK (interest_level IS NULL OR interest_level IN
        ('low','medium','high'))
);


-- =====================================================================
-- 14. VEHICLE_SALE_REQUEST  (customer offering a car to the dealer)
-- =====================================================================
CREATE TABLE vehicle_sale_request (
    sale_request_id   uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id         uuid        NOT NULL,
    customer_id       uuid        NOT NULL,
    manufacturer_name text,
    model_name        text,
    variant_name      text,
    manufacturing_year int,
    kilometers_driven int,
    fuel_type         text,
    transmission      text,
    ownership_count   int,
    expected_price    numeric(12,2),
    seller_notes      text,
    request_status    text        NOT NULL DEFAULT 'submitted',
    submitted_at      timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_sale_request_dealer
        FOREIGN KEY (dealer_id)   REFERENCES dealer (dealer_id)     ON DELETE CASCADE,
    CONSTRAINT fk_sale_request_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id) ON DELETE RESTRICT,
    CONSTRAINT ck_sale_request_km        CHECK (kilometers_driven IS NULL OR kilometers_driven >= 0),
    CONSTRAINT ck_sale_request_ownership CHECK (ownership_count   IS NULL OR ownership_count   >= 0),
    CONSTRAINT ck_sale_request_price     CHECK (expected_price    IS NULL OR expected_price    >= 0),
    -- ASSUMPTION
    CONSTRAINT ck_sale_request_fuel CHECK (fuel_type IS NULL OR fuel_type IN
        ('petrol','diesel','cng','lpg','electric','hybrid')),
    CONSTRAINT ck_sale_request_transmission CHECK (transmission IS NULL OR transmission IN
        ('manual','automatic','amt','cvt','dct')),
    CONSTRAINT ck_sale_request_status CHECK (request_status IN
        ('submitted','under_review','accepted','rejected','completed'))
);

-- 14a. Deferred FK: vehicle_image.sale_request_id -> vehicle_sale_request
--      (vehicle_image was created first; add the FK now that the target exists)
ALTER TABLE vehicle_image
    ADD CONSTRAINT fk_image_sale_request
    FOREIGN KEY (sale_request_id)
    REFERENCES vehicle_sale_request (sale_request_id) ON DELETE CASCADE;


-- =====================================================================
-- 15. FINANCE_ENQUIRY
-- =====================================================================
CREATE TABLE finance_enquiry (
    finance_enquiry_id    uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id             uuid        NOT NULL,
    vehicle_id            uuid,                        -- nullable (SET NULL)
    customer_id           uuid        NOT NULL,
    vehicle_price         numeric(12,2),
    requested_loan_amount numeric(12,2),
    down_payment          numeric(12,2),
    tenure_months         int,
    employment_type       text,
    enquiry_status        text        NOT NULL DEFAULT 'new',
    finance_partner_status text,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_finance_dealer
        FOREIGN KEY (dealer_id)   REFERENCES dealer (dealer_id)     ON DELETE CASCADE,
    CONSTRAINT fk_finance_vehicle
        FOREIGN KEY (vehicle_id)  REFERENCES vehicle (vehicle_id)   ON DELETE SET NULL,
    CONSTRAINT fk_finance_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id) ON DELETE RESTRICT,
    CONSTRAINT ck_finance_vehicle_price CHECK (vehicle_price         IS NULL OR vehicle_price         >= 0),
    CONSTRAINT ck_finance_loan          CHECK (requested_loan_amount IS NULL OR requested_loan_amount >= 0),
    CONSTRAINT ck_finance_down          CHECK (down_payment          IS NULL OR down_payment          >= 0),
    CONSTRAINT ck_finance_tenure        CHECK (tenure_months         IS NULL OR tenure_months         > 0),
    -- ASSUMPTION
    CONSTRAINT ck_finance_employment CHECK (employment_type IS NULL OR employment_type IN
        ('salaried','self_employed','business','other')),
    CONSTRAINT ck_finance_status CHECK (enquiry_status IN
        ('new','processing','approved','rejected')),
    CONSTRAINT ck_finance_partner_status CHECK (finance_partner_status IS NULL
        OR finance_partner_status IN ('pending','submitted','approved','rejected'))
);


-- =====================================================================
-- 16. PLAN  (reference data)
-- =====================================================================
CREATE TABLE plan (
    plan_id                uuid        PRIMARY KEY DEFAULT uuidv7(),
    plan_name              text        NOT NULL,
    plan_code              text        NOT NULL,
    monthly_price          numeric(10,2) NOT NULL DEFAULT 0,
    vehicle_listing_limit  int,
    image_limit_per_vehicle int,
    user_limit             int,
    ai_description_enabled boolean     NOT NULL DEFAULT false,
    finance_module_enabled boolean     NOT NULL DEFAULT false,
    custom_domain_enabled  boolean     NOT NULL DEFAULT false,
    status                 text        NOT NULL DEFAULT 'active',
    created_at             timestamptz NOT NULL DEFAULT now(),   -- [+ added]
    updated_at             timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT uq_plan_code   UNIQUE (plan_code),
    CONSTRAINT ck_plan_price  CHECK (monthly_price >= 0),
    CONSTRAINT ck_plan_status CHECK (status IN ('active','inactive'))
);


-- =====================================================================
-- 17. SUBSCRIPTION
-- =====================================================================
CREATE TABLE subscription (
    subscription_id     uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id           uuid        NOT NULL,
    plan_id             uuid        NOT NULL,
    subscription_status text        NOT NULL DEFAULT 'active',
    start_date          date,
    end_date            date,
    renewal_date        date,
    billing_cycle       text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),   -- [+ added]

    CONSTRAINT fk_subscription_dealer
        FOREIGN KEY (dealer_id) REFERENCES dealer (dealer_id) ON DELETE CASCADE,
    CONSTRAINT fk_subscription_plan
        FOREIGN KEY (plan_id)   REFERENCES plan (plan_id)     ON DELETE RESTRICT,
    CONSTRAINT ck_subscription_dates
        CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date),
    -- ASSUMPTION
    CONSTRAINT ck_subscription_status CHECK (subscription_status IN
        ('trial','active','past_due','cancelled','expired')),
    CONSTRAINT ck_subscription_cycle CHECK (billing_cycle IS NULL OR billing_cycle IN
        ('monthly','quarterly','annual'))
);


-- =====================================================================
-- 18. AUDIT_LOG  (append-only; preserved even if dealer/user removed)
-- =====================================================================
CREATE TABLE audit_log (
    audit_log_id   uuid        PRIMARY KEY DEFAULT uuidv7(),
    dealer_id      uuid,                        -- SET NULL to preserve trail
    dealer_user_id uuid,                        -- SET NULL to preserve trail
    entity_name    text        NOT NULL,
    entity_id      uuid,
    action         text        NOT NULL,
    old_value      text,                        -- consider jsonb for structured diffs
    new_value      text,
    ip_address     inet,                        -- native IP type
    created_at     timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_audit_dealer
        FOREIGN KEY (dealer_id)      REFERENCES dealer (dealer_id)          ON DELETE SET NULL,
    CONSTRAINT fk_audit_dealer_user
        FOREIGN KEY (dealer_user_id) REFERENCES dealer_user (dealer_user_id) ON DELETE SET NULL,
    -- ASSUMPTION
    CONSTRAINT ck_audit_action CHECK (action IN
        ('create','update','delete','login','logout'))
);


-- =====================================================================
--  updated_at triggers (every table carrying an updated_at column)
-- =====================================================================
CREATE TRIGGER trg_dealer_updated_at            BEFORE UPDATE ON dealer                      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_dealer_branch_updated_at     BEFORE UPDATE ON dealer_branch               FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_dealer_user_updated_at       BEFORE UPDATE ON dealer_user                 FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_dealer_branding_updated_at   BEFORE UPDATE ON dealer_branding             FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_manufacturer_updated_at      BEFORE UPDATE ON vehicle_master_manufacturer FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_model_updated_at             BEFORE UPDATE ON vehicle_master_model        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_variant_updated_at           BEFORE UPDATE ON vehicle_master_variant      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_customer_updated_at          BEFORE UPDATE ON customer                    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_vehicle_updated_at           BEFORE UPDATE ON vehicle                     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_condition_updated_at         BEFORE UPDATE ON vehicle_condition_report    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_lead_updated_at              BEFORE UPDATE ON lead                        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_sale_request_updated_at      BEFORE UPDATE ON vehicle_sale_request        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_finance_updated_at           BEFORE UPDATE ON finance_enquiry             FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_plan_updated_at              BEFORE UPDATE ON plan                        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_subscription_updated_at      BEFORE UPDATE ON subscription                FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =====================================================================
--  Indexes  (foreign keys + common query paths)
-- =====================================================================
-- Foreign-key indexes
CREATE INDEX idx_branch_dealer            ON dealer_branch            (dealer_id);
CREATE INDEX idx_dealer_user_dealer       ON dealer_user             (dealer_id);
CREATE INDEX idx_dealer_user_branch       ON dealer_user             (branch_id);
CREATE INDEX idx_model_manufacturer       ON vehicle_master_model    (manufacturer_id);
CREATE INDEX idx_variant_model            ON vehicle_master_variant  (model_id);
CREATE INDEX idx_vehicle_dealer           ON vehicle                 (dealer_id);
CREATE INDEX idx_vehicle_branch           ON vehicle                 (branch_id);
CREATE INDEX idx_vehicle_variant          ON vehicle                 (variant_id);
CREATE INDEX idx_image_vehicle            ON vehicle_image           (vehicle_id);
CREATE INDEX idx_image_sale_request       ON vehicle_image           (sale_request_id);
CREATE INDEX idx_condition_vehicle        ON vehicle_condition_report(vehicle_id);
CREATE INDEX idx_price_history_vehicle    ON vehicle_price_history   (vehicle_id);
CREATE INDEX idx_lead_dealer              ON lead                    (dealer_id);
CREATE INDEX idx_lead_vehicle             ON lead                    (vehicle_id);
CREATE INDEX idx_lead_customer            ON lead                    (customer_id);
CREATE INDEX idx_sale_request_dealer      ON vehicle_sale_request    (dealer_id);
CREATE INDEX idx_sale_request_customer    ON vehicle_sale_request    (customer_id);
CREATE INDEX idx_finance_dealer           ON finance_enquiry         (dealer_id);
CREATE INDEX idx_finance_vehicle          ON finance_enquiry         (vehicle_id);
CREATE INDEX idx_finance_customer         ON finance_enquiry         (customer_id);
CREATE INDEX idx_subscription_dealer      ON subscription            (dealer_id);
CREATE INDEX idx_subscription_plan        ON subscription            (plan_id);
CREATE INDEX idx_audit_dealer             ON audit_log               (dealer_id);
CREATE INDEX idx_audit_dealer_user        ON audit_log               (dealer_user_id);

-- Common query paths (composite / partial)
CREATE INDEX idx_vehicle_dealer_status    ON vehicle          (dealer_id, listing_status);
CREATE INDEX idx_vehicle_listed_at        ON vehicle          (listed_at DESC);
CREATE INDEX idx_lead_dealer_status       ON lead             (dealer_id, lead_status);
CREATE INDEX idx_lead_follow_up           ON lead             (follow_up_date)
    WHERE follow_up_date IS NOT NULL;
CREATE INDEX idx_finance_dealer_status    ON finance_enquiry  (dealer_id, enquiry_status);
CREATE INDEX idx_sale_request_dealer_status ON vehicle_sale_request (dealer_id, request_status);
CREATE INDEX idx_subscription_renewal     ON subscription     (renewal_date)
    WHERE renewal_date IS NOT NULL;
CREATE INDEX idx_price_history_vehicle_time ON vehicle_price_history (vehicle_id, changed_at DESC);
CREATE INDEX idx_audit_entity             ON audit_log        (entity_name, entity_id);
CREATE INDEX idx_audit_dealer_time        ON audit_log        (dealer_id, created_at DESC);
CREATE INDEX idx_customer_email           ON customer         (email) WHERE email IS NOT NULL;

-- Uniqueness that depends on a predicate (partial unique indexes)
--   * one active reg-number per platform (only when present)
CREATE UNIQUE INDEX uq_vehicle_reg_number ON vehicle (registration_number)
    WHERE registration_number IS NOT NULL;
--   * exactly one primary branch per dealer
CREATE UNIQUE INDEX uq_primary_branch_per_dealer ON dealer_branch (dealer_id)
    WHERE is_primary;
--   * one primary image per vehicle
CREATE UNIQUE INDEX uq_primary_image_per_vehicle ON vehicle_image (vehicle_id)
    WHERE is_primary AND vehicle_id IS NOT NULL;


-- =====================================================================
--  Table / column comments (documentation)
-- =====================================================================
COMMENT ON TABLE dealer                IS 'Tenant root: each dealer is an isolated account.';
COMMENT ON TABLE dealer_branding       IS '1:1 white-label branding per dealer (uq_branding_dealer).';
COMMENT ON TABLE vehicle               IS 'Individual used-car listing owned by a dealer.';
COMMENT ON TABLE vehicle_image         IS 'Image attached to EITHER a vehicle OR a sale request (ck_image_parent).';
COMMENT ON TABLE vehicle_price_history IS 'Append-only log of asking-price changes.';
COMMENT ON TABLE audit_log             IS 'Append-only audit trail; dealer/user FKs SET NULL on delete to preserve history.';
COMMENT ON COLUMN audit_log.ip_address IS 'Client IP stored as native inet type.';
COMMENT ON COLUMN vehicle.listing_quality_score IS 'AI-assigned 0-100 listing quality.';


-- =====================================================================
--  OPTIONAL TEARDOWN — DESTRUCTIVE. Review carefully before running.
--  Uncomment ONLY to drop and rebuild in a dev/test environment.
--  Drops are ordered to satisfy foreign-key dependencies.
-- =====================================================================
-- DROP TABLE IF EXISTS audit_log                     CASCADE;
-- DROP TABLE IF EXISTS subscription                  CASCADE;
-- DROP TABLE IF EXISTS plan                          CASCADE;
-- DROP TABLE IF EXISTS finance_enquiry               CASCADE;
-- DROP TABLE IF EXISTS vehicle_sale_request          CASCADE;
-- DROP TABLE IF EXISTS lead                          CASCADE;
-- DROP TABLE IF EXISTS vehicle_price_history         CASCADE;
-- DROP TABLE IF EXISTS vehicle_condition_report      CASCADE;
-- DROP TABLE IF EXISTS vehicle_image                 CASCADE;
-- DROP TABLE IF EXISTS vehicle                       CASCADE;
-- DROP TABLE IF EXISTS customer                      CASCADE;
-- DROP TABLE IF EXISTS vehicle_master_variant        CASCADE;
-- DROP TABLE IF EXISTS vehicle_master_model          CASCADE;
-- DROP TABLE IF EXISTS vehicle_master_manufacturer   CASCADE;
-- DROP TABLE IF EXISTS dealer_branding               CASCADE;
-- DROP TABLE IF EXISTS dealer_user                   CASCADE;
-- DROP TABLE IF EXISTS dealer_branch                 CASCADE;
-- DROP TABLE IF EXISTS dealer                        CASCADE;
-- DROP FUNCTION IF EXISTS set_updated_at()           CASCADE;
-- =====================================================================
--  End of schema
-- =====================================================================
