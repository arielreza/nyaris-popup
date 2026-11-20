# PopUpPOS — Developer Handoff & Context Document

> **Last updated:** November 2026  
> **Status:** ✅ Complete Initial App + Database Schema (All views and schema fully implemented, verified build).

---

## 1. Project Overview

**PopUpPOS** is a real-time Point-of-Sale web application designed for **pop-up market events**. It enables a single centralized cashier to ring up purchases across multiple tenant booths in one transaction, automatically splitting revenue between the market organizer and each tenant.

### Who it's for

| Role | Description |
|------|-------------|
| **Market Organizer** | Runs the event, manages tenants, collects the revenue-share cut, and settles payouts |
| **Cashier** | Operates the POS terminal at the event entrance or central desk |
| **Tenant** | Booth vendor who monitors their own live sales and revenue via a private portal link |

### Core Value Proposition

- **Centralized cashier** — one operator handles all payments; no per-booth payment hardware needed
- **Live 3-way revenue split** — automated real-time split between **Venue Share %**, **Organizer/EO Share %**, and **Tenant Net** (`gross_amount - venue_cut - organizer_cut`)
- **Tenant self-service portals** — each tenant gets a private, unguessable URL to view their real-time sales, venue cut, organizer cut, and net take-home total
- **Real-time everything** — all dashboards and portals update live via Supabase Realtime (WebSocket)
- **Scales to ~15–20 tenants** per event without infrastructure changes

---

## 2. Tech Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| Frontend framework | Vue 3 (Composition API, `<script setup>`) | `^3.4.0` | Reactive UI components and routing |
| Build tool | Vite | `^5.3.0` | Dev server, HMR, production bundling |
| Styling | Tailwind CSS 3 | `^3.4.0` | Utility-first CSS; dark theme throughout |
| Routing | vue-router 4 | `^4.3.0` | Client-side SPA routing |
| Icons | lucide-vue-next | `^0.400.0` | Consistent SVG icon set |
| Backend / BaaS | Supabase | — | PostgreSQL DB, Realtime, RLS, Edge Functions |
| Supabase client | @supabase/supabase-js | `^2.45.0` | JS client for DB queries, RPC, Realtime |
| CSS processing | PostCSS + Autoprefixer | `^8.4.0` / `^10.4.0` | Tailwind compilation and vendor prefixing |
| Vue Vite plugin | @vitejs/plugin-vue | `^5.0.0` | `.vue` SFC support in Vite |
| PDF Generation | jspdf & jspdf-autotable | `^4.2.1` / `^5.0.7` | Client-side settlement report and tenant payout slip PDF generation |

---

## 3. Project Structure

```
nyaris-popup/
├── supabase/
│   └── schema.sql              — Idempotent DB schema: tables, trigger, RLS policies,
│                                 Realtime publication, and RPC function
├── src/
│   ├── components/
│   │   └── DateRangePicker.vue — Hotel-style date range picker with continuous emerald highlight strip
│   ├── lib/
│   │   ├── supabase.js         — Supabase client singleton (reads env vars, throws if missing)
│   │   ├── useAuth.js          — Reactive auth state + Supabase login/logout session composable
│   │   ├── currency.js         — formatRupiah(amount) and generateReceiptCode()
│   │   ├── useEvents.js        — Vue composable: reactive events state + fetchEvents/createEvent
│   │   └── exportSettlementPdf.js — Client-side PDF generator (event settlement report & tenant slips via jsPDF)
│   ├── router/
│   │   └── index.js            — Vue Router configuration (/, /admin, /login, /tenant/:token) with auth guard
│   ├── views/
│   │   ├── LoginView.vue          — Route /login — Staff authentication page (IMPLEMENTED)
│   │   ├── CashierView.vue        — Route /   — Central cashier POS terminal (IMPLEMENTED)
│   │   ├── AdminDashboardView.vue — Route /admin — Organizer management & settlements (IMPLEMENTED)
│   │   └── TenantPortalView.vue   — Route /tenant/:token — Tenant's live revenue portal (IMPLEMENTED)
│   ├── App.vue                 — Root component: sets bg-slate-950 wrapper, initializes auth, renders <router-view>
│   ├── main.js                 — App bootstrap: creates Vue app, registers router, mounts to #app
│   └── style.css               — Global Tailwind directives + scrollbar styles + .rupiah utility
├── index.html                  — HTML entry point with #app mount point
├── package.json                — Dependencies and npm scripts (dev / build / preview)
├── vite.config.js              — Vite config: @vitejs/plugin-vue, @ alias → src/
├── tailwind.config.js          — Tailwind content paths + custom slate-950 color
├── postcss.config.js           — PostCSS config: tailwindcss + autoprefixer
├── .env.example                — Environment variable template
├── vercel.json                 — Vercel SPA rewrite rule configuration for Vue Router
└── CONTEXT.md                  — This file
```

### Key Alias

`@` resolves to `./src/` via the Vite config alias. Use it everywhere:
```js
import { supabase } from '@/lib/supabase.js'
import { formatRupiah } from '@/lib/currency.js'
```

---

## 4. Database Schema

All tables live in the `public` schema. The schema is idempotent — safe to run multiple times via `CREATE TABLE IF NOT EXISTS` and `DO $$ BEGIN ... END $$` blocks.

### `events`

The top-level entity for each pop-up market event.

| Column | Type | Constraint | Description |
|--------|------|-----------|-------------|
| `id` | `uuid` | PK, `DEFAULT gen_random_uuid()` | Unique event identifier |
| `name` | `text` | `NOT NULL` | Display name of the event |
| `venue` | `text` | — | Venue name or address |
| `event_dates` | `text` | — | Formatted date range string (e.g. "18–20 Nov 2026") |
| `default_share_percent` | `numeric` | `DEFAULT 10.0` | Legacy/combined default share % (`venue_share_percent + organizer_share_percent`) |
| `venue_share_percent` | `numeric` | `DEFAULT 10.0` | Default venue location revenue share % for this event |
| `organizer_share_percent` | `numeric` | `DEFAULT 0.0` | Default event organizer/EO revenue share % for this event |
| `status` | `text` | `NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED'))` | Operational lifecycle status of the event |
| `is_active` | `boolean` | `DEFAULT true` | Backward-compatible boolean mirroring `status === 'ACTIVE'` |
| `created_at` | `timestamptz` | `DEFAULT now()` | Row creation timestamp |

---

### `master_tenants`

The centralized master directory of vendor brands across all events. Organizers can register brands independently and reuse them across multiple event lineups.

