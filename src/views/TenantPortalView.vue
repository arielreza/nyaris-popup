<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import {
  Store,
  AlertCircle,
  Loader2,
  Banknote,
  TrendingUp,
  Percent,
  Building2,
  CheckCircle2,
  Wifi,
  WifiOff,
  AlertTriangle,
  XCircle,
} from 'lucide-vue-next'
import { supabase } from '@/lib/supabase.js'
import { formatRupiah } from '@/lib/currency.js'

// ─── State ────────────────────────────────────────────────────────────────────
const route = useRoute()
const loading = ref(true)
const error = ref(false)
const tenant = ref(null)
const event = ref(null)
const items = ref([])
const totals = ref(null)
const realtimeConnected = ref(false)
let realtimeChannel = null
let pollInterval = null

// ─── Computed ─────────────────────────────────────────────────────────────────
const sortedItems = computed(() =>
  [...items.value].sort(
    (a, b) =>
      new Date(b.transaction_created_at) - new Date(a.transaction_created_at)
  )
)

const completedCount = computed(() =>
  items.value.filter((i) => i.transaction_status === 'COMPLETED').length
)

const combinedSharePercent = computed(() => {
  if (!tenant.value) return 0
  return Number(tenant.value.venue_share_percent ?? 10) + Number(tenant.value.organizer_share_percent ?? 0)
})

const takeHomePercent = computed(() => {
  return Math.max(0, 100 - combinedSharePercent.value)
})

// ─── Relative time helper ─────────────────────────────────────────────────────
function relativeTime(isoString) {
  if (!isoString) return ''
  const diff = Math.floor((Date.now() - new Date(isoString).getTime()) / 1000)
  if (diff < 60) return `${diff}s lalu`
  if (diff < 3600) return `${Math.floor(diff / 60)} mnt lalu`
  if (diff < 86400) return `${Math.floor(diff / 3600)} jam lalu`
  return `${Math.floor(diff / 86400)}h lalu`
}

// ─── Data fetching ─────────────────────────────────────────────────────────────
async function fetchPortalData() {
  const token = route.params.token
  const { data, error: rpcError } = await supabase.rpc(
    'get_tenant_portal_by_token',
    { p_token: token }
  )

  if (rpcError || !data || !data.tenant || data.error) {
    error.value = true
    loading.value = false
    return
  }

  tenant.value = data.tenant
  event.value = data.event
  items.value = data.items ?? []
  totals.value = data.totals ?? {
    total_gross: 0,
    total_venue_cut: 0,
    total_organizer_cut: 0,
    total_combined_cut: 0,
    total_net: 0,
  }
  loading.value = false
}

// ─── Realtime subscription ─────────────────────────────────────────────────────
function subscribeRealtime() {
  realtimeChannel = supabase
    .channel('tenant-portal-' + route.params.token)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'transaction_items',
        filter: `tenant_id=eq.${tenant.value.id}`,
      },
      async () => {
        await fetchPortalData()
      }
    )
    .subscribe((status) => {
      realtimeConnected.value = status === 'SUBSCRIBED'
    })
}

// ─── Lifecycle ─────────────────────────────────────────────────────────────────
onMounted(async () => {
  await fetchPortalData()
  if (!error.value && tenant.value) {
    subscribeRealtime()
    // Periodic refresh every 15s to guarantee fresh data for login-free anon sessions
    pollInterval = setInterval(fetchPortalData, 15000)
  }
})

onUnmounted(() => {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
  if (pollInterval) {
    clearInterval(pollInterval)
  }
})
</script>

