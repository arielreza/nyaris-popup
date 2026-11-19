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
} from 'lucide-vue-next'
import { supabase } from '@/lib/supabase.js'
import { formatRupiah } from '@/lib/currency.js'

// ─── State ────────────────────────────────────────────────────────────────────
const route = useRoute()
const loading = ref(true)
const error = ref(false)
const tenant = ref(null)
const items = ref([])
const totals = ref(null)
const realtimeConnected = ref(false)
let realtimeChannel = null

// ─── Computed ─────────────────────────────────────────────────────────────────
const completedItems = computed(() =>
  [...items.value]
    .filter((i) => i.transaction_status !== 'VOIDED')
    .sort(
      (a, b) =>
        new Date(b.transaction_created_at) - new Date(a.transaction_created_at)
    )
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
  if (diff < 60) return `${diff}s ago`
  if (diff < 3600) return `${Math.floor(diff / 60)} min ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)} hr ago`
  return `${Math.floor(diff / 86400)}d ago`
}

// ─── Data fetching ─────────────────────────────────────────────────────────────
async function fetchPortalData() {
  const token = route.params.token
  const { data, error: rpcError } = await supabase.rpc(
    'get_tenant_portal_data',
    { p_token: token }
  )

  if (rpcError || !data || !data.tenant) {
    error.value = true
    loading.value = false
    return
  }

  tenant.value = data.tenant
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
        event: 'INSERT',
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
  }
})