| Column | Type | Constraint | Description |
|--------|------|-----------|-------------|
| `id` | `uuid` | PK, `DEFAULT gen_random_uuid()` | Unique master brand identifier |
| `name` | `text` | `NOT NULL` | Brand / vendor business name |
| `category` | `text` | — | Primary business category |
| `instagram` | `text` | — | Instagram handle (e.g. `kopituku` or `@kopituku`) |
| `pic_name` | `text` | — | Person-in-charge / contact person name |
| `whatsapp` | `text` | — | WhatsApp phone number |
| `bank_name` | `text` | — | Bank institution name (e.g. `BCA`, `Mandiri`, `BRI`) |
| `bank_account` | `text` | — | Bank account number (e.g. `0118492031`) |
| `bank_holder` | `text` | — | Bank account holder name (e.g. `Nadia Kusuma Putri`) |
| `contact_info` | `text` | — | Auto-composed or legacy contact details |
| `bank_info` | `text` | — | Auto-composed or legacy payout bank account details |
| `created_at` | `timestamptz` | `DEFAULT now()` | Row creation timestamp |

---

### `tenants`

Each booth vendor participating in a specific event lineup. Links back to `master_tenants` when assigned or synced.

| Column | Type | Constraint | Description |
|--------|------|-----------|-------------|
| `id` | `uuid` | PK, `DEFAULT gen_random_uuid()` | Unique tenant identifier |
| `event_id` | `uuid` | `NOT NULL REFERENCES events(id) ON DELETE CASCADE` | Parent event |
| `master_tenant_id` | `uuid` | `NULLABLE REFERENCES master_tenants(id) ON DELETE SET NULL` | Linked brand profile from master directory |
| `name` | `text` | `NOT NULL` | Tenant/brand name |
| `category` | `text` | — | Business category (e.g. "Food & Beverage", "Fashion & Apparel") |
| `booth_number` | `text` | — | Booth label (e.g. "A-12") |
| `share_percent` | `numeric` | `DEFAULT 10.0` | Combined cut % (`venue_share_percent + organizer_share_percent`) |
| `venue_share_percent` | `numeric` | `DEFAULT 10.0` | Per-tenant venue location cut % |
| `organizer_share_percent` | `numeric` | `DEFAULT 0.0` | Per-tenant event organizer/EO cut % |
| `access_token` | `uuid` | `UNIQUE DEFAULT gen_random_uuid()` | Secret URL token for the tenant portal |
| `bank_info` | `text` | — | Payout bank account info |
| `payout_status` | `text` | `DEFAULT 'PENDING' CHECK IN ('PENDING','SETTLED')` | Settlement state |
| `created_at` | `timestamptz` | `DEFAULT now()` | Row creation timestamp |

> [!NOTE]
> **Idempotent Backfill Block:** `supabase/schema.sql` includes an automated backfill script (`DO $$ ... $$`) that copies distinct existing `tenants` rows not yet in `master_tenants` (matched case-insensitively by `LOWER(TRIM(name))`) into `master_tenants` (carrying over `name`, `category`, and `bank_info`), and links `tenants.master_tenant_id` for complete historical continuity.

---

### `transactions`

A single cashier transaction (a "receipt"), which may contain items from multiple tenants.

| Column | Type | Constraint | Description |
|--------|------|-----------|-------------|
| `id` | `uuid` | PK, `DEFAULT gen_random_uuid()` | Unique transaction identifier |
| `event_id` | `uuid` | `REFERENCES events(id)` | The event this transaction belongs to |
| `receipt_code` | `text` | `UNIQUE` | Sequential receipt code (e.g. `NYR-0001`, `BZR-0042`) |
| `client_tx_id` | `uuid` | `UNIQUE (partial index)` | Client-generated idempotency UUID preventing duplicate checkout submissions |
| `payment_method` | `text` | `CHECK IN ('QRIS','CASH')` | How payment was made |
| `total_amount` | `numeric` | `DEFAULT 0` | Sum of all item `gross_amount`s |
| `cash_tendered` | `numeric(12,2)` | — | Cash received from customer (for CASH transactions) |
| `change_amount` | `numeric(12,2)` | — | Change returned to customer (for CASH transactions) |
| `status` | `text` | `DEFAULT 'COMPLETED' CHECK IN ('COMPLETED','VOIDED')` | Transaction state |
| `void_reason` | `text` | — | Required reason for supervisor-authorized void |
| `voided_at` | `timestamptz` | — | Timestamp when void authorization was executed |
| `created_at` | `timestamptz` | `DEFAULT now()` | Row creation timestamp |

### Trigger: `trg_generate_receipt_code`

Fires **BEFORE INSERT** on `transactions`. Generates an event-scoped, sequential, collision-free receipt code formatted as `<PREFIX>-0001` (e.g. `NYR-0001` derived from the first 3 alphanumeric characters of `events.name`):
- Uses `pg_advisory_xact_lock(hashtext(NEW.event_id::text))` to prevent race conditions during concurrent checkouts.
- Only fires when `NEW.receipt_code IS NULL` or `NEW.receipt_code = 'AUTO'`.

---

### `transaction_items`

One line item per tenant within a transaction. 3-way revenue split is **auto-computed by a trigger**.

| Column | Type | Constraint | Description |
|--------|------|-----------|-------------|
| `id` | `uuid` | PK, `DEFAULT gen_random_uuid()` | Unique item identifier |
| `transaction_id` | `uuid` | `NOT NULL REFERENCES transactions(id) ON DELETE CASCADE` | Parent transaction |
| `tenant_id` | `uuid` | `REFERENCES tenants(id)` | Which tenant this item belongs to |
| `item_note` | `text` | — | Optional description of what was sold |
| `gross_amount` | `numeric` | `NOT NULL` | Total sale amount for this item (before split) |
| `share_percent` | `numeric` | `NOT NULL` | Combined cut % snapshot |
| `venue_share_percent` | `numeric` | `DEFAULT 0` | Venue location cut % snapshot |
| `organizer_share_percent` | `numeric` | `DEFAULT 0` | Organizer/EO cut % snapshot |
| `venue_cut` | `numeric` | `DEFAULT 0` | **Auto-computed by trigger** — venue cut in Rupiah |
| `organizer_cut` | `numeric` | `DEFAULT 0` | **Auto-computed by trigger** — organizer/EO cut in Rupiah |
| `tenant_net` | `numeric` | — | **Auto-computed by trigger** — tenant take-home (`gross - venue_cut - organizer_cut`) |
| `created_at` | `timestamptz` | `DEFAULT now()` | Row creation timestamp |

### Trigger: `trg_compute_item_cuts`

Fires **BEFORE INSERT OR UPDATE** on `transaction_items`. Automatically calculates 3-way splits (`venue_cut`, `organizer_cut`, and `tenant_net`) while preserving backward compatibility with legacy callers:

