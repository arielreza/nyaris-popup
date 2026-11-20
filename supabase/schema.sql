-- =============================================================================
-- PopUpPOS — Supabase Database Schema
-- Idempotent: safe to run multiple times
-- Supports 3-Way Revenue Share Split (Venue Share %, Organizer Share %, Tenant Net)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- EXTENSIONS
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid() on older PG
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- belt-and-suspenders


-- =============================================================================
-- TABLES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- master_tenants (Standalone Brand Directory)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS master_tenants (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    text        NOT NULL,
    category                text,
    instagram               text,
    pic_name                text,
    whatsapp                text,
    bank_name               text,
    bank_account            text,
    bank_holder             text,
    bank_info               text,
    contact_info            text,
    created_at              timestamptz DEFAULT now()
);

-- Safe migration columns for existing master_tenants
ALTER TABLE master_tenants ADD COLUMN IF NOT EXISTS instagram text;
ALTER TABLE master_tenants ADD COLUMN IF NOT EXISTS pic_name text;
ALTER TABLE master_tenants ADD COLUMN IF NOT EXISTS whatsapp text;
ALTER TABLE master_tenants ADD COLUMN IF NOT EXISTS bank_name text;
ALTER TABLE master_tenants ADD COLUMN IF NOT EXISTS bank_account text;
ALTER TABLE master_tenants ADD COLUMN IF NOT EXISTS bank_holder text;

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    text        NOT NULL,
    venue                   text,
    event_dates             text,
    default_share_percent   numeric     DEFAULT 10.0,
    venue_share_percent     numeric     DEFAULT 10.0,
    organizer_share_percent numeric     DEFAULT 0.0,
    status                  text        NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED')),
    is_active               boolean     DEFAULT true,
    created_at              timestamptz DEFAULT now()
);

-- Safe migration columns for existing databases
ALTER TABLE events ADD COLUMN IF NOT EXISTS venue_share_percent numeric DEFAULT 10.0;
ALTER TABLE events ADD COLUMN IF NOT EXISTS organizer_share_percent numeric DEFAULT 0.0;
ALTER TABLE events ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'ACTIVE';
DO $$ BEGIN
  ALTER TABLE events DROP CONSTRAINT IF EXISTS events_status_check;
  ALTER TABLE events ADD CONSTRAINT events_status_check CHECK (status IN ('ACTIVE', 'COMPLETED'));
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- tenants
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenants (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id                uuid        NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    master_tenant_id        uuid        REFERENCES master_tenants(id) ON DELETE SET NULL,
    name                    text        NOT NULL,
    category                text,
    booth_number            text,
    share_percent           numeric     DEFAULT 10.0,
    venue_share_percent     numeric     DEFAULT 10.0,
    organizer_share_percent numeric     DEFAULT 0.0,
    access_token            uuid        UNIQUE DEFAULT gen_random_uuid(),
    bank_info               text,
    payout_status           text        DEFAULT 'PENDING'
                                        CHECK (payout_status IN ('PENDING', 'SETTLED')),
    created_at              timestamptz DEFAULT now()
);

-- Safe migration columns for existing databases
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS venue_share_percent numeric DEFAULT 10.0;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS organizer_share_percent numeric DEFAULT 0.0;
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS master_tenant_id uuid REFERENCES master_tenants(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        uuid        REFERENCES events(id),
    receipt_code    text        UNIQUE,
    client_tx_id    uuid,
    payment_method  text        CHECK (payment_method IN ('QRIS', 'CASH')),
    total_amount    numeric     DEFAULT 0,
    cash_tendered   numeric(12,2),
    change_amount   numeric(12,2),
    status          text        DEFAULT 'COMPLETED'
                                CHECK (status IN ('COMPLETED', 'VOIDED', 'VOID')),
    void_reason     text,
    voided_at       timestamptz,
    created_at      timestamptz DEFAULT now()
);