<template>
  <!-- ── Loading ──────────────────────────────────────────────────────────── -->
  <div
    v-if="loading"
    class="min-h-screen bg-light-surface flex flex-col items-center justify-center gap-4 text-light-on-surface"
  >
    <Loader2 class="w-10 h-10 text-light-primary animate-spin" />
    <p class="text-light-on-surface-variant text-sm font-body tracking-wide">Memuat portal tenant…</p>
  </div>

  <!-- ── Error ─────────────────────────────────────────────────────────────── -->
  <div
    v-else-if="error"
    class="min-h-screen bg-light-surface flex items-center justify-center p-6 text-light-on-surface"
  >
    <div
      class="bg-light-surface-container-lowest border border-light-outline-variant rounded-2xl p-8 max-w-sm w-full flex flex-col items-center gap-4 text-center shadow-xs"
    >
      <AlertCircle class="w-12 h-12 text-light-error" />
      <p class="text-light-on-surface font-display font-bold text-lg">Portal Tidak Ditemukan</p>
      <p class="text-light-on-surface-variant text-sm font-body">
        Portal tidak ditemukan atau link token tidak valid. Silakan periksa link Anda dan coba lagi.
      </p>
    </div>
  </div>

  <!-- ── Main Portal ───────────────────────────────────────────────────────── -->
  <div v-else class="min-h-screen bg-light-surface text-light-on-surface font-body selection:bg-light-primary/20">
    <div class="max-w-2xl mx-auto px-4 py-8 space-y-6">

      <!-- ── Header ──────────────────────────────────────────────────────── -->
      <header class="bg-light-surface-container-lowest border border-light-outline-variant rounded-2xl p-6 space-y-3 shadow-xs">
        <!-- Brand row -->
        <div class="flex items-center justify-between">
          <span class="text-xs font-label font-bold tracking-widest text-light-primary uppercase">
            PopUpPOS · Portal Tenant
          </span>
          <!-- Realtime indicator -->
          <div
            :class="[
              'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-label font-semibold',
              realtimeConnected
                ? 'bg-light-secondary-container text-light-primary'
                : 'bg-light-surface-container-low text-light-on-surface-variant'
            ]"
          >
            <span
              :class="[
                'w-2 h-2 rounded-full',
                realtimeConnected
                  ? 'bg-light-primary animate-pulse'
                  : 'bg-light-outline-variant',
              ]"
            />
            <span>
              {{ realtimeConnected ? 'LIVE' : 'OFFLINE' }}
            </span>
          </div>
        </div>

        <!-- Tenant name -->
        <h1 class="text-2xl sm:text-3xl font-display font-bold text-light-on-surface leading-tight">
          {{ tenant.name }}
        </h1>

        <!-- Badges row -->
        <div class="flex flex-wrap items-center gap-2">
          <span
            v-if="tenant.booth_number"
            class="inline-flex items-center gap-1 bg-light-surface-container-low text-light-on-surface border border-light-outline-variant text-xs font-label font-semibold px-3 py-1 rounded-full font-mono tabular-nums"
          >
            <Building2 class="w-3.5 h-3.5 text-light-primary" />
            Booth {{ tenant.booth_number }}
          </span>
          <span
            v-if="tenant.category"
            class="inline-flex items-center gap-1 bg-light-secondary-container text-light-primary text-xs font-label font-semibold px-3 py-1 rounded-full"
          >
            {{ tenant.category }}
          </span>
          <span
            v-if="tenant.payout_status === 'SETTLED'"
            class="inline-flex items-center gap-1 bg-light-primary text-light-on-primary text-xs font-label font-bold px-3 py-1 rounded-full shadow-xs"
          >
            <CheckCircle2 class="w-3.5 h-3.5" />
            Payout Lunas
          </span>
        </div>
      </header>

      <!-- ── Summary Cards ──────────────────────────────────────────────── -->
      <section aria-label="Ringkasan Penjualan" class="grid grid-cols-1 sm:grid-cols-2 gap-3.5">

        <!-- Gross Sales -->
        <div class="bg-light-surface-container-lowest border border-light-outline-variant rounded-2xl p-5 space-y-1 shadow-xs">
          <div class="flex items-center gap-1.5 text-light-on-surface-variant text-xs font-label font-semibold mb-2">
            <TrendingUp class="w-4 h-4 text-light-primary" />
            Gross Sales (Omzet Kotor)
          </div>
          <p class="text-light-on-surface font-mono font-bold text-2xl sm:text-3xl leading-tight tabular-nums">
            {{ formatRupiah(totals?.total_gross) }}
          </p>
          <p class="text-light-on-surface-variant text-xs font-body">Total penerimaan penjualan kotor</p>
        </div>

        <!-- Revenue Share Cuts -->
        <div class="bg-light-surface-container-lowest border border-light-tertiary/30 rounded-2xl p-5 space-y-1 shadow-xs">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-1.5 text-light-tertiary text-xs font-label font-semibold">
              <Percent class="w-4 h-4 text-light-tertiary" />
              Potongan Bagi Hasil
            </div>
            <span class="text-xs font-mono font-bold text-light-on-tertiary-container bg-light-tertiary-container px-2 py-0.5 rounded-full tabular-nums">
              {{ combinedSharePercent }}%
            </span>
          </div>
          <p class="text-light-tertiary font-mono font-bold text-2xl sm:text-3xl leading-tight tabular-nums">
            - {{ formatRupiah(totals?.total_combined_cut) }}
          </p>
          <p class="text-light-on-surface-variant text-xs font-body">Total potongan Venue &amp; Penyelenggara</p>
        </div>

        <!-- Your Take-Home (Net Payout) -->
        <div class="sm:col-span-2 bg-light-primary text-light-on-primary rounded-2xl p-6 space-y-2 shadow-sm">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 text-light-on-primary text-xs font-label font-bold uppercase tracking-wider">
              <Banknote class="w-4 h-4" />
              Your Take-Home (Net Payout)
            </div>
            <span class="text-xs font-label font-bold px-2.5 py-0.5 rounded-full bg-light-primary-container text-light-on-primary font-mono tabular-nums">
              {{ takeHomePercent }}% Hak Tenant
            </span>
          </div>
          <p class="text-light-on-primary font-mono font-black text-3xl sm:text-4xl leading-tight tabular-nums">
            {{ formatRupiah(totals?.total_net) }}
          </p>
          <p class="text-light-on-primary/90 text-xs font-body">
            Estimasi pencairan bersih setelah potongan bagi hasil ({{ combinedSharePercent }}%)
          </p>
        </div>

        <!-- Bank Info -->
        <div class="sm:col-span-2 bg-light-surface-container-lowest border border-light-outline-variant rounded-2xl p-5 shadow-xs">
          <div class="flex items-center gap-1.5 text-light-on-surface-variant text-xs font-label font-semibold mb-2">
            <Building2 class="w-4 h-4 text-light-primary" />
            Rekening Pencairan Dana (Bank Info)
          </div>
          <p
            :class="[
              'text-sm font-mono font-semibold tabular-nums',
              tenant.bank_info ? 'text-light-on-surface' : 'text-light-on-surface-variant italic font-body font-normal',
            ]"
          >
            {{ tenant.bank_info || 'Belum diisi oleh admin' }}
          </p>
        </div>
      </section>

      <!-- ── Live Sales Feed ───────────────────────────────────────────────── -->
      <section aria-label="Riwayat Penjualan Langsung" class="bg-light-surface-container-lowest border border-light-outline-variant rounded-2xl overflow-hidden shadow-xs">
        <!-- Section header -->
        <div class="flex items-center justify-between px-5 py-4 border-b border-light-outline-variant bg-light-surface-container-low">
          <div class="flex items-center gap-2">
            <span
              :class="[
                'w-2.5 h-2.5 rounded-full',
                realtimeConnected ? 'bg-light-primary animate-pulse' : 'bg-light-outline-variant',
              ]"
            />
            <h2 class="text-sm font-display font-bold text-light-on-surface tracking-wide">
              Live Sales Feed
            </h2>
          </div>
          <span class="text-xs font-mono font-semibold text-light-on-surface-variant tabular-nums">
            {{ sortedItems.length }} transaksi
          </span>
        </div>

        <!-- Empty state -->
        <div
          v-if="sortedItems.length === 0"
          class="flex flex-col items-center justify-center gap-4 py-16 px-6 text-center"
        >
          <div class="w-16 h-16 rounded-full bg-light-surface-container-low border border-light-outline-variant flex items-center justify-center">
            <Store class="w-8 h-8 text-light-on-surface-variant" />
          </div>
          <div>
            <p class="text-light-on-surface font-display font-bold">Belum ada penjualan</p>
            <p class="text-light-on-surface-variant text-sm font-body mt-1">
              Menunggu transaksi pertama tercatat di kasir…
            </p>
          </div>
        </div>

        <!-- Items list -->
        <div v-else class="divide-y divide-light-outline-variant max-h-[520px] overflow-y-auto">
          <div
            v-for="item in sortedItems"
            :key="item.id"
            :class="[
              'px-5 py-4 transition-colors',
              item.transaction_status === 'VOID' || item.transaction_status === 'VOIDED'
                ? 'bg-light-error-container/20 hover:bg-light-error-container/30'
                : 'hover:bg-light-surface-container-low'
            ]"
          >
            <!-- Top row: receipt code + payment badge + time -->
            <div class="flex items-center justify-between gap-2 mb-2">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-light-primary font-mono font-bold text-sm tabular-nums">
                  {{ item.receipt_code }}
                </span>
                <!-- Payment method badge -->
                <span
                  :class="[
                    'text-xs font-label font-bold px-2 py-0.5 rounded-full',
                    item.payment_method === 'QRIS'
                      ? 'bg-qris-container text-qris border border-qris/20'
                      : 'bg-light-secondary-container text-light-primary border border-light-primary/20',
                  ]"
                >
                  {{ item.payment_method }}
                </span>
                <!-- Void badge -->
                <span
                  v-if="item.transaction_status === 'VOID' || item.transaction_status === 'VOIDED'"
                  class="text-[11px] font-label font-bold px-2 py-0.5 rounded-full bg-light-error-container text-light-error border border-light-error/30 inline-flex items-center gap-1"
                >
                  <XCircle class="w-3 h-3" />
                  VOID
                </span>
              </div>
              <span class="text-light-on-surface-variant text-xs font-mono tabular-nums whitespace-nowrap">
                {{ relativeTime(item.transaction_created_at) }}
              </span>
            </div>

            <!-- Item note -->
            <p v-if="item.item_note" class="text-light-on-surface-variant text-xs font-body mb-2 italic">
              {{ item.item_note }}
            </p>

            <!-- Void Reason Banner -->
            <div
              v-if="(item.transaction_status === 'VOID' || item.transaction_status === 'VOIDED') && item.void_reason"
              class="flex items-center gap-1.5 text-xs text-light-error mb-2.5 bg-light-error-container/40 border border-light-error/30 rounded-md px-2.5 py-1 w-fit font-body"
            >
              <AlertTriangle class="w-3.5 h-3.5 text-light-error shrink-0" />
              <span>Alasan void: {{ item.void_reason }}</span>
            </div>

            <!-- Amount breakdown (3 clean figures: Gross, Potongan combined %, Your Net) -->
            <div
              :class="[
                'flex items-center gap-4 sm:gap-6 flex-wrap',
                item.transaction_status === 'VOID' || item.transaction_status === 'VOIDED' ? 'opacity-50 line-through' : ''
              ]"
            >
              <div>
                <p class="text-light-on-surface-variant text-xs font-label font-semibold">Gross</p>
                <p class="text-light-on-surface text-sm font-mono font-semibold tabular-nums">
                  {{ formatRupiah(item.gross_amount) }}
                </p>
              </div>
              <div>
                <p class="text-light-on-surface-variant text-xs font-label font-semibold">
                  Potongan ({{ Number(item.share_percent ?? (Number(item.venue_share_percent || 0) + Number(item.organizer_share_percent || 0))) }}%)
                </p>
                <p class="text-light-tertiary text-sm font-mono font-semibold tabular-nums">
                  - {{ formatRupiah(Number(item.venue_cut || 0) + Number(item.organizer_cut || 0)) }}
                </p>
              </div>
              <div>
                <p class="text-light-on-surface-variant text-xs font-label font-semibold">Your Net</p>
                <p class="text-light-primary text-sm font-mono font-bold tabular-nums">
                  {{ formatRupiah(item.tenant_net) }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Footer -->
      <footer class="text-center text-light-on-surface-variant font-body text-xs pb-4">
        PopUpPOS · Portal Tenant · Pembaruan data real-time
      </footer>
    </div>
  </div>
</template>