onUnmounted(() => {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
</script>

<template>
  <!-- ── Loading ──────────────────────────────────────────────────────────── -->
  <div
    v-if="loading"
    class="min-h-screen bg-slate-950 flex flex-col items-center justify-center gap-4"
  >
    <Loader2 class="w-10 h-10 text-sky-400 animate-spin" />
    <p class="text-slate-400 text-sm tracking-wide">Loading your portal…</p>
  </div>

  <!-- ── Error ─────────────────────────────────────────────────────────────── -->
  <div
    v-else-if="error"
    class="min-h-screen bg-slate-950 flex items-center justify-center p-6"
  >
    <div
      class="bg-slate-900 border border-slate-800 rounded-2xl p-8 max-w-sm w-full flex flex-col items-center gap-4 text-center"
    >
      <AlertCircle class="w-12 h-12 text-red-400" />
      <p class="text-white font-semibold text-lg">Portal Not Found</p>
      <p class="text-slate-400 text-sm">
        Portal not found or link is invalid. Please check your link and try
        again.
      </p>
    </div>
  </div>

  <!-- ── Main Portal ───────────────────────────────────────────────────────── -->
  <div v-else class="min-h-screen bg-slate-950 text-white">
    <div class="max-w-2xl mx-auto px-4 py-8 space-y-6">

      <!-- ── Header ──────────────────────────────────────────────────────── -->
      <div class="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-3">
        <!-- Brand row -->
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold tracking-widest text-slate-500 uppercase">
            PopUpPOS
          </span>
          <!-- Realtime indicator -->
          <div class="flex items-center gap-1.5">
            <span
              :class="[
                'w-2 h-2 rounded-full',
                realtimeConnected
                  ? 'bg-emerald-400 animate-pulse'
                  : 'bg-slate-600',
              ]"
            />
            <span
              :class="[
                'text-xs',
                realtimeConnected ? 'text-emerald-400' : 'text-slate-500',
              ]"
            >
              {{ realtimeConnected ? 'Live' : 'Offline' }}
            </span>
          </div>
        </div>

        <!-- Tenant name -->
        <h1 class="text-2xl font-bold text-white leading-tight">
          {{ tenant.name }}
        </h1>

        <!-- Badges row -->
        <div class="flex flex-wrap items-center gap-2">
          <span
            v-if="tenant.booth_number"
            class="inline-flex items-center gap-1 bg-slate-700 text-slate-200 text-xs font-medium px-3 py-1 rounded-full"
          >
            <Building2 class="w-3 h-3" />
            Booth {{ tenant.booth_number }}
          </span>
          <span
            v-if="tenant.category"
            class="inline-flex items-center gap-1 bg-sky-800 text-sky-200 text-xs font-medium px-3 py-1 rounded-full"
          >
            {{ tenant.category }}
          </span>
          <span
            v-if="tenant.payout_status === 'SETTLED'"
            class="inline-flex items-center gap-1 bg-emerald-900 text-emerald-300 text-xs font-semibold px-3 py-1 rounded-full"
          >
            <CheckCircle2 class="w-3 h-3" />
            Payout Settled
          </span>
        </div>
      </div>

      <!-- ── Summary Cards ──────────────────────────────────────────────── -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">

        <!-- Gross Sales -->
        <div class="bg-slate-900 border border-slate-800 rounded-2xl p-4 space-y-1">
          <div class="flex items-center gap-1.5 text-slate-400 text-xs font-medium mb-2">
            <TrendingUp class="w-3.5 h-3.5" />
            Gross Sales
          </div>
          <p class="text-white font-bold text-xl leading-tight">
            {{ formatRupiah(totals?.total_gross) }}
          </p>
          <p class="text-slate-500 text-xs">Total pendapatan kotor</p>
        </div>

        <!-- Revenue Share Cuts -->
        <div class="bg-slate-900 border border-amber-900/40 rounded-2xl p-4 space-y-1">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-1.5 text-amber-400 text-xs font-medium">
              <Percent class="w-3.5 h-3.5" />
              Potongan Bagi Hasil ({{ combinedSharePercent }}%)
            </div>
            <span class="text-xs font-mono text-slate-400">
              {{ combinedSharePercent }}%
            </span>
          </div>
          <p class="text-amber-400 font-bold text-xl leading-tight">
            {{ formatRupiah(totals?.total_combined_cut) }}
          </p>
          <p class="text-slate-500 text-xs">Total bagi hasil ke penyelenggara</p>
        </div>

        <!-- Your Take-Home -->
        <div class="sm:col-span-2 bg-emerald-950/80 border border-emerald-800/60 rounded-2xl p-5 space-y-1">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-1.5 text-emerald-400 text-xs font-semibold">
              <Banknote class="w-4 h-4" />
              Your Take-Home (Net Payout)
            </div>
            <span class="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-900/60 text-emerald-300 border border-emerald-700/60">
              {{ takeHomePercent }}%
            </span>
          </div>
          <p class="text-emerald-400 font-extrabold text-3xl leading-tight">
            {{ formatRupiah(totals?.total_net) }}
          </p>
          <p class="text-emerald-500/80 text-xs">
            Net setelah potongan bagi hasil ({{ combinedSharePercent }}%)
          </p>
        </div>

        <!-- Bank Info -->
        <div class="sm:col-span-2 bg-slate-900 border border-slate-800 rounded-2xl p-4">
          <div class="flex items-center gap-1.5 text-slate-400 text-xs font-medium mb-2">
            <Banknote class="w-3.5 h-3.5" />
            Bank Info (Rekening Pembayaran)
          </div>
          <p
            :class="[
              'text-sm font-medium',
              tenant.bank_info ? 'text-white' : 'text-slate-500 italic',
            ]"
          >
            {{ tenant.bank_info || 'Belum diisi oleh admin' }}
          </p>
        </div>
      </div>

      <!-- ── Live Sales Feed ───────────────────────────────────────────────── -->
      <div class="bg-slate-900 border border-slate-800 rounded-2xl overflow-hidden">
        <!-- Section header -->
        <div class="flex items-center justify-between px-5 py-4 border-b border-slate-800">
          <div class="flex items-center gap-2">
            <span
              :class="[
                'w-2 h-2 rounded-full',
                realtimeConnected ? 'bg-emerald-400 animate-pulse' : 'bg-slate-500',
              ]"
            />
            <h2 class="text-sm font-semibold text-white tracking-wide">
              Live Sales Feed
            </h2>
          </div>
          <span class="text-xs text-slate-500">
            {{ completedItems.length }} transaction{{ completedItems.length !== 1 ? 's' : '' }}
          </span>
        </div>

        <!-- Empty state -->
        <div
          v-if="completedItems.length === 0"
          class="flex flex-col items-center justify-center gap-4 py-16 px-6 text-center"
        >
          <div class="bg-slate-800 rounded-full p-5">
            <Store class="w-10 h-10 text-slate-500" />
          </div>
          <div>
            <p class="text-slate-300 font-medium">No sales yet</p>
            <p class="text-slate-500 text-sm mt-1">
              Waiting for first transaction…
            </p>
          </div>
        </div>

        <!-- Items list -->
        <div v-else class="divide-y divide-slate-800 max-h-[520px] overflow-y-auto">
          <div
            v-for="item in completedItems"
            :key="item.id"
            class="px-5 py-4 hover:bg-slate-800/50 transition-colors"
          >
            <!-- Top row: receipt code + payment badge + time -->
            <div class="flex items-center justify-between gap-2 mb-2">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-white font-semibold text-sm">
                  {{ item.receipt_code }}
                </span>
                <!-- Payment method badge -->
                <span
                  :class="[
                    'text-xs font-semibold px-2 py-0.5 rounded-full',
                    item.payment_method === 'QRIS'
                      ? 'bg-sky-900/60 text-sky-400 border border-sky-800'
                      : 'bg-green-900/60 text-green-400 border border-green-800',
                  ]"
                >
                  {{ item.payment_method }}
                </span>
              </div>
              <span class="text-slate-500 text-xs whitespace-nowrap">
                {{ relativeTime(item.transaction_created_at) }}
              </span>
            </div>

            <!-- Item note -->
            <p v-if="item.item_note" class="text-slate-400 text-xs mb-2 italic">
              {{ item.item_note }}
            </p>

            <!-- Amount breakdown (3 clean figures: Gross, Potongan combined %, Your Net) -->
            <div class="flex items-center gap-4 sm:gap-6 flex-wrap">
              <div>
                <p class="text-slate-500 text-xs">Gross</p>
                <p class="text-white text-sm font-medium">
                  {{ formatRupiah(item.gross_amount) }}
                </p>
              </div>
              <div>
                <p class="text-slate-500 text-xs">
                  Potongan ({{ Number(item.share_percent ?? (Number(item.venue_share_percent || 0) + Number(item.organizer_share_percent || 0))) }}%)
                </p>
                <p class="text-amber-400 text-sm font-medium">
                  - {{ formatRupiah(Number(item.venue_cut || 0) + Number(item.organizer_cut || 0)) }}
                </p>
              </div>
              <div>
                <p class="text-slate-500 text-xs">Your Net</p>
                <p class="text-emerald-400 text-sm font-semibold">
                  {{ formatRupiah(item.tenant_net) }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Footer -->
      <p class="text-center text-slate-600 text-xs pb-4">
        PopUpPOS · Tenant Portal · Data updates in real-time
      </p>
    </div>
  </div>
</template>