-- Safe migration columns and constraints for existing transactions
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cash_tendered numeric(12,2);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS change_amount numeric(12,2);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS void_reason text;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS voided_at timestamptz;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS client_tx_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_client_tx_id_unique ON transactions (client_tx_id) WHERE client_tx_id IS NOT NULL;
DO $$ BEGIN
  ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_status_check;
  ALTER TABLE transactions ADD CONSTRAINT transactions_status_check CHECK (status IN ('COMPLETED', 'VOIDED', 'VOID'));
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- transaction_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_items (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id          uuid        NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    tenant_id               uuid        REFERENCES tenants(id),
    item_note               text,
    gross_amount            numeric     NOT NULL,
    share_percent           numeric     NOT NULL DEFAULT 10.0,
    venue_share_percent     numeric     DEFAULT 0.0,
    organizer_share_percent numeric     DEFAULT 0.0,
    venue_cut               numeric     DEFAULT 0.0,
    organizer_cut           numeric     DEFAULT 0.0,
    tenant_net              numeric,
    created_at              timestamptz DEFAULT now()
);

-- Safe migration columns for existing databases
ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS venue_share_percent numeric DEFAULT 0.0;
ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS organizer_share_percent numeric DEFAULT 0.0;
ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS venue_cut numeric DEFAULT 0.0;


-- =============================================================================
-- TRIGGER: auto-compute venue_cut, organizer_cut, and tenant_net (3-Way Split)
-- =============================================================================

CREATE OR REPLACE FUNCTION compute_item_cuts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Backwards compatibility: If legacy caller only provided share_percent
    IF (NEW.venue_share_percent IS NULL OR NEW.venue_share_percent = 0) 
       AND (NEW.organizer_share_percent IS NULL OR NEW.organizer_share_percent = 0)
       AND (NEW.share_percent IS NOT NULL AND NEW.share_percent > 0) THEN
        NEW.venue_share_percent     := NEW.share_percent;
        NEW.organizer_share_percent := 0.0;
    END IF;

    NEW.venue_cut     := ROUND(NEW.gross_amount * (COALESCE(NEW.venue_share_percent, 0) / 100.0), 0);
    NEW.organizer_cut := ROUND(NEW.gross_amount * (COALESCE(NEW.organizer_share_percent, 0) / 100.0), 0);
    NEW.share_percent := COALESCE(NEW.venue_share_percent, 0) + COALESCE(NEW.organizer_share_percent, 0);
    NEW.tenant_net    := NEW.gross_amount - NEW.venue_cut - NEW.organizer_cut;

    RETURN NEW;
END;
$$;

-- Drop old trigger if exists, then recreate (idempotent)
DROP TRIGGER IF EXISTS trg_compute_item_cuts ON transaction_items;

CREATE TRIGGER trg_compute_item_cuts
    BEFORE INSERT OR UPDATE ON transaction_items
    FOR EACH ROW
    EXECUTE FUNCTION compute_item_cuts();


-- =============================================================================
-- TRIGGER: Sequential Collision-Free Receipt Code (<PREFIX>-0001)
-- =============================================================================
-- Locks/counts existing transactions for NEW.event_id using pg_advisory_xact_lock
-- and assigns a sequential, collision-free code formatted as <PREFIX>-0001.
-- Prefix is derived from the first 3 alphanumeric uppercase characters of events.name
-- (defaulting to 'POS'), overriding any empty, null, or 'AUTO' client placeholder.
-- =============================================================================

CREATE OR REPLACE FUNCTION generate_receipt_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_name text;
    v_prefix     text;
    v_seq        integer;
BEGIN
    -- Only generate if NEW.receipt_code is NULL, empty, or 'AUTO'
    IF NEW.receipt_code IS NULL OR TRIM(NEW.receipt_code) = '' OR UPPER(TRIM(NEW.receipt_code)) = 'AUTO' THEN
        -- Concurrency-safe advisory transaction lock per event
        IF NEW.event_id IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext(NEW.event_id::text));
            SELECT name INTO v_event_name FROM events WHERE id = NEW.event_id;
        END IF;

        -- Extract prefix (first 3 alphanumeric uppercase chars), fallback to 'POS'
        IF v_event_name IS NOT NULL THEN
            v_prefix := UPPER(REGEXP_REPLACE(v_event_name, '[^a-zA-Z0-9]', '', 'g'));
            IF LENGTH(v_prefix) >= 3 THEN
                v_prefix := SUBSTRING(v_prefix FROM 1 FOR 3);
            ELSIF LENGTH(v_prefix) > 0 THEN
                v_prefix := RPAD(v_prefix, 3, 'X');
            ELSE
                v_prefix := 'POS';
            END IF;
        ELSE
            v_prefix := 'POS';
        END IF;

        -- Count existing transactions for this event + 1
        SELECT COALESCE(COUNT(*), 0) + 1
        INTO v_seq
        FROM transactions
        WHERE event_id = NEW.event_id;

        NEW.receipt_code := v_prefix || '-' || LPAD(v_seq::text, 4, '0');
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generate_receipt_code ON transactions;
CREATE TRIGGER trg_generate_receipt_code
    BEFORE INSERT ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION generate_receipt_code();


