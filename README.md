# PopUpPOS — Central POS & Multi-Tenant Revenue-Share System

Sistem kasir terpusat (*Central Point of Sale*) dan pembagian bagi hasil otomatis (*3-way revenue-share split*) untuk operasional *pop-up market*, bazar kreatif, dan *curated retail event*.

**Live App:** [nyaris-popup.vercel.app](https://nyaris-popup.vercel.app)

---

## Fitur Utama

- **Central Cashier POS (`/`):**
  - Pencatatan transaksi multi-*tenant* dalam satu struk terpadu (`QRIS` & `CASH`).
  - Kalkulator uang tunai diterima (*Cash Tendered*), tombol **Uang Pas**, chip denominasi cepat, serta perhitungan kembalian otomatis.
  - Struk digital dengan opsi salin teks (*Copy Text*) dan riwayat transaksi terbaru lengkap dengan rincian item per *booth* serta fitur *Void*.
- **Admin Dashboard (`/admin` — PIN Protected):**
  - **Overview & Settlement:** Ringkasan omzet kotor, potongan *Venue*, potongan *Organizer/EO*, hak bersih *tenant*, ekspor rekap PDF acara, slip PDF per *tenant*, serta tombol salin pesan *settlement* WhatsApp satu klik.
  - **Event & Lineup:** Manajemen jadwal acara, pengaturan persentase bagi hasil *default* maupun *override* per *tenant*, dan pembagian link portal unik.
  - **Master Tenant:** Direktori terpusat lintas acara lengkap dengan kontak PIC, WhatsApp, Instagram, info rekening transfer, serta filter kategori.
- **Tenant Live Transparency Portal (`/tenant/:token`):**
  - Pemantauan penjualan *real-time* bagi masing-masing *tenant* melalui token unik tanpa perlu login.
  - Menjaga privasi pembagian internal dengan hanya menampilkan total persentase potongan gabungan dan pendapatan bersih (*Net Take-Home*).

---

## Tech Stack

- **Frontend:** Vue 3 (Composition API), Vite, Vue Router, Tailwind CSS
- **Backend & Realtime:** Supabase (PostgreSQL, Realtime Subscriptions, Row Level Security, RPC)
- **Document Export:** `jspdf` & `jspdf-autotable`
- **Deployment:** Vercel

---

## Menjalankan Secara Lokal

1. **Clone repository & install dependensi:**
   ```bash
   git clone https://github.com/arielreza/nyaris-popup.git
   cd nyaris-popup
   npm install
   ```

2. **Konfigurasi Environment Variables:**
   Buat file `.env` di root proyek dan isi kredensial berikut:
   ```env
   VITE_SUPABASE_URL=your_supabase_project_url
   VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
   VITE_ADMIN_PIN=123456
   ```

3. **Setup Database Supabase:**
   Jalankan seluruh skrip SQL dari file `supabase/schema.sql` pada **SQL Editor** di dashboard Supabase.

4. **Jalankan server development:**
   ```bash
   npm run dev
   ```