```sql
CREATE OR REPLACE FUNCTION compute_item_cuts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_has_split boolean;
BEGIN
    v_has_split := (NEW.venue_share_percent IS NOT NULL AND NEW.venue_share_percent > 0)
                OR (NEW.organizer_share_percent IS NOT NULL AND NEW.organizer_share_percent > 0);

    IF v_has_split THEN
        NEW.venue_cut     := ROUND(NEW.gross_amount * (COALESCE(NEW.venue_share_percent, 0) / 100.0), 0);
        NEW.organizer_cut := ROUND(NEW.gross_amount * (COALESCE(NEW.organizer_share_percent, 0) / 100.0), 0);
        NEW.tenant_net    := NEW.gross_amount - NEW.venue_cut - NEW.organizer_cut;
        NEW.share_percent := COALESCE(NEW.venue_share_percent, 0) + COALESCE(NEW.organizer_share_percent, 0);
    ELSE
        NEW.venue_cut     := 0;
        NEW.organizer_cut := ROUND(NEW.gross_amount * (COALESCE(NEW.share_percent, 0) / 100.0), 0);
        NEW.tenant_net    := NEW.gross_amount - NEW.organizer_cut;
    END IF;

    RETURN NEW;
END;
$$;
```

> [!IMPORTANT]
> Pass `gross_amount`, `venue_share_percent`, and `organizer_share_percent` when inserting a `transaction_item`. Never set `venue_cut`, `organizer_cut`, or `tenant_net` manually — the trigger computes and overwrites them.

---

## 5. Row Level Security (RLS) & Production Hardening

Row Level Security is **enabled** on all tables. Production security hardening is strictly enforced:
- Permissive `anon` direct table policies have been **completely dropped**. The public `anon` role has **zero** direct table read/write permissions.
- Staff operations (Cashier and Admin) authenticate via Supabase Auth and execute queries under the `authenticated` role.
- The Tenant Portal accesses data without login via a locked-down, token-scoped `SECURITY DEFINER` RPC function (`get_tenant_portal_by_token`).

### Current Policies (Production)

| Table | Policy Name | Role | Operations | Condition |
|-------|------------|------|-----------|----------|
| `master_tenants` | `authenticated_all_master_tenants` | `authenticated` | ALL | `USING (true) WITH CHECK (true)` |
| `events` | `authenticated_all_events` | `authenticated` | ALL | `USING (true) WITH CHECK (true)` |
| `tenants` | `authenticated_all_tenants` | `authenticated` | ALL | `USING (true) WITH CHECK (true)` |
| `transactions` | `authenticated_all_transactions` | `authenticated` | ALL | `USING (true) WITH CHECK (true)` |
| `transaction_items` | `authenticated_all_transaction_items` | `authenticated` | ALL | `USING (true) WITH CHECK (true)` |

> [!NOTE]
> All raw database tables are shielded from unauthenticated access. Vendor transparency is preserved by routing vendor queries through `get_tenant_portal_by_token(uuid)` which only returns data matching the secret access token.

---

## 6. RPC Functions

### `get_tenant_portal_by_token(p_token uuid)` (and `get_tenant_portal_data`)

The secure, token-scoped data endpoint for the Tenant Portal (`/tenant/:token`). Because it is declared as `SECURITY DEFINER`, it executes with elevated database privileges while restricting returned data strictly to the single tenant matching `p_token`.

**Permissions:** `GRANT EXECUTE ON FUNCTION get_tenant_portal_by_token(uuid) TO anon, authenticated;`

**Input:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `p_token` | `uuid` | The tenant's secret `access_token` from the `tenants` table |

**Output:** A single `jsonb` object with the following shape:

```json
{
  "tenant": {
    "id": "...",
    "event_id": "...",
    "name": "Booth Name",
    "category": "Food & Beverage",
    "booth_number": "A-12",
    "share_percent": 15.0,
    "venue_share_percent": 10.0,
    "organizer_share_percent": 5.0,
    "bank_info": "BCA 1234567890 a/n Budi",
    "payout_status": "PENDING",
    "created_at": "2026-11-17T..."
  },
  "items": [
    {
      "id": "...",
      "item_note": "Nasi Goreng x2",
      "gross_amount": 100000,
      "share_percent": 15,
      "venue_share_percent": 10,
      "organizer_share_percent": 5,
      "venue_cut": 10000,
      "organizer_cut": 5000,
      "total_combined_cut": 15000,
      "tenant_net": 85000,
      "created_at": "...",
      "receipt_code": "POS-8492",
      "payment_method": "QRIS",
      "transaction_created_at": "...",
      "transaction_status": "COMPLETED"
    }
  ],
  "totals": {
    "total_gross": 100000,
    "total_venue_cut": 10000,
    "total_organizer_cut": 5000,
    "total_combined_cut": 15000,
    "total_net": 85000
  }
}
```

**Error case:** If `p_token` doesn't match any tenant, returns:
```json
{ "error": "Tenant not found" }
```

**Notes:**
- `access_token` is **intentionally omitted** from the `tenant` object in the response
- `totals` aggregates only `COMPLETED` transactions (voided transactions are excluded)
- `items` returns both COMPLETED and VOIDED items; the portal filters client-side via `completedItems` computed property
- Items are ordered by `transaction.created_at DESC` (newest first)

**Usage in Vue:**
```js
const { data, error } = await supabase.rpc('get_tenant_portal_data', { p_token: token })
if (error || !data?.tenant) { /* handle error */ }
const { tenant, items, totals } = data
```

---

## 7. Routes & Views

Routes are defined in `src/router/index.js` using `createWebHistory()` (HTML5 history mode) with a global `beforeEach` navigation guard:

| Route | View | Access | Purpose |
|-------|------|--------|---------|
| `/login` | `LoginView.vue` | Public | Staff & Admin authentication page via Supabase Auth |
| `/` | `CashierView.vue` | Protected (Staff Auth) | Central POS cashier terminal |
| `/admin` | `AdminDashboardView.vue` | Protected (Staff Auth + PIN Gate) | Organizer management, settlements, PDF exports, Master Tenant directory |
| `/tenant/:token` | `TenantPortalView.vue` | Public (Token-Gated RPC) | Tenant live revenue and sales feed portal |

### `LoginView.vue` — `/login`

**Status:** ✅ **Fully implemented.**

**Features:**
- Secure staff login portal authenticating against Supabase Auth (`signInWithPassword`).
- Sleek dark-slate card with email and password inputs, show/hide password toggle, and real-time validation error alerts.
- Smart post-login redirection returning the user to their originally intended path (e.g. `/` or `/admin`).

---

### `CashierView.vue` — `/`

**Status:** ✅ **Fully implemented.**

**Features:**
- **Responsive 2-Column Split-View Layout on Desktop/Tablet (`lg:`)**:
  - Main POS workspace widens dynamically to `max-w-6xl mx-auto` with a 12-column responsive layout:
    - **Left Column (`lg:col-span-7`):** Houses the Quick Search bar, horizontal scrollable Category Pills, and Tenant Grid (`grid-cols-2 sm:grid-cols-3 gap-3`), maximizing visible booths without excessive vertical scrolling.
    - **Right Column (`lg:col-span-5 lg:sticky lg:top-20`):** Pins the **Cart (Keranjang)** card (with scrollable item list) and **Payment (Pembayaran + Proses Pembayaran)** card in sticky view so the checkout button remains visible and reachable at all times even with multiple items in the cart.
    - **Mobile View (`< 1024px`):** Clean single-column stacked layout with generous bottom padding (`pb-32`) ensuring the fixed bottom drawer never obscures checkout controls.