-- =============================================================================
-- ROW LEVEL SECURITY (Strict Lockdown: Authenticated CRUD only, Anon via RPC)
-- =============================================================================

ALTER TABLE master_tenants    ENABLE ROW LEVEL SECURITY;
ALTER TABLE events            ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants           ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_items ENABLE ROW LEVEL SECURITY;

-- 1. Drop all permissive anon policies (zero direct table access for anon)
DROP POLICY IF EXISTS anon_all_master_tenants ON master_tenants;
DROP POLICY IF EXISTS anon_all_events ON events;
DROP POLICY IF EXISTS anon_all_tenants ON tenants;
DROP POLICY IF EXISTS anon_all_transactions ON transactions;
DROP POLICY IF EXISTS anon_all_transaction_items ON transaction_items;

-- 2. Grant full CRUD exclusively to authenticated users (Staff / Admin)
DROP POLICY IF EXISTS authenticated_all_master_tenants ON master_tenants;
CREATE POLICY authenticated_all_master_tenants ON master_tenants
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS authenticated_all_events ON events;
CREATE POLICY authenticated_all_events ON events
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS authenticated_all_tenants ON tenants;
CREATE POLICY authenticated_all_tenants ON tenants
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS authenticated_all_transactions ON transactions;
CREATE POLICY authenticated_all_transactions ON transactions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS authenticated_all_transaction_items ON transaction_items;
CREATE POLICY authenticated_all_transaction_items ON transaction_items
  FOR ALL TO authenticated USING (true) WITH CHECK (true);


-- =============================================================================
-- REALTIME PUBLICATION
-- =============================================================================

-- Create publication if it doesn't exist yet (Supabase usually pre-creates it)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- Add tables to the publication (idempotent — safe if already added)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'master_tenants'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE master_tenants;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE transactions;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'transaction_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE transaction_items;
  END IF;
END $$;


