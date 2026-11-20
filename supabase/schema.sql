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
    is_active               boolean     DEFAULT true,
    created_at              timestamptz DEFAULT now()
);

-- Safe migration columns for existing databases
ALTER TABLE events ADD COLUMN IF NOT EXISTS venue_share_percent numeric DEFAULT 10.0;
ALTER TABLE events ADD COLUMN IF NOT EXISTS organizer_share_percent numeric DEFAULT 0.0;

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
    payment_method  text        CHECK (payment_method IN ('QRIS', 'CASH')),
    total_amount    numeric     DEFAULT 0,
    cash_tendered   numeric(12,2),
    change_amount   numeric(12,2),
    status          text        DEFAULT 'COMPLETED'
                                CHECK (status IN ('COMPLETED', 'VOIDED', 'VOID')),
    void_reason     text,
    created_at      timestamptz DEFAULT now()
);

-- Safe migration columns and constraints for existing transactions
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cash_tendered numeric(12,2);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS change_amount numeric(12,2);
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
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE master_tenants    ENABLE ROW LEVEL SECURITY;
ALTER TABLE events            ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants           ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_items ENABLE ROW LEVEL SECURITY;

-- master_tenants policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'master_tenants' AND policyname = 'anon_all_master_tenants'
  ) THEN
    CREATE POLICY anon_all_master_tenants ON master_tenants
      FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

-- events policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'events' AND policyname = 'anon_all_events'
  ) THEN
    CREATE POLICY anon_all_events ON events
      FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

-- tenants policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'tenants' AND policyname = 'anon_all_tenants'
  ) THEN
    CREATE POLICY anon_all_tenants ON tenants
      FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'tenants' AND policyname = 'authenticated_all_tenants'
  ) THEN
    CREATE POLICY authenticated_all_tenants ON tenants
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- transactions policies (allows DELETE for voided transaction cleanup)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transactions' AND policyname = 'anon_all_transactions'
  ) THEN
    CREATE POLICY anon_all_transactions ON transactions
      FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transactions' AND policyname = 'authenticated_all_transactions'
  ) THEN
    CREATE POLICY authenticated_all_transactions ON transactions
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- transaction_items policies (allows DELETE for voided item cleanup)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transaction_items' AND policyname = 'anon_all_transaction_items'
  ) THEN
    CREATE POLICY anon_all_transaction_items ON transaction_items
      FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transaction_items' AND policyname = 'authenticated_all_transaction_items'
  ) THEN
    CREATE POLICY authenticated_all_transaction_items ON transaction_items
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;


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
-- RPC FUNCTION: get_tenant_portal_data
-- =============================================================================
-- Returns a JSON object containing:
--   • tenant   — tenant profile (with venue_share_percent & organizer_share_percent)
--   • items    — array of transaction items enriched with 3-way split metadata
--   • totals   — aggregated financial summary (gross, venue cut, organizer cut, combined cut, net)
--
-- SECURITY DEFINER so it can bypass RLS while only ever returning data
-- for the single tenant identified by the provided token.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_tenant_portal_data(p_token uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tenant      record;
    v_tenant_json json;
    v_items_json  json;
    v_totals_json json;
BEGIN
    -- Look up tenant by access_token
    SELECT
        id,
        event_id,
        name,
        category,
        booth_number,
        share_percent,
        venue_share_percent,
        organizer_share_percent,
        bank_info,
        payout_status,
        created_at
    INTO v_tenant
    FROM tenants
    WHERE access_token = p_token;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Tenant not found');
    END IF;

    -- Build tenant profile JSON (access_token intentionally omitted)
    v_tenant_json := json_build_object(
        'id',                      v_tenant.id,
        'event_id',                v_tenant.event_id,
        'name',                    v_tenant.name,
        'category',                v_tenant.category,
        'booth_number',            v_tenant.booth_number,
        'share_percent',           COALESCE(v_tenant.share_percent, 10.0),
        'venue_share_percent',     COALESCE(v_tenant.venue_share_percent, 10.0),
        'organizer_share_percent', COALESCE(v_tenant.organizer_share_percent, 0.0),
        'bank_info',               v_tenant.bank_info,
        'payout_status',           v_tenant.payout_status,
        'created_at',              v_tenant.created_at
    );

    -- Build items array enriched with transaction metadata and 3-way split cuts
    SELECT json_agg(row_to_json(item_row))
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
            t.status       AS transaction_status
        FROM transaction_items ti
        JOIN transactions t ON t.id = ti.transaction_id
        WHERE ti.tenant_id = v_tenant.id
        ORDER BY t.created_at DESC
    ) item_row;

    -- Build totals including separate venue cut and organizer cut
    SELECT json_build_object(
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

    RETURN json_build_object(
        'tenant', v_tenant_json,
        'items',  COALESCE(v_items_json, '[]'::json),
        'totals', v_totals_json
    );
END;
$$;


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