- **Active Event Auto-Selection & Filtering**:
  - Automatically queries and filters `events` to only display active events (`status === 'ACTIVE'` or `is_active !== false`), completely hiding completed/archived events from the cashier UI.
  - Zero-click readiness: auto-selects the first active event on load and invokes `onEventChange()` to load tenants immediately without cashier manual interaction.
  - Clear empty state when 0 active events exist: displays `"Tidak ada event aktif saat ini. Aktifkan event di menu Admin."` with direct CTA button navigating to `/admin`.
- Top Bar: PopUpPOS logo, Event selector dropdown, Admin navigation shortcut (`/admin`), and Staff Logout button (`handleLogout`), aligned with `max-w-6xl` on desktop.
- **Tenant Grid with Quick Search & Category Filtering**:
  - High-contrast search input (`tenantSearchQuery`) matching brand name, booth number, or category with a 1-click clear (`×`) button.
  - Dynamic horizontal scrollable category filter pills (`Semua`, plus distinct categories extracted from active event's lineup) rendered whenever $\ge 2$ distinct categories exist.
  - Live tenant count badge (`filteredTenants.length / tenants.length`).
  - Search empty state card (`"Tidak ada tenant yang cocok dengan pencarian."`) with a 1-click `"Reset Filter"` button.
  - Auto-resets search query and category filter whenever `selectedEventId` changes.
  - Tenant quick-tap grid with booth number badge, tenant name, and category.
- **Enhanced Amount Input Modal**:
  - Live 3-Way Split preview badge in modal header (`Venue X% • EO Y% • Tenant Z%`)
  - Live thousand-separator formatting as the cashier types (e.g. `100.000`), stripping non-digits to keep clean integer values
  - Mobile-optimized numeric keyboard (`inputmode="numeric"`) with no browser number spinner arrows
  - Quick-add chip buttons: `+10.000`, `+25.000`, `+50.000`, `+100.000`, and `Clear` for rapid one-tap entry
  - Optional item note field
- Multi-tenant cart allowing one customer checkout spanning items from multiple booths
- Payment method toggle: QRIS (blue) / CASH (green)
- **Cash Tendered & Change Calculator (When CASH is active)**:
  - Header with `"Uang Diterima (Cash Tendered)"` and clickable `"Uang Pas"` button (sets `cashTendered = cartTotal`).
  - Auto-formatted IDR input (`Rp 200.000`) with quick clear `X` button.
  - Quick denomination chips (`+50k`, `+100k`, `+200k`, `+500k`) that add cash received in one tap.
  - Live **Kembalian** calculation row:
    - Displays exact change in bold emerald (`formatRupiah(cashChange)`) when tendered $\ge$ cart total.
    - If `cashTendered` is empty or 0, defaults seamlessly to exact cash (`cartTotal`), showing `Kembalian: Rp 0 (Uang Pas)`.
    - If `0 < cashTendered < cartTotal`, shows an amber/rose warning `"Kurang Rp ..."` and blocks the checkout button (`isCashInsufficient`).
- **Sequential Receipt Numbering Trigger**:
  - Cashier UI displays `"AUTO (#)"` indicating sequential numbering handled automatically by the server.
  - On checkout, passes `receipt_code: 'AUTO'`; PostgreSQL trigger `generate_receipt_code()` locks the event (`pg_advisory_xact_lock`) and generates a collision-free sequential code (e.g. `NYR-0001`).
- **Double-Submit & Unstable-Network Resilience**:
  - **Synchronous In-Flight Lock:** Non-reactive lock `checkoutInFlight = true` immediately blocks double taps or Enter-key repeats before any async promise executes.
  - **Idempotency Key (`client_tx_id`):** Generates a client UUID per checkout attempt and stores it with a unique constraint in the database.
  - **Duplicate Recovery Handling:** If Supabase throws a unique constraint error (`23505`), automatically recovers the existing transaction by `client_tx_id`, checks item integrity, displays the digital receipt, and clears the cart safely.
  - **Cart Safety & Network Alert:** If connection drops before header creation, cart contents are strictly preserved, error toast alerts cashier to retry (`"Koneksi terganggu. Transaksi belum tersimpan, silakan coba lagi."`), and locks are released in `finally`.
- Transaction processing: inserts to `transactions` with `cash_tendered` and `change_amount`, batch inserts `transaction_items` with `venue_share_percent` and `organizer_share_percent` (trigger automatically calculates `venue_cut`, `organizer_cut`, and `tenant_net`).
- **Digital Receipt Modal**:
  - Automatically pops up upon successful payment or when clicking on any receipt code in Recent Transactions.
  - Paper receipt styling with event title, receipt code, timestamp, payment method badge, itemized breakdown (tenant, booth, notes, gross amounts), total amount, and exact cash tendered / change if paid in CASH.
  - **"Copy Text"** action button that copies a neatly formatted POS text receipt to clipboard for easy WhatsApp sending or thermal printing.
- **Recent Transactions Drawer with Receipt Search & Status Filter**:
  - Live Supabase Realtime subscription (listening to both `transactions` and `transaction_items`), displaying expanded item breakdowns, cash tendered/change badges, and direct click-to-view digital receipt buttons.
  - Sticky search input (`txSearchQuery`) with 1-click clear (`×`) button matching receipt codes, void reasons, or vendor names and item notes.
  - 3-state status filter pills (`Semua`, `Completed`, `Void`) with instant reactive filtering.
  - Dynamic count badge in toggle button (`filtered / total`) and clean search empty state with 1-click filter reset.
  - Widescreen container width (`max-w-4xl`) on tablet/desktop.
- **Protected Supervisor Void Authorization Modal**:
  - Requires entering the 6-digit Supervisor/Admin PIN (`VITE_ADMIN_PIN`) and a mandatory void reason.
  - Features an on-screen 3x4 touch-friendly keypad with `touch-manipulation select-none` for rapid entry on mobile/tablet devices.
  - Updates `transactions.status = 'VOIDED'`, `transactions.void_reason`, and `transactions.voided_at`.
- **Mobile Responsiveness Polish & Touch Optimization (< 640px / iPhone 15 390px Viewport)**:
  - Global viewport lock (`maximum-scale=1.0, user-scalable=no, viewport-fit=cover`) and `touch-action: manipulation;` on interactive elements to prevent accidental double-tap zoom delays on iOS Safari/Chrome.
  - `touch-manipulation select-none` applied to all PIN keypad buttons (Admin lock & supervisor void) and quick cash chips.
  - Header bar: truncated event selector (`max-w-[125px] xs:max-w-[150px] sm:max-w-[180px]`), compact Admin navigation and logout buttons, non-wrapping brand title.
  - Generous bottom clearance (`pb-36 sm:pb-28 lg:pb-12`) ensuring checkout button and cart actions never collide with the drawer toggle.
  - iOS home indicator safety via `style="padding-bottom: env(safe-area-inset-bottom, 0px);"` on fixed bottom drawer toggle.

---

### `AdminDashboardView.vue` — `/admin`

**Status:** ✅ **Fully implemented.**

**Features:**
- **Two-Tier Authentication & PIN Gate**:
  - Protected at route level by Supabase Auth (staff login).
  - Secondary 6-digit PIN Lock Gate (`VITE_ADMIN_PIN`, default `'000000'`) for operational security on shared cashier devices.
  - Header includes dedicated `"Kunci"` and `"Keluar"` (Logout) buttons, plus a logout button directly on the PIN lock screen.
- **Mobile Responsiveness & Touch Optimization (< 768px / Mobile Viewport)**:
  - Header: non-wrapping `PopUpPOS Admin` title, compact right-side buttons with responsive labels (`Kasir` on mobile vs `Cashier View` on desktop; icon-only with `aria-label` for `Kunci` and `Keluar` on mobile).
  - Tab Bar: horizontal scrollable with `no-scrollbar`, `shrink-0`, and `touch-pan-x overscroll-x-contain` to eliminate scroll hijacking on iOS Safari. Dedicated `switchAdminTab(tabKey, event)` handler smoothly auto-centers the active tab pill (`scrollIntoView({ inline: 'center' })`) and triggers an instant coordinate reset to `(0, 0)` after DOM render (`await nextTick() + requestAnimationFrame`) to prevent iOS Safari smooth-scrolling collisions and stalls during dynamic layout reflows.
  - KPI Summary Cards: 2-column mobile layout where Gross Revenue and Tenant Net Payout span full rows while Venue/EO cuts sit side-by-side; duplicate compact payment breakdown mini-strip is hidden on mobile (`hidden sm:block`) in favor of the full reconciliation card.
  - **Stacked Mobile Cards (`md:hidden`) for All 3 Tables**:
    - **Settlement & Payout:** Clean touch cards with Booth #, tenant name, category, payout status toggle pill, 2x2 financial metric grid (Gross, Net, Venue Cut, Org Cut), full-width action buttons (PDF, Salin WA), and compact Totals summary card.
    - **Tenant Management:** Cards displaying Booth #, name, category, clear revenue split string, and direct action row (Undangan WA, Buka WA, Portal link, Edit, Delete) without horizontal scroll.
    - **Master Tenant Directory:** Cards with Brand Name, category badge, Instagram link, PIC & clickable WhatsApp chat link, bank details, active event registration badge, and 1-tap Assign/Edit/Delete buttons.
  - Tables on Desktop/Tablet: preserved completely intact via `hidden md:block`.
  - Modals Safe-Area: bottom padding (`pb-24 sm:pb-6`) inside scroll containers ensures submit buttons stay clear of the floating iOS bottom navigation bar.
- **3-Tab Admin Workspace Architecture**:
  - Replaces long, cluttered single-page scrolling with a sticky, focused horizontal tab navigation bar:
    1. **`Overview & Settlement` (Default)**:
       - Compact Active Event selector bar with live status, dates badge, venue info, and quick switch to event settings.
       - **5 Live Revenue Summary Cards**: Total Gross (White), Venue Cut (Violet), Organizer Cut (Amber), Tenant Net Payout (Emerald), and QRIS vs Cash breakdown (Sky).
       - **Rekonsiliasi Metode Pembayaran (End-of-Day)**:
         - A dedicated high-clarity reconciliation card right below the KPI cards comparing digital payments vs physical cash drawer:
           - **QRIS Settlement**: Total Rupiah, transaction count badge, and revenue share percentage.
           - **CASH (Laci Kasir)**: Total net cash, transaction count badge, revenue share percentage, and a breakdown line showing total cash received from buyers (`Diterima: Rp ...`) vs change returned (`Kembalian: -Rp ...`).
           - **Visual Split Bar**: Full-width progress bar showing the proportional breakdown between QRIS (sky) and CASH (emerald).
       - **Per-Tenant Settlement & Payout Table**: Booth #, Tenant Name, Category, Gross Sales, Venue Cut, Organizer Cut, Net Payout, and toggleable payout status (`PENDING` / `SETTLED`).
       - **Professional PDF Settlement Generators (`jspdf` & `jspdf-autotable`)**:
         - **`Export All PDF` (`generateEventSettlementPdf`)**: Generates an A4 internal event settlement document featuring official header, event metadata box with default split (`Skema Bagi Hasil: Venue X% • EO Y%`), 4-card financial summary grid (Gross Sales, Venue Cut, EO Cut, Tenant Net, plus QRIS vs Cash breakdown), and a full settlement table with default percentages embedded in column headers (`Venue Cut (X%)` and `EO Cut (Y%)`), clean rupiah figures in cells (only appending `(Z%)` if overridden), single-line status column (`PENDING` / `SETTLED`), bold summary footer (`TOTAL KESELURUHAN`), and page numbering.
         - **Per-Row `PDF` Slip (`generateTenantSettlementPdf`)**: Produces an individual vendor settlement slip with clean bank account alignment, a single unified `Potongan Bagi Hasil (X%)` line (strictly hiding internal Venue vs EO split from tenants), prominent Net Payout highlight card, and a chronological audit log table of all non-voided transaction items for that tenant.
         - **One-Click WhatsApp Settlement Summary (`copyTenantWaSummary`)**: A per-tenant "WA" action button copying a cleanly formatted WhatsApp recap message to clipboard with instant toast notification, detailing gross sales, combined share % & deduction amount, net payout, destination bank info, payout status, and tenant portal link—strictly hiding internal Venue vs EO splits.
    2. **`Event & Lineup`**:
       - **Event Management & Lifecycle Status**:
         - Event selector with status tags (`[ACTIVE]` / `[COMPLETED]`), active status badge (emerald `ACTIVE` / amber `COMPLETED`), and active event metadata badges in both Overview and Event Management tabs.
         - **1-Click Status Toggle Button**: `"Tandai Selesai"` (archives event from cashier) or `"Aktifkan Kembali"` (restores event to cashier) with instant Supabase update, reactive local state sync, and confirmation toast.
         - Collapsible Event Creator powered by `DateRangePicker.vue` with 3-way split inputs, creating events with `status: 'ACTIVE'` and `is_active: true`.
         - "Edit Event" panel with Status selector dropdown (`ACTIVE` / `COMPLETED`), date picker, 3-way split inputs, and bulk share sync checkbox (`"Terapkan default share % baru ke semua tenant di event ini"`).
       - **Event Lineup Section (Streamlined Workflow)**:
         - Eliminates redundant "Import Past" modal — `master_tenants` serves as the single source of truth for all brands across past and future events.
         - **Only 2 Clean Action Buttons**:
           1. **`+ Pilih dari Master`** (`openAssignLineupModal`): Lists all brands from `master_tenants` (enriched with their last joined event or `"Belum pernah ikut event"`), allowing the organizer to multi-select brands, assign booth numbers, and add them to the active event using the event's default share %.
           2. **`+ Tenant Baru`** (Quick-Add form toggle): Adds a vendor directly to the active event lineup AND automatically upserts/links it into `master_tenants` (filling in missing category/bank info if already present) so the master directory remains 100% synchronized.
         - Lineup table showing Booth #, Brand Name (with Master Brand indicator), Category, 3-way Share % split, Payout status badge.
         - Action buttons:
           - **`Edit`**: Edit tenant override modal (custom share % and category).
           - **`Undangan WA`**: 1-click copies a personalized Indonesian WhatsApp invitation message with tenant name, PIC name (if available from master record), event dates, booth number, direct portal link, and confidential sales tracking guidance.
           - **`Buka WA` (`wa.me`)**: Direct link button opening WhatsApp chat with the pre-filled invite message if a WhatsApp number is stored in the linked master record.
           - **`Portal`**: Copies raw tenant portal link (`/tenant/:token`) with "Copied!" feedback.
           - **`Delete`**: Safely removes tenant from lineup with active transaction guard and voided transaction auto-cleanup.
         - **Lineup Deletion Safety & Voided Transaction Cleanup**:
           - When attempting to remove a tenant from lineup, inspects all linked `transaction_items` joined with `transactions(id, status)`.
           - **Active transactions guard:** If any non-void transaction exists (`transactions.status !== 'VOID' && transactions.status !== 'VOIDED'`), deletion is blocked with clear Indonesian feedback: `"Tidak dapat menghapus tenant karena masih memiliki transaksi aktif di event ini (void transaksi terkait terlebih dahulu)."` displayed via both an inline warning banner and a toast.
           - **Voided transactions auto-cleanup:** If all linked transactions are `VOID` / `VOIDED` (0 active transactions):
             1. Deletes the voided `transaction_items` rows belonging to that `tenant_id`.
             2. Inspects parent `VOID` `transactions` and deletes any empty transaction header rows that now have 0 remaining items.
             3. Safely deletes the `tenants` row from `tenants` table without foreign-key constraint violations (`23503`).
             4. Updates local reactive state (`tenants`, `allTenantsList`, and transaction metrics) and emits a success toast (`"Tenant berhasil dihapus dari lineup."`).
    3. **`Master Tenant` Directory**:
       - Standalone central brand and vendor database (`master_tenants`) independent of any event.
       - **Enriched Brand Profile & Flexible Form (`newMasterTenant` & `editingMasterTenant`)**:
         - Only **Nama Brand \*** and **Kategori \*** are required; all other fields are strictly optional (`instagram`, `pic_name`, `whatsapp`, `bank_name`, `bank_account`, `bank_holder`).
         - Auto-composes `bank_info` (e.g. `"BCA 0118492031 a.n. Nadia Kusuma Putri"`) and `contact_info` while preserving manual inputs.
         - Automatically synchronizes updated `bank_info` to linked `tenants` rows in the active event lineup.
       - **Horizontal Category Filter Pills**:
         - Scrollable pill buttons displaying `All (N)` plus each category with dynamic item count badges (`masterCategoriesWithCounts`).
       - **Multi-Field Real-Time Search**: Matches across brand name, `@instagram`, PIC name, WhatsApp phone, bank name, account number, account holder, and legacy contact/bank info.
       - **Enhanced Master Brands Table**:
         - **Brand Name**: bold brand title + pink clickable `@instagram` link badge + last joined event label.
         - **Kategori**: category pill.
         - **PIC & Kontak**: PIC name + clickable emerald WhatsApp phone link.
         - **Bank / Rekening**: Bank institution + account number (font-mono) + `a.n. Bank Holder`.
         - **Status di Event Aktif**: `"Terdaftar (Booth X)"` or `"Belum di Event Ini"`.
         - **Actions**:
           - **Interactive "Assign to Event" Modal (`assigningMasterModal`)**:
             - Interactive `<select>` dropdown allowing organizers to assign any brand to ANY existing event (defaulting to the currently active event).
             - Real-time preview of the target event's default 3-way split (`Venue %`, `Organizer %`, `Tenant Net %`) and dates.
             - Cross-event duplicate detection (`isBrandAlreadyInTargetEvent` using `allTenantsList`): displays an amber warning badge (`"Brand ini sudah terdaftar di lineup event terpilih."`) and disables the submit button to prevent duplicate booth entries.
             - Booth number input and automatic revenue split initialization from the chosen target event.
             - Smooth event switching if assigned to an event other than the active event, automatically transitioning `selectedEventId`, fetching the target event's lineup, and showing a floating success toast.
           - Edit brand profile modal with clean 2-column grid.
           - Delete brand confirmation (preserves historical event transactions).
- Supabase Realtime subscription on `transaction_items` and `master_tenants` for instant synchronization across all tabs and cashier sessions.

---

### `TenantPortalView.vue` — `/tenant/:token`

**Status:** ✅ **Fully implemented.**

**Features:**
- Loads tenant data via `get_tenant_portal_data` RPC on mount
- Displays tenant header with name, booth number, category badge, payout status
- **Revenue-Share Visibility Rule (Combined Share Only)**:
  - Keeps the internal Venue vs Organizer/EO split strictly private to Admin.
  - **Summary Cards**:
    - **Gross Sales** (Total revenue kotor)
    - **Potongan Bagi Hasil (X%)** (single combined deduction amount; hides separate Venue vs EO breakdown)
    - **Your Take-Home** (prominent emerald card with net payout and take-home percentage pill)
    - **Bank Info** (rekening tujuan transfer dari penyelenggara)
- **Live Sales Feed**: scrollable list of completed items with receipt code, payment method badge (QRIS=sky, CASH=green), relative timestamp, and clean 3-part breakdown (`Gross`, `Potongan (X%)`, `Your Net`) without internal split details
- Realtime connection indicator (pulsing emerald dot = connected, grey = offline)
- Realtime subscription filtered to `tenant_id = eq.{id}` — only receives this tenant's new items
- Error state if token is invalid; loading state with spinner

---

## 8. Component Architecture

### Composables

#### `src/lib/useEvents.js`

A Vue 3 composable encapsulating all event-related state and async operations.

```js
const { events, activeEvent, setActiveEvent, fetchEvents, createEvent, updateEvent } = useEvents()
```

| Export | Type | Description |
|--------|------|-------------|
| `events` | `Ref<Array>` | Reactive list of all events, ordered newest first |
| `activeEvent` | `Ref<Object\|null>` | The event currently selected for POS operations |
| `setActiveEvent(event)` | Function | Sets `activeEvent.value` |
| `fetchEvents()` | `async Function` | Fetches all events from Supabase; populates `events` ref |
| `createEvent(payload)` | `async Function` | Inserts a new event; prepends to `events` ref; returns new row |
| `updateEvent(id, payload)` | `async Function` | Updates an existing event; synchronizes `events` and `activeEvent` refs |

> [!NOTE]
> `useEvents()` creates its own reactive state per call. For shared state across views, call it once in a parent and pass down, or lift to a Pinia store when the app grows.

---

### Components

#### `src/components/DateRangePicker.vue`

A hotel-booking-style date range picker tailored for pop-up market events:
- **Trigger button:** Input-style trigger showing a Calendar icon, formatted Indonesian date range (`"18–20 Nov 2026"`), and a duration badge (`"3 hari"`).
- **Popover calendar:** Clean dropdown with month/year navigation (`<` and `>`), Indonesian day-of-week headers (`Min`–`Sab`), and click-outside/Escape handling.
- **Hotel-style connected highlighting:**
  - 1st click sets start date; 2nd click sets end date (auto-swaps if 2nd date is earlier).
  - Hover preview dynamically previews the continuous emerald band.
  - Visual pills: Start date (`rounded-l-lg`), end date (`rounded-r-lg`), in-between range strip (`bg-emerald-500/20 text-emerald-300`), single-day selection (`rounded-lg`).
  - Quick footer actions: `"Hari Ini"` and `"Selesai"`.
- **Props / v-model:** `v-model:start="startDate"` and `v-model:end="endDate"`.

---

### Utilities

#### `src/lib/currency.js`

```js
import { formatRupiah, generateReceiptCode } from '@/lib/currency.js'
```

**`formatRupiah(amount)`**

Formats a number as Indonesian Rupiah using the `id-ID` locale.

| Input | Output |
|-------|--------|
| `150000` | `"Rp 150.000"` |
| `1500000` | `"Rp 1.500.000"` |
| `0` | `"Rp 0"` |
| `null` / `undefined` / `NaN` | `"Rp 0"` |

Implementation uses `Number(amount).toLocaleString('id-ID')` — dots as thousands separators, no decimal places for whole numbers.

**`generateReceiptCode()`**

Returns a random POS receipt code in the format `POS-XXXX` where XXXX is a random integer between 1000–9999.

```js
generateReceiptCode() // → "POS-8492"
```

> [!WARNING]
> `generateReceiptCode()` uses `Math.random()` — codes **can collide** on high transaction volume. The `receipt_code` column has a `UNIQUE` constraint, so a collision will cause an insert error. For production, use a sequential counter or UUID-based code. See Section 14.

---

#### `src/lib/supabase.js`

Exports a single `supabase` client instance. Throws a descriptive error at startup if environment variables are missing.

```js
import { supabase } from '@/lib/supabase.js'
```

The client is initialized with:
- `VITE_SUPABASE_URL` — your Supabase project URL
- `VITE_SUPABASE_ANON_KEY` — the public anon/service key

---

## 9. Revenue Split Logic

Every `transaction_item` stores a **snapshot** of the split at the time of sale. This means historical items are unaffected if `share_percent` is changed later.

### Formula

```
organizer_cut = ROUND(gross_amount × share_percent / 100, 0)
tenant_net    = gross_amount − organizer_cut
```

Rounding is to the nearest whole Rupiah (no decimals).

### Hierarchy

1. **Event default** — `events.default_share_percent` (default: `10.0`)
2. **Per-tenant override** — `tenants.share_percent` (default: `10.0`, can be set differently per tenant)
3. **Item snapshot** — `transaction_items.share_percent` is populated at insert time from the tenant's current `share_percent`

### Example

| Field | Value |
|-------|-------|
| Gross sale | Rp 150.000 |
| Share percent | 10% |
| Organizer cut | `ROUND(150000 × 10 / 100, 0)` = **Rp 15.000** |
| Tenant take-home | `150000 − 15000` = **Rp 135.000** |

### Aggregation in Totals

The `get_tenant_portal_data` RPC sums over **COMPLETED** transactions only:

```sql
SUM(ti.gross_amount)   → total_gross
SUM(ti.organizer_cut)  → total_organizer_cut
SUM(ti.tenant_net)     → total_net
```

---

## 10. Realtime Subscriptions

PopUpPOS uses Supabase Realtime (`postgres_changes`) to push live database updates to connected browsers without polling.

### Subscription Map

| Table | View | Channel Name | Filter | Trigger Action |
|-------|------|-------------|--------|---------------|
| `transactions` | `CashierView` | `cashier-transactions` | None (all events) | Refresh recent transactions drawer |
| `transaction_items` | `AdminDashboardView` | `admin-items` | None (all tenants) | Refresh summary cards |
| `transaction_items` | `TenantPortalView` | `tenant-portal-{token}` | `tenant_id=eq.{id}` | Re-fetch portal data via RPC |

### How to Subscribe (Pattern)

The pattern used in `TenantPortalView.vue`:

```js
import { supabase } from '@/lib/supabase.js'
import { onMounted, onUnmounted } from 'vue'

let realtimeChannel = null

function subscribeRealtime(tenantId) {
  realtimeChannel = supabase
    .channel('tenant-portal-' + tenantId)
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'transaction_items',
        filter: `tenant_id=eq.${tenantId}`,
      },
      async (payload) => {
        // Re-fetch full data to get computed fields from the trigger
        await fetchPortalData()
      }
    )
    .subscribe((status) => {
      realtimeConnected.value = status === 'SUBSCRIBED'
    })
}

onMounted(() => subscribeRealtime(tenant.value.id))

onUnmounted(() => {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
```

> [!IMPORTANT]
> Always call `supabase.removeChannel(channel)` in `onUnmounted` to avoid memory leaks and duplicate subscriptions when navigating between routes.

### Realtime Tables

Both `transactions` and `transaction_items` are added to the `supabase_realtime` publication in `schema.sql`. No manual Supabase dashboard config needed.

---

## 11. Tenant Portal Security Model

The Tenant Portal uses a **secret URL token** pattern — no login required.

### How It Works

1. When a tenant is created, Supabase auto-generates a `uuid` for `access_token` via `DEFAULT gen_random_uuid()`
2. The portal URL is: `https://your-app.com/tenant/<access_token>`
3. The token is passed to the `get_tenant_portal_data` RPC as `p_token`
4. The RPC runs as `SECURITY DEFINER` and only returns data for the matched tenant — **no cross-tenant data exposure**
5. The `access_token` itself is **never returned** in the RPC response

### Security Properties

| Property | Current (MVP) | Production Recommendation |
|----------|--------------|--------------------------|
| Token entropy | UUID v4 — 122 bits of randomness | Sufficient; keep as-is |
| Token in URL | Yes — appears in browser history | Acceptable for internal tools |
| Cross-tenant isolation | Enforced by RPC | ✅ Already production-safe |
| Token expiry | None | Add `token_expires_at` column + RPC check |
| Token revocation | Delete or regenerate the UUID | Add a `revoke` endpoint or admin button |
| Rate limiting | None | Add Supabase Edge Function rate limiting |
| PIN / OTP | None | Optional for sensitive revenue data |

---

## 12. Environment Setup

### Prerequisites

- Node.js 18+ and npm
- A [Supabase](https://supabase.com) project (free tier works)

### Steps

```bash
# 1. Clone the repository
git clone <repo-url>
cd nyaris-popup

# 2. Install dependencies
npm install

# 3. Configure environment
cp .env.example .env
# Edit .env and fill in:
#   VITE_SUPABASE_URL=https://your-project-id.supabase.co
#   VITE_SUPABASE_ANON_KEY=your-anon-key-here
#   VITE_ADMIN_PIN=000000
```

```sql
-- 4. Initialize the database
-- Go to: Supabase Dashboard → SQL Editor → New Query
-- Paste the entire contents of supabase/schema.sql and click Run
-- (Safe to re-run — all statements are idempotent)
```

```bash
# 5. Start the dev server
npm run dev
# → http://localhost:5173
```

```
# 6. First-run setup
# a. Open http://localhost:5173/admin
# b. Create your first event (name, venue, dates, share %)
# c. Add tenants to the event (name, category, booth number, bank info)
# d. Copy each tenant's portal link: http://localhost:5173/tenant/<access_token>
# e. Share portal links with tenants

# 7. Open the cashier terminal
# → http://localhost:5173/
```

### Build for Production

```bash
npm run build    # Outputs to dist/
npm run preview  # Preview the production build locally
```

---

## 13. Currency Formatting

All monetary values in this app use **Indonesian Rupiah (IDR)**.

| Property | Value |
|----------|-------|
| Locale | `id-ID` |
| Currency symbol | `Rp` (prefix, with space) |
| Thousands separator | `.` (dot) |
| Decimal separator | `,` (comma) — not shown for whole numbers |
| Example | `150000` → `"Rp 150.000"` |
| Example | `1500000` → `"Rp 1.500.000"` |

The `.rupiah` utility class in `style.css` applies `tabular-nums` and slight negative letter spacing for alignment in tables and cards:

```css
.rupiah {
  font-variant-numeric: tabular-nums;
  letter-spacing: -0.02em;
}
```

---

## 14. Known Limitations & Production TODO

| # | Limitation | Severity | Recommended Fix |
|---|-----------|----------|----------------|
| 1 | RLS policies allow full anon CRUD | 🔴 Critical | Restrict to `authenticated` role with `auth.uid()` checks before going public |
| 2 | `/admin` protected by client-side 6-digit PIN gate | 🟡 Medium | Upgrade to full Supabase Auth (email+password / MFA) for multi-user enterprise operations |
| 3 | Tenant portal tokens have no expiry | 🟡 Medium | Add `token_expires_at timestamptz` column; validate in RPC |
| 4 | No offline support | 🟡 Medium | Add service worker + IndexedDB queue for offline transaction drafts |
| 5 | Receipt codes use `Math.random()` — may collide | 🟡 Medium | Use a DB sequence or `uuid_generate_v4()` truncated to 8 chars |
| 6 | CSV export is client-side only | 🟢 Low | Fine for MVP; for large datasets, use a Supabase Edge Function |
| 7 | No void audit trail | 🟡 Medium | Add `voided_by`, `voided_at` columns to `transactions` |
| 8 | `useEvents` state is not shared | 🟢 Low | Add Pinia if the same events state is needed across multiple views simultaneously |
| 9 | No pagination on items list | 🟢 Low | Add limit/offset or cursor-based pagination in `get_tenant_portal_data` for high-volume events |
| 10 | No error boundary / global error handler | 🟡 Medium | Add Vue `app.config.errorHandler` and a toast notification system |

---

## 15. Design System Reference

PopUpPOS uses a **dark theme** throughout, built on Tailwind CSS with a custom `slate-950` extension.

### Color Palette

| Token | Hex / Tailwind | Usage |
|-------|---------------|-------|
| Background (app) | `slate-950` / `#020617` | Page and modal backgrounds |
| Surface | `slate-900` | Cards, panels, drawers |
| Border | `slate-800` | Card borders, dividers |
| Text primary | `white` | Headings, key values |
| Text secondary | `slate-400` | Labels, metadata |
| Text muted | `slate-500` | Timestamps, hints, empty states |
| Text faint | `slate-600` | Footer text |
| Accent — revenue | `emerald-400` | Tenant net / take-home values |
| Accent — revenue bg | `emerald-950` | Take-home card background |
| Accent — organizer cut | `amber-400` | Organizer cut values |
| Accent — QRIS | `sky-400` | QRIS payment method badge |
| Accent — CASH | `green-400` | Cash payment method badge |
| Accent — error | `red-400` | Error states |
| Realtime live | `emerald-400` + `animate-pulse` | Live connection dot |
| Realtime offline | `slate-600` | Offline connection dot |

### Typography

- **Font family:** System font stack (Tailwind default `font-sans`)
- **Antialiasing:** `antialiased` applied globally via `body` in `style.css`
- **Heading sizes:** `text-2xl font-bold` (tenant name), `text-sm font-semibold` (section headers)
- **Value sizes:** `text-3xl font-extrabold` (take-home), `text-lg font-bold` (summary cards), `text-sm font-medium` (line items)

### Component Patterns

**Card:**
```html
<div class="bg-slate-900 border border-slate-800 rounded-2xl p-4">
  <!-- content -->
</div>
```

**Badge/Pill:**
```html
<span class="inline-flex items-center gap-1 bg-slate-700 text-slate-200 text-xs font-medium px-3 py-1 rounded-full">
  Label
</span>
```

**Icon + Label row:**
```html
<div class="flex items-center gap-1.5 text-slate-400 text-xs font-medium">
  <SomeIcon class="w-3.5 h-3.5" />
  Label
</div>
```

**Realtime status indicator:**
```html
<span :class="['w-2 h-2 rounded-full', isLive ? 'bg-emerald-400 animate-pulse' : 'bg-slate-600']" />
<span :class="['text-xs', isLive ? 'text-emerald-400' : 'text-slate-500']">{{ isLive ? 'Live' : 'Offline' }}</span>
```

**Scrollbar (global, via `style.css`):**
- Width: `1.5` (Tailwind `w-1.5`)
- Track: `slate-900`
- Thumb: `slate-600`, `rounded-full`

### Spacing & Layout

- Max content width: `max-w-2xl mx-auto` (Tenant Portal), no max width constraint on Admin/Cashier
- Horizontal padding: `px-4`
- Vertical page padding: `py-8`
- Section spacing: `space-y-6`
- Card internal spacing: `p-4` (compact) / `p-5`–`p-6` (prominent cards)
- Grid: `grid grid-cols-2 gap-3` for summary cards (with `col-span-2` for full-width cards)

---

*This document is the authoritative handoff reference for PopUpPOS. Update it as features are implemented.*