-- =============================================================================
-- TOKEN-SCOPED RPC: get_tenant_portal_by_token (SECURITY DEFINER)
-- =============================================================================
-- Safely provides tenant portal access to anon without granting table access.
-- Returns ONLY the single tenant matching p_token, its parent event, its items,
-- and aggregated totals. Never exposes other tenants.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_tenant_portal_by_token(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant      record;
    v_event       record;
    v_tenant_json jsonb;
    v_event_json  jsonb;
    v_items_json  jsonb;
    v_totals_json jsonb;
BEGIN
    -- Look up tenant by access_token
    SELECT
        t.id,
        t.event_id,
        t.name,
        t.category,
        t.booth_number,
        COALESCE(t.share_percent, 10.0) AS share_percent,
        COALESCE(t.venue_share_percent, 10.0) AS venue_share_percent,
        COALESCE(t.organizer_share_percent, 0.0) AS organizer_share_percent,
        t.bank_info,
        t.payout_status,
        t.access_token,
        t.created_at
    INTO v_tenant
    FROM tenants t
    WHERE t.access_token = p_token;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Tenant not found');
    END IF;

    -- Look up parent event
    SELECT
        e.id,
        e.name,
        e.venue,
        e.event_dates,
        e.is_active,
        e.created_at
    INTO v_event
    FROM events e
    WHERE e.id = v_tenant.event_id;

    -- Build tenant profile JSON
    v_tenant_json := jsonb_build_object(
        'id',                      v_tenant.id,
        'event_id',                v_tenant.event_id,
        'name',                    v_tenant.name,
        'category',                v_tenant.category,
        'booth_number',            v_tenant.booth_number,
        'share_percent',           v_tenant.share_percent,
        'venue_share_percent',     v_tenant.venue_share_percent,
        'venue_share_pct',         v_tenant.venue_share_percent,
        'organizer_share_percent', v_tenant.organizer_share_percent,
        'eo_share_pct',            v_tenant.organizer_share_percent,
        'bank_info',               v_tenant.bank_info,
        'payout_status',           v_tenant.payout_status,
        'portal_token',            v_tenant.access_token,
        'created_at',              v_tenant.created_at
    );

    -- Build event profile JSON
    v_event_json := jsonb_build_object(
        'id',          v_event.id,
        'name',        v_event.name,
        'venue',       v_event.venue,
        'event_dates', v_event.event_dates,
        'status',      CASE WHEN v_event.is_active THEN 'ACTIVE' ELSE 'INACTIVE' END,
        'is_active',   COALESCE(v_event.is_active, true),
        'created_at',  v_event.created_at
    );

    -- Build items array enriched with transaction metadata, cuts and audit details
    SELECT COALESCE(jsonb_agg(to_jsonb(item_row)), '[]'::jsonb)
    INTO v_items_json
    FROM (
        SELECT
            ti.id,
            ti.item_note,
            ti.gross_amount,
            COALESCE(ti.share_percent, 0) AS share_percent,
            COALESCE(ti.venue_share_percent, 0) AS venue_share_percent,
            COALESCE(ti.organizer_share_percent, 0) AS organizer_share_percent,
            COALESCE(ti.venue_cut, 0) AS venue_cut,
            COALESCE(ti.organizer_cut, 0) AS organizer_cut,
            (COALESCE(ti.venue_cut, 0) + COALESCE(ti.organizer_cut, 0)) AS total_combined_cut,
            ti.tenant_net,
            ti.created_at,
            t.receipt_code,
            t.payment_method,
            t.created_at  AS transaction_created_at,
            t.status       AS transaction_status,
            t.void_reason,
            t.voided_at
        FROM transaction_items ti
        JOIN transactions t ON t.id = ti.transaction_id
        WHERE ti.tenant_id = v_tenant.id
        ORDER BY t.created_at DESC
    ) item_row;

    -- Build totals for completed transactions only
    SELECT jsonb_build_object(
        'total_gross',          COALESCE(SUM(ti.gross_amount), 0),
        'total_venue_cut',      COALESCE(SUM(ti.venue_cut), 0),
        'total_organizer_cut',  COALESCE(SUM(ti.organizer_cut), 0),
        'total_combined_cut',   COALESCE(SUM(COALESCE(ti.venue_cut, 0) + COALESCE(ti.organizer_cut, 0)), 0),
        'total_net',            COALESCE(SUM(ti.tenant_net), 0)
    )
    INTO v_totals_json
    FROM transaction_items ti
    JOIN transactions t ON t.id = ti.transaction_id
    WHERE ti.tenant_id = v_tenant.id
      AND t.status = 'COMPLETED';

    RETURN jsonb_build_object(
        'tenant', v_tenant_json,
        'event',  v_event_json,
        'items',  v_items_json,
        'totals', v_totals_json
    );
END;
$$;

-- Grant EXECUTE permission to anon and authenticated
GRANT EXECUTE ON FUNCTION get_tenant_portal_by_token(uuid) TO anon, authenticated;

-- Backwards-compatible get_tenant_portal_data
CREATE OR REPLACE FUNCTION get_tenant_portal_data(p_token uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT get_tenant_portal_by_token(p_token)::json;
$$;

GRANT EXECUTE ON FUNCTION get_tenant_portal_data(uuid) TO anon, authenticated;


-- =============================================================================
-- IDEMPOTENT BACKFILL: Sync existing tenants into master_tenants
-- =============================================================================
-- Automatically copies any existing tenants rows that are not yet in
-- master_tenants (matched case-insensitively by LOWER(TRIM(name))),
-- carrying over name, category, and bank_info.
-- Then links all tenants with null master_tenant_id to their master record.
-- =============================================================================

DO $$
BEGIN
  -- 1. Insert distinct brands from tenants that do not exist yet in master_tenants
  INSERT INTO master_tenants (name, category, bank_info)
  SELECT DISTINCT ON (LOWER(TRIM(t.name)))
    TRIM(t.name) AS name,
    t.category,
    t.bank_info
  FROM tenants t
  WHERE NOT EXISTS (
    SELECT 1
    FROM master_tenants mt
    WHERE LOWER(TRIM(mt.name)) = LOWER(TRIM(t.name))
  )
  ORDER BY LOWER(TRIM(t.name)), t.created_at DESC;

  -- 2. Link any unlinked tenants to their corresponding master_tenants row
  UPDATE tenants t
  SET master_tenant_id = mt.id
  FROM master_tenants mt
  WHERE t.master_tenant_id IS NULL
    AND LOWER(TRIM(t.name)) = LOWER(TRIM(mt.name));
END $$;

