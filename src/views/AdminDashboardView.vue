<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import {
  ShieldCheck,
  ShoppingCart,
  ChevronDown,
  ChevronUp,
  Plus,
  Loader2,
  Copy,
  Check,
  Download,
  RefreshCw,
  TrendingUp,
  Wallet,
  CreditCard,
  Banknote,
  Lock,
  Delete,
  ArrowLeft,
  Pencil,
  Users,
  Search,
  X,
  Filter,
  Trash2,
  CalendarCheck,
  Building2,
  Store,
  ExternalLink,
  AlertCircle,
  CheckCircle2,
  FileText,
  MessageSquare,
  LogOut,
} from 'lucide-vue-next'
import { supabase } from '@/lib/supabase.js'
import { useAuth } from '@/lib/useAuth.js'
import { useEvents } from '@/lib/useEvents.js'
import { formatRupiah } from '@/lib/currency.js'
import DateRangePicker from '@/components/DateRangePicker.vue'
import { generateEventSettlementPdf, generateTenantSettlementPdf } from '@/lib/exportSettlementPdf.js'

const router = useRouter()
const route = useRoute()
const { signOut } = useAuth()
const { selectedEventId: globalEventId, selectEventId: setGlobalEventId } = useEvents()

async function handleLogout() {
  lockAdmin()
  await signOut()
  router.push('/login')
}

// ─── PIN Gate State ───────────────────────────────────────────────────────────

const ADMIN_PIN = import.meta.env.VITE_ADMIN_PIN || '000000'
const isUnlocked = ref(false)
const enteredPin = ref('')
const pinError = ref('')
const isShaking = ref(false)

function appendDigit(digit) {
  if (enteredPin.value.length >= 6) return
  pinError.value = ''
  enteredPin.value += digit
  if (enteredPin.value.length === 6) {
    verifyPin()
  }
}

function deleteDigit() {
  pinError.value = ''
  if (enteredPin.value.length > 0) {
    enteredPin.value = enteredPin.value.slice(0, -1)
  }
}

function clearPin() {
  pinError.value = ''
  enteredPin.value = ''
}

async function verifyPin() {
  if (enteredPin.value === ADMIN_PIN) {
    sessionStorage.setItem('popuppos_admin_unlocked', 'true')
    isUnlocked.value = true
    pinError.value = ''
    enteredPin.value = ''
    await Promise.all([fetchEvents(), fetchMasterTenants()])
    subscribeMasterRealtime()
    if (events.value.length && !selectedEventId.value) {
      const match = globalEventId.value && events.value.find((e) => e.id === globalEventId.value)
      selectedEventId.value = match ? match.id : events.value[0].id
    }
  } else {
    pinError.value = 'PIN salah, coba lagi'
    isShaking.value = true
    setTimeout(() => {
      isShaking.value = false
      enteredPin.value = ''
    }, 600)
  }
}

function lockAdmin() {
  sessionStorage.removeItem('popuppos_admin_unlocked')
  isUnlocked.value = false
  enteredPin.value = ''
  pinError.value = ''
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
  if (masterRealtimeChannel) {
    supabase.removeChannel(masterRealtimeChannel)
    masterRealtimeChannel = null
  }
}

function handleKeydown(e) {
  if (isUnlocked.value) return
  if (/^[0-9]$/.test(e.key)) {
    e.preventDefault()
    appendDigit(e.key)
  } else if (e.key === 'Backspace') {
    e.preventDefault()
    deleteDigit()
  } else if (e.key === 'Escape') {
    e.preventDefault()
    clearPin()
  }
}

// ─── State ────────────────────────────────────────────────────────────────────

const activeTab = ref(
  (route.query.tab && ['overview', 'lineup', 'master'].includes(String(route.query.tab).toLowerCase()))
    ? String(route.query.tab).toLowerCase()
    : 'overview'
) // 'overview' | 'lineup' | 'master'

watch(
  () => route.query.tab,
  (newTab) => {
    if (newTab && ['overview', 'lineup', 'master'].includes(String(newTab).toLowerCase())) {
      activeTab.value = String(newTab).toLowerCase()
    }
  }
)

function switchAdminTab(tabKey, event) {
  activeTab.value = tabKey
  if (route.query.tab !== tabKey) {
    router.replace({ query: { ...route.query, tab: tabKey } })
  }
  if (event?.currentTarget) {
    event.currentTarget.scrollIntoView({
      behavior: 'smooth',
      inline: 'center',
      block: 'nearest'
    })
  }
}

watch(activeTab, async () => {
  await nextTick()
  requestAnimationFrame(() => {
    window.scrollTo(0, 0)
    document.documentElement.scrollTop = 0
    document.body.scrollTop = 0
  })
})

const events = ref([])
const selectedEventId = ref(null)

watch(globalEventId, (newId) => {
  if (newId && newId !== selectedEventId.value && events.value.some((e) => e.id === newId)) {
    selectedEventId.value = newId
  }
})
const tenants = ref([])
const transactionItems = ref([]) // items with joined transaction info
const transactions = ref([]) // transactions for active event

const loadingEvents = ref(false)
const loadingTenants = ref(false)
const loadingItems = ref(false)

const showCreateEventForm = ref(false)
const showAddTenantForm = ref(false)

const copiedId = ref(null) // track which tenant link was just copied
const copiedInviteId = ref(null) // track which tenant invite was just copied
let realtimeChannel = null

// ─── Create Event Form ────────────────────────────────────────────────────────

const newEvent = ref({
  name: '',
  venue: '',
  venue_share_percent: 10,
  organizer_share_percent: 0,
})

const newEventTotalCut = computed(() => {
  return Number(newEvent.value.venue_share_percent || 0) + Number(newEvent.value.organizer_share_percent || 0)
})
const newEventTenantTakeHome = computed(() => {
  return Math.max(0, 100 - newEventTotalCut.value)
})

const todayStr = new Date().toISOString().slice(0, 10)
const eventStartDate = ref(todayStr)
const eventEndDate = ref(todayStr)
const creatingEvent = ref(false)
const createEventError = ref('')

const ID_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des']

function formatEventDates(startStr, endStr) {
  if (!startStr) return ''
  const [sY, sM, sD] = startStr.split('-').map(Number)
  const [eY, eM, eD] = (endStr || startStr).split('-').map(Number)

  if (!endStr || startStr === endStr) {
    return `${sD} ${ID_MONTHS[sM - 1]} ${sY}`
  }
  if (sY === eY && sM === eM) {
    return `${sD}–${eD} ${ID_MONTHS[sM - 1]} ${sY}`
  }
  if (sY === eY) {
    return `${sD} ${ID_MONTHS[sM - 1]} – ${eD} ${ID_MONTHS[eM - 1]} ${sY}`
  }
  return `${sD} ${ID_MONTHS[sM - 1]} ${sY} – ${eD} ${ID_MONTHS[eM - 1]} ${eY}`
}

function onStartDateChange() {
  if (!eventEndDate.value || eventEndDate.value < eventStartDate.value) {
    eventEndDate.value = eventStartDate.value
  }
}

const eventDatesPreview = computed(() => {
  return formatEventDates(eventStartDate.value, eventEndDate.value)
})

// ─── Add Tenant Form ──────────────────────────────────────────────────────────

const PRESET_CATEGORIES = [
  'Fashion & Apparel',
  'Food & Beverage',
  'Beauty & Nail Art',
  'Accessories & Jewelry',
  'Interactive / Tarot / Photo',
  'Art & Collectibles',
  'Thrift & Vintage',
  'Other (Custom)'
]

const selectedCategory = ref('Food & Beverage')
const customCategory = ref('')

const newTenant = ref({
  name: '',
  booth_number: '',
  venue_share_percent: 10,
  organizer_share_percent: 0,
  bank_info: '',
})

const newTenantTotalCut = computed(() => {
  return Number(newTenant.value.venue_share_percent || 0) + Number(newTenant.value.organizer_share_percent || 0)
})
const newTenantTakeHome = computed(() => {
  return Math.max(0, 100 - newTenantTotalCut.value)
})

const addingTenant = ref(false)
const addTenantError = ref('')

// ─── Computed helpers ─────────────────────────────────────────────────────────

const selectedEvent = computed(() =>
  events.value.find((e) => e.id === selectedEventId.value) || null
)

// transaction_items joined with their transaction (payment_method, status)
// We only count non-VOIDED transactions
const validItems = computed(() =>
  transactionItems.value.filter((i) => i.transactions?.status !== 'VOIDED')
)

const totalGross = computed(() =>
  validItems.value.reduce((s, i) => s + Number(i.gross_amount || 0), 0)
)
const totalVenueCut = computed(() =>
  validItems.value.reduce((s, i) => s + Number(i.venue_cut || 0), 0)
)
const totalOrganizerCut = computed(() =>
  validItems.value.reduce((s, i) => s + Number(i.organizer_cut || 0), 0)
)
const totalTenantNet = computed(() =>
  validItems.value.reduce((s, i) => s + Number(i.tenant_net || 0), 0)
)
const totalQris = computed(() =>
  validItems.value
    .filter((i) => i.transactions?.payment_method === 'QRIS')
    .reduce((s, i) => s + Number(i.gross_amount || 0), 0)
)
const totalCash = computed(() =>
  validItems.value
    .filter((i) => i.transactions?.payment_method === 'CASH')
    .reduce((s, i) => s + Number(i.gross_amount || 0), 0)
)

// Non-void transactions for active event
const validTransactions = computed(() => {
  if (transactions.value.length > 0) {
    return transactions.value.filter((t) => t.status !== 'VOID' && t.status !== 'VOIDED')
  }
  // Fallback: derive distinct parent transactions from validItems
  const map = new Map()
  for (const item of validItems.value) {
    if (item.transactions && !map.has(item.transactions.id)) {
      map.set(item.transactions.id, item.transactions)
    }
  }
  return Array.from(map.values()).filter((t) => t.status !== 'VOID' && t.status !== 'VOIDED')
})

// End-of-Day Payment Reconciliation
const paymentBreakdown = computed(() => {
  const activeTxs = validTransactions.value
  const qrisTxs = activeTxs.filter((t) => t.payment_method === 'QRIS')
  const cashTxs = activeTxs.filter((t) => t.payment_method === 'CASH')

  const qrisTotal = qrisTxs.reduce((sum, t) => sum + Number(t.total_amount || 0), 0)
  const qrisCount = qrisTxs.length

  const cashTotal = cashTxs.reduce((sum, t) => sum + Number(t.total_amount || 0), 0)
  const cashCount = cashTxs.length

  const cashTenderedTotal = cashTxs.reduce((sum, t) => {
    const tendered = t.cash_tendered != null ? Number(t.cash_tendered) : Number(t.total_amount || 0)
    return sum + tendered
  }, 0)

  const cashChangeTotal = cashTxs.reduce((sum, t) => sum + Number(t.change_amount || 0), 0)

  const gross = totalGross.value || (qrisTotal + cashTotal)
  const qrisPct = gross > 0 ? Math.round((qrisTotal / gross) * 100) : 0
  const cashPct = gross > 0 ? Math.max(0, 100 - qrisPct) : 0

  return {
    qrisTotal,
    qrisCount,
    cashTotal,
    cashCount,
    cashTenderedTotal,
    cashChangeTotal,
    qrisPct,
    cashPct,
  }
})

// Per-tenant settlement rows
const settlementRows = computed(() => {
  return tenants.value.map((tenant) => {
    const items = validItems.value.filter((i) => i.tenant_id === tenant.id)
    const gross = items.reduce((s, i) => s + Number(i.gross_amount || 0), 0)
    const venueCut = items.reduce((s, i) => s + Number(i.venue_cut || 0), 0)
    const orgCut = items.reduce((s, i) => s + Number(i.organizer_cut || 0), 0)
    const net = items.reduce((s, i) => s + Number(i.tenant_net || 0), 0)
    return { ...tenant, gross, venueCut, orgCut, net, items }
  })
})

// ─── Data Fetching ────────────────────────────────────────────────────────────

async function fetchEvents() {
  loadingEvents.value = true
  const { data, error } = await supabase
    .from('events')
    .select('*')
    .order('created_at', { ascending: false })
  loadingEvents.value = false
  if (!error) events.value = data
}

async function fetchTenants(eventId) {
  if (!eventId) { tenants.value = []; return }
  loadingTenants.value = true
  const { data, error } = await supabase
    .from('tenants')
    .select('*')
    .eq('event_id', eventId)
    .order('booth_number', { ascending: true })
  loadingTenants.value = false
  if (!error) tenants.value = data
}

async function fetchTransactionItems(eventId) {
  if (!eventId) {
    transactionItems.value = []
    transactions.value = []
    return
  }
  loadingItems.value = true
  const [itemsRes, txRes] = await Promise.all([
    supabase
      .from('transaction_items')
      .select(`
        *,
        transactions!inner(id, receipt_code, payment_method, status, total_amount, cash_tendered, change_amount, event_id, created_at)
      `)
      .eq('transactions.event_id', eventId),
    supabase
      .from('transactions')
      .select('id, receipt_code, payment_method, total_amount, cash_tendered, change_amount, status, event_id, created_at')
      .eq('event_id', eventId)
      .order('created_at', { ascending: false })
  ])
  loadingItems.value = false
  if (!itemsRes.error) transactionItems.value = itemsRes.data || []
  if (!txRes.error) transactions.value = txRes.data || []
}

// ─── Realtime ─────────────────────────────────────────────────────────────────

function subscribeRealtime(eventId) {
  if (realtimeChannel) {
    try {
      supabase.removeChannel(realtimeChannel)
    } catch (err) {
      console.warn('[Admin Realtime] Cleanup error:', err)
    }
    realtimeChannel = null
  }
  if (!eventId) return

  const uniqueTopic = `admin-items-${eventId}:${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
  realtimeChannel = supabase
    .channel(uniqueTopic)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'transaction_items' },
      () => { fetchTransactionItems(eventId) }
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'transactions', filter: `event_id=eq.${eventId}` },
      () => { fetchTransactionItems(eventId) }
    )
    .subscribe((status, err) => {
      if (err) console.warn('[Admin Realtime] Subscription status:', status, err)
    })
}

// ─── Watch selected event ─────────────────────────────────────────────────────

watch(selectedEventId, (id) => {
  if (id && id !== globalEventId.value) {
    setGlobalEventId(id)
  }
  fetchTenants(id)
  fetchTransactionItems(id)
  subscribeRealtime(id)
  showAddTenantForm.value = false
  showEditEventForm.value = false
  closeEditTenantModal()
  if (selectedEvent.value) {
    newTenant.value.venue_share_percent = Number(selectedEvent.value.venue_share_percent ?? 10)
    newTenant.value.organizer_share_percent = Number(selectedEvent.value.organizer_share_percent ?? 0)
  }
})

// ─── Lifecycle ────────────────────────────────────────────────────────────────

onMounted(async () => {
  const sessionUnlocked = sessionStorage.getItem('popuppos_admin_unlocked') === 'true'
  if (sessionUnlocked) {
    isUnlocked.value = true
    await Promise.all([fetchEvents(), fetchMasterTenants()])
    subscribeMasterRealtime()
    if (events.value.length) {
      const match = globalEventId.value && events.value.find((e) => e.id === globalEventId.value)
      selectedEventId.value = match ? match.id : events.value[0].id
    }
  }
  window.addEventListener('keydown', handleKeydown)
  window.addEventListener('lock-admin', lockAdmin)
})

onUnmounted(() => {
  if (realtimeChannel) supabase.removeChannel(realtimeChannel)
  if (masterRealtimeChannel) supabase.removeChannel(masterRealtimeChannel)
  window.removeEventListener('keydown', handleKeydown)
  window.removeEventListener('lock-admin', lockAdmin)
})

// ─── Create Event ─────────────────────────────────────────────────────────────

async function createEvent() {
  createEventError.value = ''
  if (!newEvent.value.name.trim()) {
    createEventError.value = 'Event name is required.'
    return
  }
  creatingEvent.value = true
  const formattedDates = formatEventDates(eventStartDate.value, eventEndDate.value)
  const venueShare = Number(newEvent.value.venue_share_percent ?? 10)
  const orgShare = Number(newEvent.value.organizer_share_percent ?? 0)
  const totalDefaultShare = venueShare + orgShare

  const { data, error } = await supabase
    .from('events')
    .insert([
      {
        name: newEvent.value.name.trim(),
        venue: newEvent.value.venue.trim(),
        event_dates: formattedDates,
        default_share_percent: totalDefaultShare,
        venue_share_percent: venueShare,
        organizer_share_percent: orgShare,
        status: 'ACTIVE',
        is_active: true,
      }
    ])
    .select()
    .single()
  creatingEvent.value = false
  if (error) {
    createEventError.value = error.message
    return
  }
  events.value.unshift(data)
  selectedEventId.value = data.id
  newEvent.value = { name: '', venue: '', venue_share_percent: 10, organizer_share_percent: 0 }
  const today = new Date().toISOString().slice(0, 10)
  eventStartDate.value = today
  eventEndDate.value = today
  showCreateEventForm.value = false
}

// ─── Add Tenant ───────────────────────────────────────────────────────────────

async function addTenant() {
  addTenantError.value = ''
  const trimmedName = newTenant.value.name.trim()
  if (!trimmedName) {
    addTenantError.value = 'Tenant name is required.'
    return
  }

  // 1. Validasi Brand duplikat di event ini
  const isDuplicateBrand = tenants.value.some(
    (t) => (t.name || '').trim().toLowerCase() === trimmedName.toLowerCase()
  )
  if (isDuplicateBrand) {
    const errorMsg = `Brand "${trimmedName}" sudah terdaftar di lineup event ini.`
    addTenantError.value = errorMsg
    showToast('error', errorMsg)
    return
  }

  // 2. Validasi Nomor/Kode Booth duplikat di event ini (jika diisi)
  const trimmedBooth = (newTenant.value.booth_number || '').trim()
  if (trimmedBooth) {
    const isDuplicateBooth = tenants.value.some(
      (t) => (t.booth_number || '').trim().toLowerCase() === trimmedBooth.toLowerCase()
    )
    if (isDuplicateBooth) {
      const errorMsg = `Nomor/Kode Booth "${trimmedBooth}" sudah digunakan oleh booth lain di event ini.`
      addTenantError.value = errorMsg
      showToast('error', errorMsg)
      return
    }
  }

  const finalCategory = selectedCategory.value === 'Other (Custom)'
    ? customCategory.value.trim()
    : selectedCategory.value

  if (!finalCategory) {
    addTenantError.value = 'Category is required.'
    return
  }

  addingTenant.value = true
  const venueShare = Number(newTenant.value.venue_share_percent ?? 10)
  const orgShare = Number(newTenant.value.organizer_share_percent ?? 0)
  const totalShare = venueShare + orgShare

  // Auto-sync or link to master_tenants directory
  let masterTenantId = null
  try {
    const { data: existingMaster } = await supabase
      .from('master_tenants')
      .select('id, category, bank_info')
      .ilike('name', newTenant.value.name.trim())
      .maybeSingle()

    if (existingMaster) {
      masterTenantId = existingMaster.id
      const updates = {}
      if (!existingMaster.bank_info && newTenant.value.bank_info.trim()) {
        updates.bank_info = newTenant.value.bank_info.trim()
      }
      if (!existingMaster.category && finalCategory) {
        updates.category = finalCategory
      }
      if (Object.keys(updates).length > 0) {
        await supabase.from('master_tenants').update(updates).eq('id', existingMaster.id)
      }
    } else {
      const { data: createdMaster } = await supabase
        .from('master_tenants')
        .insert({
          name: newTenant.value.name.trim(),
          category: finalCategory,
          bank_info: newTenant.value.bank_info.trim(),
          contact_info: '',
        })
        .select('id')
        .single()
      if (createdMaster) {
        masterTenantId = createdMaster.id
      }
    }
    await fetchMasterTenants()
  } catch (err) {
    console.warn('Could not sync to master_tenants:', err)
  }

  const { data, error } = await supabase
    .from('tenants')
    .insert([
      {
        name: newTenant.value.name.trim(),
        category: finalCategory,
        booth_number: newTenant.value.booth_number.trim(),
        share_percent: totalShare,
        venue_share_percent: venueShare,
        organizer_share_percent: orgShare,
        bank_info: newTenant.value.bank_info.trim(),
        event_id: selectedEventId.value,
        master_tenant_id: masterTenantId,
      }
    ])
    .select()
    .single()
  addingTenant.value = false
  if (error) {
    addTenantError.value = error.message
    return
  }
  tenants.value.push(data)
  newTenant.value = {
    name: '',
    booth_number: '',
    venue_share_percent: selectedEvent.value?.venue_share_percent ?? 10,
    organizer_share_percent: selectedEvent.value?.organizer_share_percent ?? 0,
    bank_info: '',
  }
  selectedCategory.value = 'Food & Beverage'
  customCategory.value = ''
  showAddTenantForm.value = false
}

// ─── Copy Portal Link & WhatsApp Invite ───────────────────────────────────────

async function copyPortalLink(tenant) {
  const url = `${window.location.origin}/tenant/${tenant.access_token}`
  await navigator.clipboard.writeText(url)
  copiedId.value = tenant.id
  setTimeout(() => { copiedId.value = null }, 2000)
}

function getLinkedMasterTenant(tenant) {
  if (!tenant) return null
  if (tenant.master_tenant_id) {
    const found = masterTenants.value.find((m) => m.id === tenant.master_tenant_id)
    if (found) return found
  }
  const cleanName = (tenant.name || '').trim().toLowerCase()
  return masterTenants.value.find((m) => (m.name || '').trim().toLowerCase() === cleanName) || null
}

function normalizeWhatsappNumber(rawPhone) {
  if (!rawPhone) return ''
  let cleaned = String(rawPhone).replace(/\D/g, '')
  if (cleaned.startsWith('08')) {
    cleaned = '628' + cleaned.slice(2)
  } else if (cleaned.startsWith('8')) {
    cleaned = '628' + cleaned.slice(1)
  }
  return cleaned
}

function buildTenantPortalInviteMessage(tenant) {
  const ev = selectedEvent.value
  const evName = ev?.name || 'Event Pop-up'
  const evDatesStr = ev?.event_dates ? ` (*${ev.event_dates}*)` : ''
  const tenantName = tenant.name || 'Tenant'

  const master = getLinkedMasterTenant(tenant)
  const picName = master?.pic_name?.trim()
  const picStr = picName ? ` (PIC: ${picName})` : ''

  const boothStr = tenant.booth_number && tenant.booth_number !== '—'
    ? ` (Booth *${tenant.booth_number}*)`
    : ''

  const portalUrl = `${window.location.origin}/tenant/${tenant.access_token}`

  return [
    `Halo *${tenantName}*${picStr},`,
    `Berikut adalah link akses Portal Live Sales untuk event *${evName}*${evDatesStr}${boothStr}:`,
    ``,
    `🔗 *Link Portal:* ${portalUrl}`,
    ``,
    `💡 *Informasi:*`,
    `• Pantau rekap penjualan kotor, rincian transaksi, dan bagi hasil bersih secara real-time tanpa perlu login.`,
    `• Mohon simpan link ini dan jaga kerahasiaannya untuk tim internal booth Anda.`,
    ``,
    `Semoga lancar dan sukses untuk penjualannya! 🙏✨`,
  ].join('\n')
}

function getTenantWhatsappUrl(tenant) {
  const master = getLinkedMasterTenant(tenant)
  const phone = normalizeWhatsappNumber(master?.whatsapp)
  if (!phone) return null
  const message = buildTenantPortalInviteMessage(tenant)
  return `https://wa.me/${phone}?text=${encodeURIComponent(message)}`
}

async function copyTenantPortalInvite(tenant) {
  try {
    const msg = buildTenantPortalInviteMessage(tenant)
    await navigator.clipboard.writeText(msg)
    copiedInviteId.value = tenant.id
    setTimeout(() => {
      if (copiedInviteId.value === tenant.id) copiedInviteId.value = null
    }, 2000)
    showToast('success', `Undangan portal WA untuk ${tenant.name} berhasil disalin!`)
  } catch (err) {
    showToast('error', 'Gagal menyalin undangan portal: ' + err.message)
  }
}

// ─── Toggle Payout Status ─────────────────────────────────────────────────────

async function togglePayoutStatus(tenant) {
  const next = tenant.payout_status === 'PENDING' ? 'SETTLED' : 'PENDING'
  const { error } = await supabase
    .from('tenants')
    .update({ payout_status: next })
    .eq('id', tenant.id)
  if (!error) {
    const idx = tenants.value.findIndex((t) => t.id === tenant.id)
    if (idx !== -1) tenants.value[idx].payout_status = next
  }
}

// ─── Edit Existing Event Settings & Sync Share ────────────────────────────────

const showEditEventForm = ref(false)
const editEventForm = ref({
  name: '',
  venue: '',
  event_dates: '',
  venue_share_percent: 10,
  organizer_share_percent: 0,
  status: 'ACTIVE',
  syncTenants: true,
})
const editStartDate = ref(todayStr)
const editEndDate = ref(todayStr)
const editDateChanged = ref(false)
const savingEditEvent = ref(false)
const editEventError = ref('')

const editEventTotalCut = computed(() => {
  return Number(editEventForm.value.venue_share_percent || 0) + Number(editEventForm.value.organizer_share_percent || 0)
})
const editEventTenantTakeHome = computed(() => {
  return Math.max(0, 100 - editEventTotalCut.value)
})

function openEditEvent() {
  if (!selectedEvent.value) return
  editEventError.value = ''
  showCreateEventForm.value = false
  editDateChanged.value = false
  editEventForm.value = {
    name: selectedEvent.value.name || '',
    venue: selectedEvent.value.venue || '',
    event_dates: selectedEvent.value.event_dates || '',
    venue_share_percent: Number(selectedEvent.value.venue_share_percent ?? 10),
    organizer_share_percent: Number(selectedEvent.value.organizer_share_percent ?? 0),
    status: selectedEvent.value.status || (selectedEvent.value.is_active === false ? 'COMPLETED' : 'ACTIVE'),
    syncTenants: true,
  }
  editStartDate.value = todayStr
  editEndDate.value = todayStr
  showEditEventForm.value = !showEditEventForm.value
}

async function saveEditEvent() {
  editEventError.value = ''
  if (!editEventForm.value.name.trim()) {
    editEventError.value = 'Event name is required.'
    return
  }

  savingEditEvent.value = true
  const venueShare = Number(editEventForm.value.venue_share_percent ?? 10)
  const orgShare = Number(editEventForm.value.organizer_share_percent ?? 0)
  const totalShare = venueShare + orgShare
  const finalDates = editDateChanged.value
    ? formatEventDates(editStartDate.value, editEndDate.value)
    : (editEventForm.value.event_dates || '')
  const finalStatus = editEventForm.value.status || 'ACTIVE'

  const { data: updatedEvent, error: evError } = await supabase
    .from('events')
    .update({
      name: editEventForm.value.name.trim(),
      venue: editEventForm.value.venue.trim(),
      event_dates: finalDates,
      venue_share_percent: venueShare,
      organizer_share_percent: orgShare,
      default_share_percent: totalShare,
      status: finalStatus,
      is_active: finalStatus === 'ACTIVE',
    })
    .eq('id', selectedEventId.value)
    .select()
    .single()

  if (evError) {
    savingEditEvent.value = false
    editEventError.value = evError.message
    return
  }

  const idx = events.value.findIndex((e) => e.id === selectedEventId.value)
  if (idx !== -1) {
    events.value[idx] = updatedEvent
  }

  if (editEventForm.value.syncTenants && tenants.value.length > 0) {
    const { error: syncError } = await supabase
      .from('tenants')
      .update({
        venue_share_percent: venueShare,
        organizer_share_percent: orgShare,
        share_percent: totalShare,
      })
      .eq('event_id', selectedEventId.value)

    if (syncError) {
      console.error('Tenant sync error:', syncError)
    } else {
      await fetchTenants(selectedEventId.value)
    }
  }

  savingEditEvent.value = false
  showEditEventForm.value = false
  showToast('success', `Pengaturan event "${updatedEvent.name}" berhasil disimpan!`)
}

const togglingEventStatus = ref(false)
async function toggleEventStatus(ev) {
  if (!ev || togglingEventStatus.value) return
  const currentStatus = ev.status || (ev.is_active === false ? 'COMPLETED' : 'ACTIVE')
  const newStatus = currentStatus === 'ACTIVE' ? 'COMPLETED' : 'ACTIVE'
  togglingEventStatus.value = true
  try {
    const { data, error } = await supabase
      .from('events')
      .update({
        status: newStatus,
        is_active: newStatus === 'ACTIVE',
      })
      .eq('id', ev.id)
      .select()
      .single()

    if (error) throw error

    const idx = events.value.findIndex((e) => e.id === ev.id)
    if (idx !== -1) {
      events.value[idx] = { ...events.value[idx], ...data, status: newStatus, is_active: newStatus === 'ACTIVE' }
    }
    const label = newStatus === 'ACTIVE' ? 'diaktifkan kembali' : 'ditandai selesai'
    showToast('success', `Event "${ev.name}" berhasil ${label}!`)
  } catch (err) {
    showToast('error', `Gagal mengubah status event: ${err.message}`)
  } finally {
    togglingEventStatus.value = false
  }
}

// ─── Quick Per-Tenant Share Override Edit ─────────────────────────────────────

const editingTenantModal = ref(false)
const editingTenant = ref(null)
const editTenantCategory = ref('Food & Beverage')
const editTenantCustomCategory = ref('')
const savingEditTenant = ref(false)
const editTenantError = ref('')

const editTenantTotalCut = computed(() => {
  if (!editingTenant.value) return 0
  return Number(editingTenant.value.venue_share_percent || 0) + Number(editingTenant.value.organizer_share_percent || 0)
})
const editTenantTakeHome = computed(() => {
  return Math.max(0, 100 - editTenantTotalCut.value)
})

function openEditTenant(tenant) {
  editTenantError.value = ''
  editingTenant.value = {
    id: tenant.id,
    name: tenant.name || '',
    booth_number: tenant.booth_number || '',
    bank_info: tenant.bank_info || '',
    venue_share_percent: Number(tenant.venue_share_percent ?? 10),
    organizer_share_percent: Number(tenant.organizer_share_percent ?? 0),
  }

  if (PRESET_CATEGORIES.includes(tenant.category)) {
    editTenantCategory.value = tenant.category
    editTenantCustomCategory.value = ''
  } else if (tenant.category) {
    editTenantCategory.value = 'Other (Custom)'
    editTenantCustomCategory.value = tenant.category
  } else {
    editTenantCategory.value = 'Food & Beverage'
    editTenantCustomCategory.value = ''
  }

  editingTenantModal.value = true
}

function closeEditTenantModal() {
  editingTenantModal.value = false
  editingTenant.value = null
}

async function saveEditTenant() {
  if (!editingTenant.value) return
  editTenantError.value = ''
  const trimmedName = editingTenant.value.name.trim()

  if (!trimmedName) {
    editTenantError.value = 'Nama tenant tidak boleh kosong.'
    return
  }

  // 1. Validasi Brand duplikat di event ini (kecuali booth ini sendiri)
  const isDuplicateBrand = tenants.value.some(
    (t) => t.id !== editingTenant.value.id && (t.name || '').trim().toLowerCase() === trimmedName.toLowerCase()
  )
  if (isDuplicateBrand) {
    const errorMsg = `Brand "${trimmedName}" sudah terdaftar pada booth lain di event ini.`
    editTenantError.value = errorMsg
    showToast('error', errorMsg)
    return
  }

  // 2. Validasi Nomor/Kode Booth duplikat di event ini (kecuali booth ini sendiri, jika diisi)
  const trimmedBooth = (editingTenant.value.booth_number || '').trim()
  if (trimmedBooth) {
    const isDuplicateBooth = tenants.value.some(
      (t) => t.id !== editingTenant.value.id && (t.booth_number || '').trim().toLowerCase() === trimmedBooth.toLowerCase()
    )
    if (isDuplicateBooth) {
      const errorMsg = `Nomor/Kode Booth "${trimmedBooth}" sudah digunakan oleh booth lain di event ini.`
      editTenantError.value = errorMsg
      showToast('error', errorMsg)
      return
    }
  }

  const finalCategory = editTenantCategory.value === 'Other (Custom)'
    ? editTenantCustomCategory.value.trim()
    : editTenantCategory.value

  if (!finalCategory) {
    editTenantError.value = 'Kategori tenant harus diisi.'
    return
  }

  savingEditTenant.value = true
  const venueShare = Number(editingTenant.value.venue_share_percent ?? 10)
  const orgShare = Number(editingTenant.value.organizer_share_percent ?? 0)
  const totalShare = venueShare + orgShare

  const { data, error } = await supabase
    .from('tenants')
    .update({
      name: editingTenant.value.name.trim(),
      booth_number: editingTenant.value.booth_number.trim(),
      category: finalCategory,
      bank_info: editingTenant.value.bank_info.trim(),
      venue_share_percent: venueShare,
      organizer_share_percent: orgShare,
      share_percent: totalShare,
    })
    .eq('id', editingTenant.value.id)
    .select()
    .single()

  savingEditTenant.value = false

  if (error) {
    editTenantError.value = error.message
    return
  }

  const idx = tenants.value.findIndex((t) => t.id === data.id)
  if (idx !== -1) {
    tenants.value[idx] = data
  }
  closeEditTenantModal()
}

// ─── Toast & Notifications ───────────────────────────────────────────────────

const lineupError = ref('')
const toast = ref({
  show: false,
  type: 'info',
  message: '',
  timer: null,
})

function showToast(type, message, duration = 4000) {
  if (toast.value.timer) clearTimeout(toast.value.timer)
  toast.value = {
    show: true,
    type,
    message,
    timer: setTimeout(() => {
      toast.value.show = false
    }, duration),
  }
}

async function removeTenantFromLineup(tenant) {
  lineupError.value = ''
  if (!confirm(`Hapus tenant "${tenant.name}" dari lineup event ini?`)) return

  try {
    // 1. Query transaction_items for this tenant joined with transactions(id, status)
    const { data: linkedItems, error: fetchErr } = await supabase
      .from('transaction_items')
      .select(`
        id,
        transaction_id,
        transactions (
          id,
          status
        )
      `)
      .eq('tenant_id', tenant.id)

    if (fetchErr) throw fetchErr

    const items = linkedItems || []

    // 2. Check if there are any items belonging to active/non-void transactions
    const activeItems = items.filter((item) => {
      const status = item.transactions?.status
      return status !== 'VOID' && status !== 'VOIDED'
    })

    // If active transactions exist, block deletion with clear error message
    if (activeItems.length > 0) {
      const msg = 'Tidak dapat menghapus tenant karena masih memiliki transaksi aktif di event ini (void transaksi terkait terlebih dahulu).'
      lineupError.value = msg
      showToast('error', msg, 6500)
      return
    }

    // 3. If ALL linked transactions are VOID (0 active transactions): clean up voided items & empty headers
    if (items.length > 0) {
      const itemIdsToDelete = items.map((item) => item.id)
      const candidateTxIds = [...new Set(items.map((item) => item.transaction_id).filter(Boolean))]

      // Delete the voided transaction_items rows belonging to this tenant_id
      const { error: delItemsErr } = await supabase
        .from('transaction_items')
        .delete()
        .in('id', itemIdsToDelete)

      if (delItemsErr) throw delItemsErr

      // Check if any of those parent VOID transactions now have 0 remaining transaction_items
      if (candidateTxIds.length > 0) {
        const { data: remainingItems, error: remErr } = await supabase
          .from('transaction_items')
          .select('transaction_id')
          .in('transaction_id', candidateTxIds)

        if (!remErr && remainingItems) {
          const remainingTxSet = new Set(remainingItems.map((r) => r.transaction_id))
          const emptyTxIds = candidateTxIds.filter((id) => !remainingTxSet.has(id))
          if (emptyTxIds.length > 0) {
            await supabase
              .from('transactions')
              .delete()
              .in('id', emptyTxIds)
          }
        }
      }
    }

    // 4. Proceed to delete the tenants row from the lineup cleanly
    const { error: delTenantErr } = await supabase
      .from('tenants')
      .delete()
      .eq('id', tenant.id)

    if (delTenantErr) {
      if (delTenantErr.code === '23503') {
        const msg = 'Tidak dapat menghapus tenant karena masih memiliki referensi transaksi di event ini.'
        lineupError.value = msg
        showToast('error', msg, 6500)
        return
      }
      throw delTenantErr
    }

    // 5. Update reactive state & synchronize
    tenants.value = tenants.value.filter((t) => t.id !== tenant.id)
    allTenantsList.value = allTenantsList.value.filter((t) => t.id !== tenant.id)
    showToast('success', 'Tenant berhasil dihapus dari lineup.')
    await fetchMasterTenants()
    if (selectedEventId.value) {
      await fetchTransactionItems(selectedEventId.value)
    }
  } catch (err) {
    console.error('Error removing tenant:', err)
    const msg = `Gagal menghapus tenant: ${err.message}`
    lineupError.value = msg
    showToast('error', msg, 5000)
  }
}

// ─── Master Tenants Directory (Standalone Brand DB) ───────────────────────────

const masterTenants = ref([])
const allTenantsList = ref([])
const loadingMasterTenants = ref(false)
const masterSearchQuery = ref('')
const masterCategoryFilter = ref('ALL')
let masterRealtimeChannel = null

function subscribeMasterRealtime() {
  if (masterRealtimeChannel) {
    try {
      supabase.removeChannel(masterRealtimeChannel)
    } catch (err) {
      console.warn('[Master Realtime] Cleanup error:', err)
    }
    masterRealtimeChannel = null
  }
  const uniqueTopic = `admin-master-tenants-sync:${Date.now()}_${Math.random().toString(36).slice(2, 7)}`
  masterRealtimeChannel = supabase
    .channel(uniqueTopic)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'master_tenants' },
      () => { fetchMasterTenants() }
    )
    .subscribe((status, err) => {
      if (err) console.warn('[Master Realtime] Subscription status:', status, err)
    })
}

async function fetchMasterTenants() {
  loadingMasterTenants.value = true
  const [masterRes, tenantsRes] = await Promise.all([
    supabase.from('master_tenants').select('*').order('name', { ascending: true }),
    supabase.from('tenants').select('id, name, master_tenant_id, event_id, created_at, events(id, name)').order('created_at', { ascending: false }),
  ])
  loadingMasterTenants.value = false

  if (!masterRes.error && masterRes.data) {
    const allHistoricalTenants = tenantsRes.data || []
    allTenantsList.value = allHistoricalTenants
    masterTenants.value = masterRes.data.map((m) => {
      // Find latest event this brand participated in
      const lastTenant = allHistoricalTenants.find(
        (t) => (t.master_tenant_id && t.master_tenant_id === m.id) ||
               (t.name && t.name.toLowerCase().trim() === m.name.toLowerCase().trim())
      )
      return {
        ...m,
        lastEventName: lastTenant?.events?.name || null,
      }
    })
  } else if (masterRes.data) {
    masterTenants.value = masterRes.data
  }
}

function normalizeInstagram(handle) {
  if (!handle) return ''
  return handle.trim().replace(/^@+/, '')
}

function composeBankInfo(bankName, bankAccount, bankHolder, fallback = '') {
  const parts = []
  if (bankName?.trim()) parts.push(bankName.trim())
  if (bankAccount?.trim()) parts.push(bankAccount.trim())
  if (bankHolder?.trim()) parts.push(`a.n. ${bankHolder.trim()}`)
  return parts.length > 0 ? parts.join(' ') : (fallback?.trim() || '')
}

function composeContactInfo(picName, whatsapp, instagram, fallback = '') {
  const parts = []
  if (picName?.trim()) parts.push(picName.trim())
  if (whatsapp?.trim()) parts.push(`WA: ${whatsapp.trim()}`)
  if (instagram?.trim()) parts.push(`IG: @${normalizeInstagram(instagram)}`)
  return parts.length > 0 ? parts.join(' • ') : (fallback?.trim() || '')
}

const masterCategoriesWithCounts = computed(() => {
  const allCount = masterTenants.value.length
  const pills = [
    { key: 'ALL', label: 'Semua Brand', count: allCount }
  ]
  const baseCategories = PRESET_CATEGORIES.filter((c) => c !== 'Other (Custom)')
  const categoryOrder = [...baseCategories]
  masterTenants.value.forEach((m) => {
    if (m.category && !categoryOrder.includes(m.category)) {
      categoryOrder.push(m.category)
    }
  })

  for (const cat of categoryOrder) {
    const count = masterTenants.value.filter((m) => m.category === cat).length
    pills.push({
      key: cat,
      label: cat,
      count
    })
  }

  return pills
})

const filteredMasterTenants = computed(() => {
  let list = masterTenants.value
  if (masterCategoryFilter.value !== 'ALL') {
    list = list.filter((m) => m.category === masterCategoryFilter.value)
  }
  if (masterSearchQuery.value.trim()) {
    const q = masterSearchQuery.value.toLowerCase().trim()
    list = list.filter((m) =>
      (m.name && m.name.toLowerCase().includes(q)) ||
      (m.category && m.category.toLowerCase().includes(q)) ||
      (m.instagram && m.instagram.toLowerCase().includes(q)) ||
      (m.pic_name && m.pic_name.toLowerCase().includes(q)) ||
      (m.whatsapp && m.whatsapp.toLowerCase().includes(q)) ||
      (m.bank_name && m.bank_name.toLowerCase().includes(q)) ||
      (m.bank_account && m.bank_account.toLowerCase().includes(q)) ||
      (m.bank_holder && m.bank_holder.toLowerCase().includes(q)) ||
      (m.contact_info && m.contact_info.toLowerCase().includes(q)) ||
      (m.bank_info && m.bank_info.toLowerCase().includes(q))
    )
  }
  return list
})

// Add Master Tenant
const showAddMasterModal = ref(false)
const newMasterTenant = ref({
  name: '',
  category: 'Food & Beverage',
  customCategory: '',
  instagram: '',
  pic_name: '',
  whatsapp: '',
  bank_name: '',
  bank_account: '',
  bank_holder: '',
  contact_info: '',
  bank_info: '',
})
const creatingMaster = ref(false)
const createMasterError = ref('')

function openAddMasterModal() {
  createMasterError.value = ''
  newMasterTenant.value = {
    name: '',
    category: 'Food & Beverage',
    customCategory: '',
    instagram: '',
    pic_name: '',
    whatsapp: '',
    bank_name: '',
    bank_account: '',
    bank_holder: '',
    contact_info: '',
    bank_info: '',
  }
  showAddMasterModal.value = true
}

async function createMasterTenant() {
  createMasterError.value = ''
  const trimmedName = newMasterTenant.value.name.trim()
  if (!trimmedName) {
    createMasterError.value = 'Brand name is required.'
    return
  }

  // Anti-duplicate brand name validation (case-insensitive, trim spasi)
  const isDuplicate = masterTenants.value.some(
    (m) => (m.name || '').trim().toLowerCase() === trimmedName.toLowerCase()
  )
  if (isDuplicate) {
    const errorMsg = `Brand dengan nama "${trimmedName}" sudah terdaftar di Database Brand.`
    createMasterError.value = errorMsg
    showToast('error', errorMsg)
    return
  }

  const finalCategory = newMasterTenant.value.category === 'Other (Custom)'
    ? newMasterTenant.value.customCategory.trim()
    : newMasterTenant.value.category
  if (!finalCategory) {
    createMasterError.value = 'Category is required.'
    return
  }

  const cleanIg = normalizeInstagram(newMasterTenant.value.instagram)
  const pic = newMasterTenant.value.pic_name?.trim() || ''
  const wa = newMasterTenant.value.whatsapp?.trim() || ''
  const bName = newMasterTenant.value.bank_name?.trim() || ''
  const bAcc = newMasterTenant.value.bank_account?.trim() || ''
  const bHolder = newMasterTenant.value.bank_holder?.trim() || ''
  const composedBank = composeBankInfo(bName, bAcc, bHolder, newMasterTenant.value.bank_info)
  const composedContact = composeContactInfo(pic, wa, cleanIg, newMasterTenant.value.contact_info)

  creatingMaster.value = true
  const { data, error } = await supabase
    .from('master_tenants')
    .insert([
      {
        name: newMasterTenant.value.name.trim(),
        category: finalCategory,
        instagram: cleanIg || null,
        pic_name: pic || null,
        whatsapp: wa || null,
        bank_name: bName || null,
        bank_account: bAcc || null,
        bank_holder: bHolder || null,
        bank_info: composedBank || null,
        contact_info: composedContact || null,
      }
    ])
    .select()
    .single()
  creatingMaster.value = false

  if (error) {
    createMasterError.value = error.message
    return
  }

  masterTenants.value.push(data)
  masterTenants.value.sort((a, b) => a.name.localeCompare(b.name))
  showAddMasterModal.value = false
}

// Edit Master Tenant
const editingMasterModal = ref(false)
const editingMasterTenant = ref(null)
const editMasterCategory = ref('Food & Beverage')
const editMasterCustomCategory = ref('')
const savingMaster = ref(false)
const editMasterError = ref('')

function openEditMasterModal(mt) {
  editMasterError.value = ''
  editingMasterTenant.value = {
    id: mt.id,
    name: mt.name || '',
    instagram: mt.instagram || '',
    pic_name: mt.pic_name || '',
    whatsapp: mt.whatsapp || '',
    bank_name: mt.bank_name || '',
    bank_account: mt.bank_account || '',
    bank_holder: mt.bank_holder || '',
    contact_info: mt.contact_info || '',
    bank_info: mt.bank_info || '',
  }
  if (PRESET_CATEGORIES.includes(mt.category)) {
    editMasterCategory.value = mt.category
    editMasterCustomCategory.value = ''
  } else if (mt.category) {
    editMasterCategory.value = 'Other (Custom)'
    editMasterCustomCategory.value = mt.category
  } else {
    editMasterCategory.value = 'Food & Beverage'
    editMasterCustomCategory.value = ''
  }
  editingMasterModal.value = true
}

async function saveEditMasterTenant() {
  if (!editingMasterTenant.value) return
  editMasterError.value = ''
  const trimmedName = editingMasterTenant.value.name.trim()
  if (!trimmedName) {
    editMasterError.value = 'Brand name is required.'
    return
  }

  // Anti-duplicate brand name validation (excluding self, case-insensitive, trim spasi)
  const isDuplicate = masterTenants.value.some(
    (m) => m.id !== editingMasterTenant.value.id && (m.name || '').trim().toLowerCase() === trimmedName.toLowerCase()
  )
  if (isDuplicate) {
    const errorMsg = `Brand dengan nama "${trimmedName}" sudah digunakan oleh brand lain di Database Brand.`
    editMasterError.value = errorMsg
    showToast('error', errorMsg)
    return
  }

  const finalCategory = editMasterCategory.value === 'Other (Custom)'
    ? editMasterCustomCategory.value.trim()
    : editMasterCategory.value
  if (!finalCategory) {
    editMasterError.value = 'Category is required.'
    return
  }

  const cleanIg = normalizeInstagram(editingMasterTenant.value.instagram)
  const pic = editingMasterTenant.value.pic_name?.trim() || ''
  const wa = editingMasterTenant.value.whatsapp?.trim() || ''
  const bName = editingMasterTenant.value.bank_name?.trim() || ''
  const bAcc = editingMasterTenant.value.bank_account?.trim() || ''
  const bHolder = editingMasterTenant.value.bank_holder?.trim() || ''
  const composedBank = composeBankInfo(bName, bAcc, bHolder, editingMasterTenant.value.bank_info)
  const composedContact = composeContactInfo(pic, wa, cleanIg, editingMasterTenant.value.contact_info)

  savingMaster.value = true
  const { data, error } = await supabase
    .from('master_tenants')
    .update({
      name: editingMasterTenant.value.name.trim(),
      category: finalCategory,
      instagram: cleanIg || null,
      pic_name: pic || null,
      whatsapp: wa || null,
      bank_name: bName || null,
      bank_account: bAcc || null,
      bank_holder: bHolder || null,
      bank_info: composedBank || null,
      contact_info: composedContact || null,
    })
    .eq('id', editingMasterTenant.value.id)
    .select()
    .single()
  savingMaster.value = false

  if (error) {
    editMasterError.value = error.message
    return
  }

  // Sync updated bank_info to linked tenants rows in active event lineup if empty or matching previous master value
  if (selectedEventId.value && composedBank) {
    try {
      await supabase
        .from('tenants')
        .update({ bank_info: composedBank })
        .eq('event_id', selectedEventId.value)
        .eq('master_tenant_id', data.id)

      tenants.value.forEach((t) => {
        if (t.master_tenant_id === data.id) {
          t.bank_info = composedBank
        }
      })
    } catch (e) {
      console.warn('Could not sync bank info to active event tenants:', e)
    }
  }

  const idx = masterTenants.value.findIndex((m) => m.id === data.id)
  if (idx !== -1) {
    masterTenants.value[idx] = {
      ...masterTenants.value[idx],
      ...data,
    }
  }
  editingMasterModal.value = false
}

async function deleteMasterTenant(mt) {
  if (!confirm(`Hapus brand "${mt.name}" dari Master Directory? Riwayat event sebelumnya tetap tersimpan.`)) return
  const { error } = await supabase
    .from('master_tenants')
    .delete()
    .eq('id', mt.id)
  if (!error) {
    masterTenants.value = masterTenants.value.filter((m) => m.id !== mt.id)
  }
}

// Quick Assign Single Master Tenant to Event (from Tab 3)
const assigningMasterModal = ref(false)
const targetMasterTenant = ref(null)
const assignTargetEventId = ref('')
const assignBoothNumber = ref('')
const assigningToActiveEvent = ref(false)
const assignMasterError = ref('')

const assignTargetEvent = computed(() => {
  return events.value.find((e) => e.id === assignTargetEventId.value) || null
})

const isBrandAlreadyInTargetEvent = computed(() => {
  if (!targetMasterTenant.value || !assignTargetEventId.value) return false
  const targetName = targetMasterTenant.value.name.toLowerCase().trim()
  const targetMasterId = targetMasterTenant.value.id

  if (assignTargetEventId.value === selectedEventId.value) {
    return tenants.value.some(
      (t) => (t.master_tenant_id && t.master_tenant_id === targetMasterId) ||
             (t.name && t.name.toLowerCase().trim() === targetName)
    )
  }

  return allTenantsList.value.some(
    (t) => t.event_id === assignTargetEventId.value &&
           ((t.master_tenant_id && t.master_tenant_id === targetMasterId) ||
            (t.name && t.name.toLowerCase().trim() === targetName))
  )
})

function openAssignSingleMasterModal(mt) {
  targetMasterTenant.value = mt
  assignTargetEventId.value = selectedEventId.value || events.value[0]?.id || ''
  assignBoothNumber.value = ''
  assignMasterError.value = ''
  assigningMasterModal.value = true
}

async function confirmAssignMasterToActiveEvent() {
  if (!targetMasterTenant.value || !assignTargetEventId.value) return
  assignMasterError.value = ''

  // 1. Anti-duplicate brand check in target event
  if (isBrandAlreadyInTargetEvent.value) {
    const errorMsg = `Brand "${targetMasterTenant.value.name}" sudah terdaftar di lineup event terpilih.`
    assignMasterError.value = errorMsg
    showToast('error', errorMsg)
    return
  }

  // 2. Anti-duplicate booth number check in target event (if provided)
  const trimmedBooth = assignBoothNumber.value.trim()
  if (trimmedBooth) {
    const targetBooths = assignTargetEventId.value === selectedEventId.value
      ? tenants.value
      : allTenantsList.value.filter(t => t.event_id === assignTargetEventId.value)

    const isDuplicateBooth = targetBooths.some(
      (t) => (t.booth_number || '').trim().toLowerCase() === trimmedBooth.toLowerCase()
    )
    if (isDuplicateBooth) {
      const errorMsg = `Nomor/Kode Booth "${trimmedBooth}" sudah digunakan oleh booth lain di event terpilih.`
      assignMasterError.value = errorMsg
      showToast('error', errorMsg)
      return
    }
  }

  assigningToActiveEvent.value = true

  const targetEv = assignTargetEvent.value
  const venueShare = Number(targetEv?.venue_share_percent ?? 10)
  const orgShare = Number(targetEv?.organizer_share_percent ?? 0)
  const totalShare = venueShare + orgShare

  const { data, error } = await supabase
    .from('tenants')
    .insert([
      {
        event_id: assignTargetEventId.value,
        master_tenant_id: targetMasterTenant.value.id,
        name: targetMasterTenant.value.name,
        category: targetMasterTenant.value.category || 'Food & Beverage',
        booth_number: assignBoothNumber.value.trim(),
        bank_info: targetMasterTenant.value.bank_info || '',
        venue_share_percent: venueShare,
        organizer_share_percent: orgShare,
        share_percent: totalShare,
        payout_status: 'PENDING',
      }
    ])
    .select()
    .single()

  assigningToActiveEvent.value = false

  if (error) {
    assignMasterError.value = error.message
    return
  }

  allTenantsList.value.unshift(data)

  const wasDifferentEvent = selectedEventId.value !== assignTargetEventId.value

  if (!wasDifferentEvent) {
    tenants.value.push(data)
    showToast('success', `Brand "${targetMasterTenant.value.name}" berhasil ditugaskan ke lineup "${targetEv.name}"!`)
  } else {
    // Switch active event smoothly to target event
    selectedEventId.value = assignTargetEventId.value
    showToast('success', `Brand "${targetMasterTenant.value.name}" berhasil ditugaskan ke "${targetEv.name}". Event aktif dialihkan ke event tersebut.`)
  }

  await fetchMasterTenants()
  assigningMasterModal.value = false
}

// Assign Multiple from Master Tenant (from Tab 2 Lineup)
const showAssignLineupModal = ref(false)
const selectedMasterIds = ref(new Set())
const lineupAssignBooths = ref({})
const assigningLineup = ref(false)
const assignLineupSearch = ref('')
const assignLineupCategory = ref('ALL')

const activeEventTenantNames = computed(() => {
  return new Set(tenants.value.map((t) => t.name.toLowerCase().trim()))
})

const activeEventMasterIds = computed(() => {
  return new Set(tenants.value.map((t) => t.master_tenant_id).filter(Boolean))
})

const filteredLineupMasterTenants = computed(() => {
  let list = masterTenants.value
  if (assignLineupCategory.value !== 'ALL') {
    list = list.filter((m) => m.category === assignLineupCategory.value)
  }
  if (assignLineupSearch.value.trim()) {
    const q = assignLineupSearch.value.toLowerCase().trim()
    list = list.filter((m) =>
      m.name.toLowerCase().includes(q) ||
      (m.category && m.category.toLowerCase().includes(q))
    )
  }
  return list
})

function openAssignLineupModal() {
  selectedMasterIds.value = new Set()
  lineupAssignBooths.value = {}
  assignLineupSearch.value = ''
  assignLineupCategory.value = 'ALL'
  showAssignLineupModal.value = true
  fetchMasterTenants()
}

function toggleSelectMaster(m) {
  const isAlreadyInEvent = activeEventMasterIds.value.has(m.id) || activeEventTenantNames.value.has(m.name.toLowerCase().trim())
  if (isAlreadyInEvent) return

  if (selectedMasterIds.value.has(m.id)) {
    selectedMasterIds.value.delete(m.id)
  } else {
    selectedMasterIds.value.add(m.id)
    if (!lineupAssignBooths.value[m.id]) {
      lineupAssignBooths.value[m.id] = ''
    }
  }
}

function toggleSelectAllLineupMasters() {
  const selectable = filteredLineupMasterTenants.value.filter(
    (m) => !activeEventMasterIds.value.has(m.id) && !activeEventTenantNames.value.has(m.name.toLowerCase().trim())
  )
  const allSelected = selectable.length > 0 && selectable.every((m) => selectedMasterIds.value.has(m.id))
  if (allSelected) {
    selectable.forEach((m) => selectedMasterIds.value.delete(m.id))
  } else {
    selectable.forEach((m) => {
      selectedMasterIds.value.add(m.id)
      if (!lineupAssignBooths.value[m.id]) {
        lineupAssignBooths.value[m.id] = ''
      }
    })
  }
}

async function confirmAssignMastersToLineup() {
  if (selectedMasterIds.value.size === 0 || !selectedEventId.value) return

  // 1. Check if any selected brand is already registered in active event
  const existingBrandNames = new Set(tenants.value.map(t => (t.name || '').trim().toLowerCase()))
  const existingMasterIds = new Set(tenants.value.map(t => t.master_tenant_id).filter(Boolean))

  for (const masterId of selectedMasterIds.value) {
    const master = masterTenants.value.find((m) => m.id === masterId)
    if (!master) continue
    const masterNameLower = (master.name || '').trim().toLowerCase()
    if (existingMasterIds.has(master.id) || existingBrandNames.has(masterNameLower)) {
      const errorMsg = `Brand "${master.name}" sudah terdaftar di lineup event ini.`
      showToast('error', errorMsg)
      return
    }
  }

  // 2. Check booth number duplicates (both against existing event booths and between newly assigned booths)
  const existingBoothNumbers = new Set(
    tenants.value
      .map(t => (t.booth_number || '').trim().toLowerCase())
      .filter(Boolean)
  )
  const newBatchBooths = new Set()

  for (const masterId of selectedMasterIds.value) {
    const rawBooth = (lineupAssignBooths.value[masterId] || '').trim()
    if (rawBooth) {
      const lowerBooth = rawBooth.toLowerCase()
      if (existingBoothNumbers.has(lowerBooth)) {
        const errorMsg = `Nomor/Kode Booth "${rawBooth}" sudah digunakan oleh booth lain di event ini.`
        showToast('error', errorMsg)
        return
      }
      if (newBatchBooths.has(lowerBooth)) {
        const errorMsg = `Nomor/Kode Booth "${rawBooth}" dimasukkan lebih dari sekali dalam penugasan ini.`
        showToast('error', errorMsg)
        return
      }
      newBatchBooths.add(lowerBooth)
    }
  }

  assigningLineup.value = true

  const venueShare = Number(selectedEvent.value?.venue_share_percent ?? 10)
  const orgShare = Number(selectedEvent.value?.organizer_share_percent ?? 0)
  const totalShare = venueShare + orgShare

  const rows = []
  for (const masterId of selectedMasterIds.value) {
    const master = masterTenants.value.find((m) => m.id === masterId)
    if (!master) continue
    rows.push({
      event_id: selectedEventId.value,
      master_tenant_id: master.id,
      name: master.name,
      category: master.category || 'Food & Beverage',
      booth_number: (lineupAssignBooths.value[masterId] || '').trim(),
      bank_info: master.bank_info || '',
      venue_share_percent: venueShare,
      organizer_share_percent: orgShare,
      share_percent: totalShare,
      payout_status: 'PENDING',
    })
  }

  const { data, error } = await supabase
    .from('tenants')
    .insert(rows)
    .select()

  assigningLineup.value = false

  if (!error && data) {
    tenants.value.push(...data)
    showAssignLineupModal.value = false
    selectedMasterIds.value.clear()
    lineupAssignBooths.value = {}
    fetchMasterTenants()
  }
}

// ─── PDF Settlement Export ───────────────────────────────────────────────────

function exportAllPdf() {
  if (!selectedEvent.value) return
  generateEventSettlementPdf({
    event: selectedEvent.value,
    summary: {
      totalGross: totalGross.value,
      totalVenueCut: totalVenueCut.value,
      totalOrganizerCut: totalOrganizerCut.value,
      totalTenantNet: totalTenantNet.value,
      totalQris: paymentBreakdown.value.qrisTotal,
      totalCash: paymentBreakdown.value.cashTotal,
    },
    paymentBreakdown: paymentBreakdown.value,
    tenantRows: settlementRows.value,
  })
  showToast('success', 'Laporan Settlement Event PDF berhasil diunduh.')
}

function exportTenantPdf(row) {
  if (!selectedEvent.value) return
  generateTenantSettlementPdf({
    event: selectedEvent.value,
    tenantRow: row,
    tenantItems: row.items || [],
  })
  showToast('success', `Slip Settlement PDF untuk "${row.name}" berhasil diunduh.`)
}

// ─── WhatsApp Settlement Message ─────────────────────────────────────────────

const copiedWaId = ref(null)

async function copyTenantWaSummary(row) {
  if (!selectedEvent.value) return
  const ev = selectedEvent.value
  const evName = ev.name || 'Event Pop-up'
  const evDatesStr = ev.event_dates ? ` (*${ev.event_dates}*)` : ''
  const tenantName = row.name || 'Tenant'
  const boothStr = row.booth_number && row.booth_number !== '—'
    ? ` (Booth *${row.booth_number}*)`
    : ''
  const totalSharePct = Number(row.venue_share_percent ?? ev.venue_share_percent ?? 10) + Number(row.organizer_share_percent ?? ev.organizer_share_percent ?? 0)
  const combinedCut = Number(row.venueCut || 0) + Number(row.orgCut || 0)
  const bankStr = row.bank_info?.trim() || 'Belum diisi'
  const portalUrl = `${window.location.origin}/tenant/${row.access_token}`

  const msg = [
    `Halo *${tenantName}*${boothStr},`,
    `Berikut rekap hasil penjualan untuk event *${evName}*${evDatesStr}:`,
    ``,
    `• Total Penjualan Kotor: *${formatRupiah(row.gross)}*`,
    `• Potongan Bagi Hasil (${totalSharePct}%): *- ${formatRupiah(combinedCut)}*`,
    `• *Total Hak Bersih (Net): ${formatRupiah(row.net)}*`,
    ``,
    `Rekening Tujuan: *${bankStr}*`,
    `Status: *${row.payout_status || 'PENDING'}*`,
    ``,
    `Cek rincian transaksi lengkap di Portal Tenant:`,
    `${portalUrl}`,
    ``,
    `Terima kasih telah berpartisipasi! 🙏`,
  ].join('\n')

  try {
    await navigator.clipboard.writeText(msg)
    copiedWaId.value = row.id
    setTimeout(() => {
      if (copiedWaId.value === row.id) copiedWaId.value = null
    }, 2000)
    showToast('success', `Pesan settlement WhatsApp untuk ${tenantName} disalin!`)
  } catch (err) {
    showToast('error', 'Gagal menyalin pesan WhatsApp: ' + err.message)
  }
}
</script>

<template>
    <!-- ── 6-Digit PIN Lock Screen (when locked) ────────────────────────── -->
  <div
    v-if="!isUnlocked"
    class="min-h-screen bg-light-surface text-light-on-surface font-body flex flex-col items-center justify-center p-4 selection:bg-light-primary/20"
  >
    <div class="w-full max-w-sm flex flex-col items-center text-center">
      <!-- Shield / Lock Badge -->
      <div
        class="w-16 h-16 rounded-3xl bg-light-secondary-container border border-light-outline-variant flex items-center justify-center mb-5 text-light-primary shadow-xs"
      >
        <Lock class="w-7 h-7" />
      </div>

      <!-- Header Title & Subtitle -->
      <h1 class="text-2xl font-headline font-bold tracking-tight text-light-on-surface mb-1.5">
        PopUpPOS <span class="text-light-primary">Admin</span>
      </h1>
      <p class="text-xs font-body text-light-on-surface-variant max-w-[280px] leading-relaxed mb-6">
        Masukkan 6-digit PIN untuk akses dashboard event, settlements &amp; komisi
      </p>

      <!-- PIN Indicators (6 box indicators with glowing dots) -->
      <div
        :class="[
          'flex items-center justify-center gap-2.5 mb-2',
          isShaking ? 'animate-shake' : '',
        ]"
      >
        <div
          v-for="i in 6"
          :key="i"
          :class="[
            'w-11 h-12 rounded-xl border flex items-center justify-center transition-all duration-150',
            enteredPin.length >= i
              ? 'bg-light-primary/10 border-light-primary shadow-xs scale-105'
              : 'bg-light-surface-container-lowest border-light-outline-variant',
          ]"
        >
          <span
            v-if="enteredPin.length >= i"
            class="w-3 h-3 rounded-full bg-light-primary shadow-xs"
          />
        </div>
      </div>

      <!-- Error / Helper Message -->
      <div class="h-6 mb-5 flex items-center justify-center">
        <p v-if="pinError" class="text-xs font-semibold text-light-error">
          {{ pinError }}
        </p>
        <p v-else class="text-[11px] font-body text-light-on-surface-variant">
          Ketik langsung di keyboard atau gunakan keypad
        </p>
      </div>

      <!-- Touch-friendly 3x4 On-Screen Keypad -->
      <div class="grid grid-cols-3 gap-2.5 w-full max-w-[270px]">
        <button
          v-for="n in [1, 2, 3, 4, 5, 6, 7, 8, 9]"
          :key="n"
          type="button"
          @click="appendDigit(String(n))"
          class="h-14 rounded-2xl bg-light-surface-container-lowest hover:bg-light-surface-container active:scale-95 border border-light-outline-variant font-headline text-xl font-bold text-light-on-surface flex items-center justify-center transition-all duration-100 shadow-xs cursor-pointer touch-manipulation select-none"
        >
          {{ n }}
        </button>

        <!-- Clear Button -->
        <button
          type="button"
          @click="clearPin"
          class="h-14 rounded-2xl bg-light-surface-container-low hover:bg-light-surface-container active:scale-95 border border-light-outline-variant text-xs font-bold font-label text-light-on-surface-variant hover:text-light-on-surface flex items-center justify-center transition-all duration-100 uppercase tracking-wider cursor-pointer touch-manipulation select-none"
        >
          Clear
        </button>

        <!-- 0 Button -->
        <button
          type="button"
          @click="appendDigit('0')"
          class="h-14 rounded-2xl bg-light-surface-container-lowest hover:bg-light-surface-container active:scale-95 border border-light-outline-variant font-headline text-xl font-bold text-light-on-surface flex items-center justify-center transition-all duration-100 shadow-xs cursor-pointer touch-manipulation select-none"
        >
          0
        </button>

        <!-- Backspace Button -->
        <button
          type="button"
          @click="deleteDigit"
          class="h-14 rounded-2xl bg-light-surface-container-low hover:bg-light-surface-container active:scale-95 border border-light-outline-variant text-light-on-surface-variant hover:text-light-on-surface flex items-center justify-center transition-all duration-100 cursor-pointer touch-manipulation select-none"
          title="Hapus"
        >
          <Delete class="w-5 h-5" />
        </button>
      </div>

      <!-- Return to Cashier & Logout Links -->
      <div class="mt-8 flex items-center gap-2">
        <button
          type="button"
          @click="router.push('/')"
          class="flex items-center gap-2 text-xs font-label font-semibold text-light-on-surface-variant hover:text-light-on-surface bg-light-surface-container-lowest hover:bg-light-surface-container border border-light-outline-variant px-3.5 py-2 rounded-xl transition-colors cursor-pointer"
        >
          <ArrowLeft class="w-4 h-4 text-light-primary" />
          Kembali ke Kasir
        </button>
        <button
          type="button"
          @click="handleLogout"
          class="flex items-center gap-1.5 text-xs font-label font-semibold text-light-tertiary hover:bg-light-tertiary-container/30 bg-light-surface-container-lowest border border-light-outline-variant px-3 py-2 rounded-xl transition-colors cursor-pointer"
          title="Keluar dari akun staf"
        >
          <LogOut class="w-3.5 h-3.5" />
          Keluar
        </button>
      </div>
    </div>
  </div>

  <!-- ── Unlocked Admin Dashboard ──────────────────────────────────────── -->
  <div v-else class="min-h-screen bg-light-surface text-light-on-surface font-body">

    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8 space-y-6 sm:space-y-8 pb-24 sm:pb-12">
<!-- ════════════════════════════════════════════════════════════════
           TAB 1: OVERVIEW & SETTLEMENT
      ═════════════════════════════════════════════════════════════════ -->
      <div v-if="activeTab === 'overview'" class="flex flex-col gap-gutter-xl">
        <!-- ── Page Header & Controls ─────────────────────────────────── -->
        <header class="flex flex-wrap items-start justify-between gap-gutter-lg">
          <div class="min-w-0">
            <h1 class="font-headline text-headline-lg text-light-on-surface">Ringkasan &amp; Tutup Buku</h1>
            <p class="font-body text-body-md text-light-on-surface-variant mt-gutter-xs">Pantau omzet real-time dan bagikan laporan hasil penjualan ke setiap booth.</p>
          </div>

          <!-- Right-Aligned Action Bar -->
          <div class="flex flex-wrap items-center gap-gutter-sm shrink-0">
            <!-- Active Event Switcher Pill -->
            <div class="relative inline-flex items-center">
              <span class="material-symbols-outlined text-[18px] text-light-primary absolute left-3 pointer-events-none" style="font-variation-settings: 'FILL' 1;" aria-hidden="true">festival</span>
              <select
                v-model="selectedEventId"
                class="appearance-none pl-9 pr-8 py-2 rounded-md bg-light-secondary-container text-light-on-secondary-container border border-light-primary font-label text-label-md hover:bg-light-surface-variant transition-colors cursor-pointer focus:outline-none focus:ring-2 focus:ring-light-primary"
              >
                <option value="" disabled>-- Pilih Event --</option>
                <option v-for="ev in events" :key="ev.id" :value="ev.id">
                  {{ ev.name }} • {{ (ev.status === 'COMPLETED' || ev.is_active === false) ? 'COMPLETED' : 'ACTIVE' }}
                </option>
              </select>
              <span class="material-symbols-outlined text-[18px] text-light-on-secondary-container absolute right-2.5 pointer-events-none" aria-hidden="true">expand_more</span>
            </div>

            <!-- Export PDF Button -->
            <button
              v-if="selectedEventId"
              @click="exportAllPdf"
              type="button"
              class="inline-flex items-center gap-gutter-xs px-gutter-md py-2 rounded-md bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface hover:bg-light-surface-container-low transition-colors duration-state-change ease-state-change shrink-0 font-label text-label-md cursor-pointer"
            >
              <span class="material-symbols-outlined text-[18px] text-light-primary" aria-hidden="true">picture_as_pdf</span>
              <span class="font-label text-label-md">Export PDF</span>
            </button>

            <!-- Salin Rekap WA Button (Event-wide) -->
            <button
              v-if="selectedEventId"
              type="button"
              @click="() => {
                if (!selectedEvent) return;
                const lines = [
                  `*Rekap Hasil Penjualan - ${selectedEvent.name}*`,
                  selectedEvent.event_dates ? `Tanggal: ${selectedEvent.event_dates}` : '',
                  selectedEvent.venue ? `Venue: ${selectedEvent.venue}` : '',
                  ``,
                  `• Total Omzet Kotor: *${formatRupiah(totalGross)}* (${validTransactions.length} transaksi)`,
                  `• Hak Bersih Tenant: *${formatRupiah(totalTenantNet)}*`,
                  `• Bagian Venue: *${formatRupiah(totalVenueCut)}*`,
                  `• Bagian Organizer: *${formatRupiah(totalOrganizerCut)}*`,
                  ``,
                  `*Rekonsiliasi Pembayaran:*`,
                  `• QRIS Settlement: *${formatRupiah(paymentBreakdown.qrisTotal)}* (${paymentBreakdown.qrisCount} trx - ${paymentBreakdown.qrisPct}%)`,
                  `• Net Fisik Tunai: *${formatRupiah(paymentBreakdown.cashTotal)}* (${paymentBreakdown.cashCount} trx - ${paymentBreakdown.cashPct}%)`,
                  ``,
                  `*PopUpPOS System*`
                ].filter(Boolean).join('\n');
                navigator.clipboard.writeText(lines).then(() => {
                  showToast('success', 'Rekap event disalin untuk WhatsApp!');
                }).catch(err => {
                  showToast('error', 'Gagal menyalin: ' + err.message);
                });
              }"
              class="inline-flex items-center gap-gutter-xs px-gutter-md py-2 rounded-md bg-light-primary text-light-on-primary hover:bg-light-primary-container transition-colors duration-state-change ease-state-change shrink-0 font-label text-label-md cursor-pointer"
            >
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">chat</span>
              <span class="font-label text-label-md">Salin Rekap WA</span>
            </button>

            <!-- Kunci Admin Button -->
            <button
              @click="lockAdmin"
              type="button"
              class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md bg-light-surface-container-low hover:bg-light-surface-container text-light-on-surface-variant hover:text-light-on-surface border border-light-outline-variant font-label text-label-md transition-colors cursor-pointer shrink-0"
              title="Kunci sesi Admin"
            >
              <Lock class="w-4 h-4 text-light-primary" />
              <span class="hidden sm:inline">Kunci Admin</span>
            </button>
          </div>
        </header>

        <!-- Event Metadata Details Strip (when event selected) -->
        <div v-if="selectedEvent" class="flex flex-wrap items-center gap-2 text-xs">
          <span
            :class="(selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false)
              ? 'bg-light-tertiary-container text-light-on-tertiary-container border-light-tertiary'
              : 'bg-light-secondary-container text-light-primary border-light-primary'"
            class="px-2.5 py-1 rounded-md border font-label text-label-sm font-bold flex items-center gap-1.5"
          >
            <span class="w-1.5 h-1.5 rounded-full" :class="(selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false) ? 'bg-light-tertiary' : 'bg-light-primary'"></span>
            {{ (selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false) ? 'COMPLETED' : 'ACTIVE' }}
          </span>
          <span class="px-2.5 py-1 rounded-md bg-light-surface-container-low text-light-on-surface-variant border border-light-outline-variant font-label text-label-sm">
            Venue: <strong class="text-light-on-surface">{{ selectedEvent.venue || '—' }}</strong>
          </span>
          <span v-if="selectedEvent.event_dates" class="px-2.5 py-1 rounded-md bg-light-surface-container-low text-light-primary border border-light-outline-variant font-label text-label-sm">
            {{ selectedEvent.event_dates }}
          </span>
          <span v-if="loadingItems" class="flex items-center gap-1.5 text-xs text-light-on-surface-variant">
            <Loader2 class="w-3.5 h-3.5 animate-spin text-light-primary" />
            Memperbarui data realtime…
          </span>
        </div>

        <!-- ── If no event is selected ─────────────────────────────────── -->
        <div v-if="!selectedEventId" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant p-12 sm:p-16 text-center space-y-4">
          <CalendarCheck class="w-12 h-12 text-light-on-surface-variant mx-auto" />
          <div>
            <p class="font-headline text-headline-md font-bold text-light-on-surface">Pilih Event Terlebih Dahulu</p>
            <p class="font-body text-body-sm text-light-on-surface-variant mt-1">Silakan pilih event aktif di dropdown atas, atau buka tab Event &amp; Lineup untuk membuat event baru.</p>
          </div>
          <button
            @click="switchAdminTab('lineup', $event)"
            type="button"
            class="inline-flex items-center gap-2 bg-light-primary text-light-on-primary px-5 py-2.5 rounded-md font-label text-label-md font-bold transition-colors hover:bg-light-primary-container cursor-pointer"
          >
            <CalendarCheck class="w-4 h-4" />
            Kelola Event &amp; Lineup
          </button>
        </div>

        <!-- ── If event is selected ────────────────────────────────────── -->
        <template v-else>
          <!-- ── Top KPI Summary Row (4 Cards) ─────────────────────────── -->
          <section aria-label="Ringkasan KPI Keuangan" class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-gutter-md items-stretch">
            <!-- KPI 1: Primary Highlighted Card -->
            <article class="h-full p-gutter-lg rounded-md bg-light-primary text-light-on-primary flex flex-col justify-between gap-gutter-sm shadow-sm">
              <div class="flex items-center justify-between gap-gutter-xs">
                <span class="font-label text-label-md text-light-on-primary">Total Omzet Kotor</span>
                <span class="material-symbols-outlined text-[20px] text-light-on-primary shrink-0" aria-hidden="true">payments</span>
              </div>
              <div>
                <p class="font-headline text-headline-lg font-bold text-light-on-primary font-mono tabular-nums">{{ formatRupiah(totalGross) }}</p>
                <p class="font-label text-label-sm text-light-on-primary mt-gutter-xs tabular-nums">{{ validTransactions.length }} transaksi non-voided</p>
              </div>
            </article>

            <!-- KPI 2: Hak Bersih Tenant -->
            <article class="h-full p-gutter-lg rounded-md bg-light-surface-container-lowest border border-light-outline-variant flex flex-col justify-between gap-gutter-sm">
              <div class="flex items-center justify-between gap-gutter-xs">
                <span class="font-label text-label-md text-light-on-surface-variant">Hak Bersih Tenant</span>
                <span class="material-symbols-outlined text-[20px] text-light-primary shrink-0" aria-hidden="true">storefront</span>
              </div>
              <div>
                <p class="font-headline text-headline-lg font-bold text-light-on-surface font-mono tabular-nums">{{ formatRupiah(totalTenantNet) }}</p>
                <p class="font-label text-label-sm text-light-primary mt-gutter-xs tabular-nums">
                  {{ totalGross > 0 ? Math.round((totalTenantNet / totalGross) * 100) : 0 }}% rata-rata
                </p>
              </div>
            </article>

            <!-- KPI 3: Bagian Venue -->
            <article class="h-full p-gutter-lg rounded-md bg-light-surface-container-lowest border border-light-outline-variant flex flex-col justify-between gap-gutter-sm">
              <div class="flex items-center justify-between gap-gutter-xs">
                <span class="font-label text-label-md text-light-on-surface-variant">Bagian Venue</span>
                <span class="material-symbols-outlined text-[20px] text-light-on-surface-variant shrink-0" aria-hidden="true">apartment</span>
              </div>
              <div>
                <p class="font-headline text-headline-lg font-bold text-light-on-surface font-mono tabular-nums">{{ formatRupiah(totalVenueCut) }}</p>
                <p class="font-label text-label-sm text-light-on-surface-variant mt-gutter-xs tabular-nums">
                  {{ totalGross > 0 ? Math.round((totalVenueCut / totalGross) * 100) : 0 }}%
                </p>
              </div>
            </article>

            <!-- KPI 4: Bagian Organizer -->
            <article class="h-full p-gutter-lg rounded-md bg-light-surface-container-lowest border border-light-outline-variant flex flex-col justify-between gap-gutter-sm">
              <div class="flex items-center justify-between gap-gutter-xs">
                <span class="font-label text-label-md text-light-on-surface-variant">Bagian Organizer</span>
                <span class="material-symbols-outlined text-[20px] text-light-on-surface-variant shrink-0" aria-hidden="true">groups</span>
              </div>
              <div>
                <p class="font-headline text-headline-lg font-bold text-light-on-surface font-mono tabular-nums">{{ formatRupiah(totalOrganizerCut) }}</p>
                <p class="font-label text-label-sm text-light-on-surface-variant mt-gutter-xs tabular-nums">
                  {{ totalGross > 0 ? Math.round((totalOrganizerCut / totalGross) * 100) : 0 }}%
                </p>
              </div>
            </article>
          </section>

          <!-- ── Visual Widget: Rekonsiliasi Metode Pembayaran (End-of-Day) ── -->
          <section aria-label="Rekonsiliasi Metode Pembayaran End-of-Day" class="p-gutter-lg sm:p-gutter-xl rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-lg">
            <!-- Widget Header -->
            <div class="flex flex-wrap items-center justify-between gap-gutter-md">
              <div class="flex items-center gap-gutter-md min-w-0">
                <div class="w-10 h-10 rounded-md bg-light-secondary-container text-light-primary flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-[22px]" aria-hidden="true">account_balance_wallet</span>
                </div>
                <div class="min-w-0">
                  <h2 class="font-headline text-headline-md text-light-on-surface">Rekonsiliasi Metode Pembayaran (End-of-Day)</h2>
                  <p class="font-body text-body-sm text-light-on-surface-variant">Pemisahan setoran kas masuk QRIS vs fisik laci kasir (CASH)</p>
                </div>
              </div>

              <span class="font-mono text-mono-sm px-gutter-md py-gutter-xs rounded-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface tabular-nums shrink-0">
                Total Transaksi: {{ paymentBreakdown.qrisCount + paymentBreakdown.cashCount }}
              </span>
            </div>

            <!-- Two Side-by-Side Detail Cards -->
            <div class="grid grid-cols-1 md:grid-cols-2 gap-gutter-lg items-stretch">
              <!-- Left Card: QRIS Settlement -->
              <article class="h-full p-gutter-lg rounded-md bg-light-surface-container-low border border-light-outline-variant flex flex-col justify-between gap-gutter-md">
                <div class="flex items-center justify-between gap-gutter-sm">
                  <div class="flex items-center gap-gutter-sm">
                    <span class="font-label text-label-md px-gutter-sm py-gutter-xs rounded-sm bg-qris-container text-qris font-bold">QRIS Settlement</span>
                    <span class="font-body text-body-sm text-light-on-surface-variant tabular-nums">{{ paymentBreakdown.qrisCount }} transaksi</span>
                  </div>
                  <span class="font-mono text-mono-sm px-gutter-sm py-gutter-xs rounded-full bg-qris text-light-on-primary tabular-nums font-bold">{{ paymentBreakdown.qrisPct }}%</span>
                </div>

                <p class="font-mono text-2xl sm:text-3xl lg:text-display-lg font-bold text-qris tabular-nums">{{ formatRupiah(paymentBreakdown.qrisTotal) }}</p>

                <p class="font-body text-body-sm text-light-on-surface-variant pt-gutter-sm border-t border-light-outline-variant">Langsung masuk ke rekening settlement QRIS penyelenggara</p>
              </article>

              <!-- Right Card: CASH (Laci Kasir) -->
              <article class="h-full p-gutter-lg rounded-md bg-light-surface-container-low border border-light-outline-variant flex flex-col justify-between gap-gutter-md">
                <div class="flex items-center justify-between gap-gutter-sm">
                  <div class="flex items-center gap-gutter-sm">
                    <span class="font-label text-label-md px-gutter-sm py-gutter-xs rounded-sm bg-light-secondary-container text-light-primary font-bold">CASH (Laci Kasir)</span>
                    <span class="font-body text-body-sm text-light-on-surface-variant tabular-nums">{{ paymentBreakdown.cashCount }} transaksi</span>
                  </div>
                  <span class="font-mono text-mono-sm px-gutter-sm py-gutter-xs rounded-full bg-light-primary text-light-on-primary tabular-nums font-bold">{{ paymentBreakdown.cashPct }}%</span>
                </div>

                <p class="font-mono text-2xl sm:text-3xl lg:text-display-lg font-bold text-light-primary tabular-nums">{{ formatRupiah(paymentBreakdown.cashTotal) }}</p>

                <div class="flex flex-wrap items-center justify-between gap-gutter-sm pt-gutter-sm border-t border-light-outline-variant">
                  <span v-if="paymentBreakdown.cashChangeTotal > 0" class="font-mono text-mono-sm text-light-on-surface-variant tabular-nums">
                    Diterima: {{ formatRupiah(paymentBreakdown.cashTenderedTotal) }} • Kembalian: -{{ formatRupiah(paymentBreakdown.cashChangeTotal) }}
                  </span>
                  <span v-else class="font-mono text-mono-sm text-light-on-surface-variant tabular-nums">
                    Fisik kas laci kasir wajib cocok dengan nominal di atas
                  </span>
                  <span class="font-label text-label-sm text-light-primary font-bold shrink-0">Net Cash Fisik</span>
                </div>
              </article>
            </div>

            <!-- Bottom Visual Split Bar -->
            <div class="flex flex-col gap-gutter-sm">
              <div class="w-full h-3 rounded-full bg-light-surface-container overflow-hidden flex gap-0.5" role="img" :aria-label="`Rasio QRIS ${paymentBreakdown.qrisPct}% dan CASH ${paymentBreakdown.cashPct}%`">
                <div :style="{ width: `${paymentBreakdown.qrisPct}%` }" class="h-full bg-qris transition-all duration-300"></div>
                <div :style="{ width: `${paymentBreakdown.cashPct}%` }" class="h-full bg-light-primary transition-all duration-300"></div>
              </div>
              <div class="flex flex-wrap items-center justify-between gap-gutter-sm">
                <div class="flex items-center gap-gutter-xs">
                  <span class="w-2.5 h-2.5 rounded-full bg-qris shrink-0" aria-hidden="true"></span>
                  <span class="font-mono text-mono-sm text-light-on-surface tabular-nums">
                    QRIS: {{ paymentBreakdown.qrisPct }}% ({{ formatRupiah(paymentBreakdown.qrisTotal) }})
                  </span>
                </div>
                <div class="flex items-center gap-gutter-xs">
                  <span class="w-2.5 h-2.5 rounded-full bg-light-primary shrink-0" aria-hidden="true"></span>
                  <span class="font-mono text-mono-sm text-light-on-surface tabular-nums">
                    CASH: {{ paymentBreakdown.cashPct }}% ({{ formatRupiah(paymentBreakdown.cashTotal) }})
                  </span>
                </div>
              </div>
            </div>
          </section>

          <!-- ── Main Section: Laporan Bagi Hasil per Tenant ───────────── -->
          <section aria-label="Laporan Bagi Hasil per Tenant" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant overflow-hidden">
            <div class="p-gutter-lg border-b border-light-outline-variant flex flex-wrap items-center justify-between gap-gutter-md">
              <div>
                <h2 class="font-headline text-headline-md text-light-on-surface">Laporan Bagi Hasil per Tenant</h2>
                <p class="font-body text-body-sm text-light-on-surface-variant">Klik status transfer untuk menandai pelunasan, atau kirim rekap langsung ke WhatsApp tenant.</p>
              </div>
              <div class="flex items-center gap-2">
                <span class="font-mono text-mono-sm px-gutter-md py-gutter-xs rounded-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface-variant">
                  {{ settlementRows.length }} Booth Aktif
                </span>
              </div>
            </div>

            <div v-if="loadingTenants || loadingItems" class="flex justify-center py-10">
              <Loader2 class="w-7 h-7 text-light-primary animate-spin" />
            </div>
            <div v-else-if="settlementRows.length === 0" class="text-center py-10 text-light-on-surface-variant text-sm font-body">
              Belum ada tenant di event ini. Masukkan tenant di tab Event &amp; Lineup.
            </div>
            <div v-else>
              <!-- Desktop / Tablet Table View (>= 768px: hidden on mobile) -->
              <div class="hidden md:block overflow-x-auto">
                <table class="w-full text-left border-collapse">
                  <thead>
                    <tr class="bg-light-surface-container-low border-b border-light-outline-variant">
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase">Booth #</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase">Brand &amp; Kategori</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-right">Omzet Kotor</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-right">Potongan Venue</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-right">Potongan EO</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-right">Hak Bersih Tenant</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-center">Status Transfer</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-right">Aksi</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-light-outline-variant">
                    <tr
                      v-for="row in settlementRows"
                      :key="row.id"
                      class="hover:bg-light-surface-container-low transition-colors duration-state-change ease-state-change"
                    >
                      <td class="py-gutter-md px-gutter-md">
                        <span class="font-mono text-mono-sm px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container text-light-on-surface font-semibold">
                          {{ row.booth_number || '—' }}
                        </span>
                      </td>
                      <td class="py-gutter-md px-gutter-md">
                        <p class="font-label text-label-lg font-bold text-light-on-surface">{{ row.name }}</p>
                        <p class="font-body text-body-sm text-light-on-surface-variant">{{ row.category || 'Umum' }}</p>
                      </td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-md text-light-on-surface tabular-nums font-semibold">{{ formatRupiah(row.gross) }}</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-sm text-light-on-surface-variant tabular-nums">{{ formatRupiah(row.venueCut) }}</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-sm text-light-on-surface-variant tabular-nums">{{ formatRupiah(row.orgCut) }}</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-md text-light-primary tabular-nums font-bold">{{ formatRupiah(row.net) }}</td>
                      <td class="py-gutter-md px-gutter-md text-center">
                        <button
                          type="button"
                          @click="togglePayoutStatus(row)"
                          :class="row.payout_status === 'SETTLED'
                            ? 'bg-light-secondary-container text-light-primary border border-light-primary hover:bg-light-surface-variant'
                            : 'bg-light-tertiary-container text-light-on-tertiary-container border border-light-tertiary hover:opacity-90'"
                          class="shrink-0 inline-flex items-center gap-1 px-gutter-sm py-gutter-xs rounded-full font-label text-label-sm font-semibold transition-colors cursor-pointer select-none"
                        >
                          <Check v-if="row.payout_status === 'SETTLED'" class="w-3 h-3" />
                          <span>{{ row.payout_status === 'SETTLED' ? 'LUNAS' : 'BELUM TRANSFER' }}</span>
                        </button>
                      </td>
                      <td class="py-gutter-md px-gutter-md text-right">
                        <div class="inline-flex items-center gap-gutter-xs shrink-0">
                          <button
                            type="button"
                            @click="exportTenantPdf(row)"
                            :title="`Unduh slip settlement PDF untuk ${row.name}`"
                            class="px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-on-surface hover:bg-light-surface-container-low transition-colors cursor-pointer"
                          >
                            PDF
                          </button>
                          <button
                            type="button"
                            @click="copyTenantWaSummary(row)"
                            :title="`Salin ringkasan settlement WhatsApp untuk ${row.name}`"
                            :class="copiedWaId === row.id
                              ? 'bg-light-secondary-container text-light-primary border border-light-primary'
                              : 'bg-light-primary text-light-on-primary hover:bg-light-primary-container'"
                            class="px-gutter-sm py-gutter-xs rounded-sm font-label text-label-sm transition-colors cursor-pointer inline-flex items-center gap-1 font-semibold"
                          >
                            <Check v-if="copiedWaId === row.id" class="w-3 h-3" />
                            <span v-else class="material-symbols-outlined text-[14px]">chat</span>
                            <span>{{ copiedWaId === row.id ? 'Tersalin' : 'Kirim WA' }}</span>
                          </button>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                  <!-- Totals footer -->
                  <tfoot>
                    <tr class="bg-light-surface-container-low text-xs font-bold border-t-2 border-light-outline-variant">
                      <td colspan="2" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase tracking-wider">Total Keseluruhan</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-md text-light-on-surface tabular-nums font-bold">{{ formatRupiah(totalGross) }}</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-sm text-light-on-surface-variant tabular-nums font-semibold">{{ formatRupiah(totalVenueCut) }}</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-sm text-light-on-surface-variant tabular-nums font-semibold">{{ formatRupiah(totalOrganizerCut) }}</td>
                      <td class="py-gutter-md px-gutter-md text-right font-mono text-mono-md text-light-primary tabular-nums font-bold">{{ formatRupiah(totalTenantNet) }}</td>
                      <td colspan="2"></td>
                    </tr>
                  </tfoot>
                </table>
              </div>

              <!-- Mobile Stacked Card View (< 768px: md:hidden) -->
              <div class="md:hidden flex flex-col gap-gutter-md p-gutter-md">
                <article
                  v-for="row in settlementRows"
                  :key="row.id"
                  class="p-gutter-lg rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-md"
                >
                  <div class="flex items-center justify-between gap-gutter-sm">
                    <div class="flex items-center gap-gutter-sm min-w-0">
                      <span class="shrink-0 font-mono text-mono-sm px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container text-light-on-surface font-semibold">
                        {{ row.booth_number || '—' }}
                      </span>
                      <div class="min-w-0">
                        <h3 class="font-title text-title-md font-bold text-light-on-surface truncate">{{ row.name }}</h3>
                        <p class="font-body text-body-sm text-light-on-surface-variant">{{ row.category || 'Umum' }}</p>
                      </div>
                    </div>
                    <button
                      type="button"
                      @click="togglePayoutStatus(row)"
                      :class="row.payout_status === 'SETTLED'
                        ? 'bg-light-secondary-container text-light-primary border border-light-primary'
                        : 'bg-light-tertiary-container text-light-on-tertiary-container border border-light-tertiary'"
                      class="shrink-0 inline-flex items-center gap-1 px-gutter-sm py-gutter-xs rounded-full font-label text-label-sm font-semibold cursor-pointer select-none"
                    >
                      <Check v-if="row.payout_status === 'SETTLED'" class="w-3 h-3" />
                      <span>{{ row.payout_status === 'SETTLED' ? 'LUNAS' : 'BELUM TRANSFER' }}</span>
                    </button>
                  </div>

                  <!-- 2x2 Financial Metric Grid -->
                  <div class="grid grid-cols-2 gap-gutter-md p-gutter-md rounded-md bg-light-surface-container-low">
                    <div>
                      <span class="font-label text-label-sm text-light-on-surface-variant block">Omzet Kotor</span>
                      <span class="font-mono text-mono-md text-light-on-surface tabular-nums font-semibold">{{ formatRupiah(row.gross) }}</span>
                    </div>
                    <div>
                      <span class="font-label text-label-sm text-light-on-surface-variant block">Potongan Venue</span>
                      <span class="font-mono text-mono-md text-light-on-surface-variant tabular-nums font-semibold">{{ formatRupiah(row.venueCut) }}</span>
                    </div>
                    <div>
                      <span class="font-label text-label-sm text-light-on-surface-variant block">Potongan EO</span>
                      <span class="font-mono text-mono-md text-light-on-surface-variant tabular-nums font-semibold">{{ formatRupiah(row.orgCut) }}</span>
                    </div>
                    <div>
                      <span class="font-label text-label-sm text-light-on-surface-variant block">Hak Bersih Tenant</span>
                      <span class="font-mono text-mono-md text-light-primary tabular-nums font-bold">{{ formatRupiah(row.net) }}</span>
                    </div>
                  </div>

                  <!-- Action Buttons: Unduh PDF & Salin Rekap WA -->
                  <div class="grid grid-cols-2 gap-gutter-sm">
                    <button
                      type="button"
                      @click="exportTenantPdf(row)"
                      class="py-gutter-sm px-gutter-md rounded-md bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-md text-light-on-surface hover:bg-light-surface-container-low transition-colors cursor-pointer text-center"
                    >
                      Unduh PDF
                    </button>
                    <button
                      type="button"
                      @click="copyTenantWaSummary(row)"
                      :class="copiedWaId === row.id
                        ? 'bg-light-secondary-container text-light-primary border border-light-primary'
                        : 'bg-light-primary text-light-on-primary hover:bg-light-primary-container'"
                      class="py-gutter-sm px-gutter-md rounded-md font-label text-label-md transition-colors cursor-pointer flex items-center justify-center gap-1 font-semibold text-center"
                    >
                      <Check v-if="copiedWaId === row.id" class="w-3.5 h-3.5" />
                      <span>{{ copiedWaId === row.id ? 'Tersalin' : 'Salin Rekap WA' }}</span>
                    </button>
                  </div>
                </article>

                <!-- Compact Totals Summary Card at bottom of mobile list -->
                <div class="p-gutter-md rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-sm">
                  <div class="flex items-center justify-between border-b border-light-outline-variant pb-2">
                    <span class="font-label text-label-sm font-bold text-light-on-surface-variant uppercase tracking-wider">Total Keseluruhan</span>
                    <span class="font-mono font-bold text-base text-light-on-surface tabular-nums">{{ formatRupiah(totalGross) }}</span>
                  </div>
                  <div class="grid grid-cols-3 gap-2 text-xs pt-1">
                    <div>
                      <span class="font-label text-[10px] text-light-on-surface-variant block">Venue Cut</span>
                      <span class="font-mono font-semibold text-light-on-surface-variant tabular-nums text-xs">{{ formatRupiah(totalVenueCut) }}</span>
                    </div>
                    <div>
                      <span class="font-label text-[10px] text-light-on-surface-variant block">Org. Cut</span>
                      <span class="font-mono font-semibold text-light-on-surface-variant tabular-nums text-xs">{{ formatRupiah(totalOrganizerCut) }}</span>
                    </div>
                    <div>
                      <span class="font-label text-[10px] text-light-primary block">Tenant Net</span>
                      <span class="font-mono font-bold text-light-primary tabular-nums text-xs">{{ formatRupiah(totalTenantNet) }}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </section>
        </template>
      </div>

      <!-- ════════════════════════════════════════════════════════════════
           TAB 2: EVENT & LINEUP
      ═════════════════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'lineup'" class="flex flex-col gap-gutter-xl">
        <!-- ── Page Header & Primary CTA ──────────────────────────────── -->
        <header class="flex flex-wrap items-start justify-between gap-gutter-lg">
          <div class="min-w-0">
            <h1 class="font-headline text-headline-lg text-light-on-surface">Kelola Event &amp; Booth</h1>
            <p class="font-body text-body-md text-light-on-surface-variant mt-gutter-xs">Atur jadwal acara, status aktif kasir, dan daftar booth tenant yang berpartisipasi.</p>
          </div>

          <button
            @click="showCreateEventForm = !showCreateEventForm"
            type="button"
            class="inline-flex items-center gap-gutter-sm px-gutter-lg py-gutter-md rounded-md bg-light-primary text-light-on-primary hover:bg-light-primary-container transition-colors duration-state-change ease-state-change shrink-0 font-label text-label-md cursor-pointer"
          >
            <Plus class="w-4 h-4" />
            <span>+ Buat Event Baru</span>
            <ChevronUp v-if="showCreateEventForm" class="w-4 h-4" />
            <ChevronDown v-else class="w-4 h-4" />
          </button>
        </header>

        <!-- ── Active Event Control Card ──────────────────────────────── -->
        <section aria-label="Kontrol Event Aktif" class="p-gutter-xl rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-lg">
          <div class="flex flex-wrap items-center justify-between gap-gutter-md">
            <div class="flex flex-wrap items-center gap-gutter-md min-w-0">
              <!-- Event Switcher Dropdown Pill -->
              <div class="relative inline-flex items-center">
                <span class="material-symbols-outlined text-[18px] text-light-primary absolute left-3 pointer-events-none" style="font-variation-settings: 'FILL' 1;" aria-hidden="true">festival</span>
                <select
                  v-model="selectedEventId"
                  class="appearance-none pl-9 pr-8 py-2 rounded-md bg-light-surface-container-low border border-light-outline-variant text-light-on-surface hover:border-light-primary transition-colors cursor-pointer font-title text-title-md focus:outline-none focus:ring-2 focus:ring-light-primary"
                >
                  <option value="" disabled>-- Pilih Event --</option>
                  <option v-for="ev in events" :key="ev.id" :value="ev.id">
                    {{ ev.name }} {{ ev.event_dates ? `• ${ev.event_dates}` : '' }}
                  </option>
                </select>
                <span class="material-symbols-outlined text-[18px] text-light-on-surface-variant absolute right-2.5 pointer-events-none" aria-hidden="true">expand_more</span>
              </div>

              <!-- Status Toggle Pill -->
              <button
                v-if="selectedEvent"
                type="button"
                @click="toggleEventStatus(selectedEvent)"
                :disabled="togglingEventStatus"
                :class="(selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false)
                  ? 'bg-light-surface-container text-light-on-surface-variant border-light-outline-variant'
                  : 'bg-light-secondary-container text-light-primary border-light-primary'"
                class="inline-flex items-center gap-gutter-xs px-gutter-md py-gutter-xs rounded-full border font-label text-label-md transition-colors cursor-pointer shrink-0"
                :title="(selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false) ? 'Aktifkan kembali event ini agar muncul di kasir' : 'Tandai event ini selesai (arsipkan dari kasir)'"
              >
                <Loader2 v-if="togglingEventStatus" class="w-3.5 h-3.5 animate-spin" />
                <span v-else class="w-2 h-2 rounded-full shrink-0" :class="(selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false) ? 'bg-light-on-surface-variant' : 'bg-light-primary'"></span>
                <span>
                  {{ (selectedEvent.status === 'COMPLETED' || selectedEvent.is_active === false) ? 'STATUS: COMPLETED (Diarsipkan)' : 'STATUS: ACTIVE (Tampil di Kasir)' }}
                </span>
              </button>
            </div>

            <!-- Action buttons in Hero Card -->
            <div class="flex flex-wrap items-center gap-gutter-sm shrink-0">
              <button
                v-if="selectedEvent"
                type="button"
                @click="openEditEvent"
                class="inline-flex items-center gap-gutter-xs px-gutter-md py-gutter-sm rounded-md bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface hover:bg-light-surface-container-low transition-colors duration-state-change ease-state-change shrink-0 font-label text-label-md cursor-pointer"
              >
                <span class="material-symbols-outlined text-[16px]" aria-hidden="true">edit</span>
                <span>Edit Detail Event</span>
                <ChevronUp v-if="showEditEventForm" class="w-3.5 h-3.5 ml-1" />
                <ChevronDown v-else class="w-3.5 h-3.5 ml-1" />
              </button>
              <button
                v-if="selectedEvent"
                type="button"
                @click="openAssignLineupModal"
                class="inline-flex items-center gap-gutter-xs px-gutter-md py-gutter-sm rounded-md bg-light-primary text-light-on-primary hover:bg-light-primary-container transition-colors duration-state-change ease-state-change shrink-0 font-label text-label-md cursor-pointer"
              >
                <span class="material-symbols-outlined text-[16px]" aria-hidden="true">person_add</span>
                <span>+ Tugaskan Brand dari Database</span>
              </button>
              <button
                @click="lockAdmin"
                type="button"
                class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md bg-light-surface-container-low hover:bg-light-surface-container text-light-on-surface-variant hover:text-light-on-surface border border-light-outline-variant font-label text-label-md transition-colors cursor-pointer shrink-0"
                title="Kunci sesi Admin"
              >
                <Lock class="w-4 h-4 text-light-primary" />
                <span class="hidden sm:inline">Kunci Admin</span>
              </button>
            </div>
          </div>

          <!-- Event Metadata Row -->
          <div v-if="selectedEvent" class="flex flex-wrap items-center gap-gutter-lg pt-gutter-md border-t border-light-outline-variant">
            <div class="flex items-center gap-gutter-xs">
              <span class="material-symbols-outlined text-[18px] text-light-on-surface-variant" aria-hidden="true">location_on</span>
              <span class="font-body text-body-md text-light-on-surface-variant">Venue:</span>
              <span class="font-label text-label-lg text-light-on-surface font-semibold">{{ selectedEvent.venue || '—' }}</span>
            </div>

            <span class="font-mono text-mono-sm px-gutter-md py-gutter-xs rounded-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface tabular-nums font-semibold">
              Venue {{ selectedEvent.venue_share_percent ?? 10 }}% • Organizer {{ selectedEvent.organizer_share_percent ?? 0 }}% • Tenant {{ 100 - (Number(selectedEvent.venue_share_percent ?? 10) + Number(selectedEvent.organizer_share_percent ?? 0)) }}%
            </span>

            <span v-if="selectedEvent.event_dates" class="font-body text-body-sm text-light-primary">
              Jadwal: <strong>{{ selectedEvent.event_dates }}</strong>
            </span>
          </div>
        </section>

        <!-- ── Create Event Form (collapsible) ────────────────────────── -->
        <Transition
          enter-active-class="transition-all duration-200 ease-out"
          enter-from-class="opacity-0 -translate-y-2"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition-all duration-150 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-2"
        >
          <div v-if="showCreateEventForm" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant p-6 space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="font-headline text-headline-sm font-bold text-light-on-surface uppercase tracking-wider flex items-center gap-2">
                <Plus class="w-4 h-4 text-light-primary" />
                Buat Event Baru
              </h3>
              <button @click="showCreateEventForm = false" class="text-light-on-surface-variant hover:text-light-on-surface p-1">
                <X class="w-4 h-4" />
              </button>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama Event <span class="text-light-error">*</span></label>
                <input
                  v-model="newEvent.name"
                  type="text"
                  placeholder="e.g. Nyaris Pop Up Vol. 7"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary placeholder:text-light-on-surface-variant"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Venue / Lokasi</label>
                <input
                  v-model="newEvent.venue"
                  type="text"
                  placeholder="e.g. Toko Kopi Mas Boy"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary placeholder:text-light-on-surface-variant"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Tanggal Pelaksanaan (Rentang Kalender)</label>
                <DateRangePicker v-model:start="eventStartDate" v-model:end="eventEndDate" />
              </div>
              <div class="space-y-1.5 sm:col-span-2">
                <div class="flex items-center justify-between flex-wrap gap-2">
                  <label class="text-xs font-label font-semibold text-light-on-surface-variant">Skema Default Bagi Hasil (3-Way Split)</label>
                  <span class="font-mono text-mono-sm px-2.5 py-0.5 rounded-full bg-light-surface-container-low text-light-on-surface border border-light-outline-variant tabular-nums font-semibold">
                    Total Potongan: <strong class="text-light-error font-bold">{{ newEventTotalCut }}%</strong> • Hak Tenant: <strong class="text-light-primary font-bold">{{ newEventTenantTakeHome }}%</strong>
                  </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div class="space-y-1">
                    <label class="text-[11px] font-label font-semibold text-light-secondary flex items-center justify-between">
                      <span>Bagian Venue %</span>
                      <span class="text-light-on-surface-variant font-normal">Lokasi / Tempat</span>
                    </label>
                    <input
                      v-model.number="newEvent.venue_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary tabular-nums font-mono"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[11px] font-label font-semibold text-light-secondary flex items-center justify-between">
                      <span>Bagian Organizer %</span>
                      <span class="text-light-on-surface-variant font-normal">Penyelenggara / EO</span>
                    </label>
                    <input
                      v-model.number="newEvent.organizer_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary tabular-nums font-mono"
                    />
                  </div>
                </div>
              </div>
            </div>
            <div v-if="createEventError" class="text-sm text-light-error bg-light-error-container/20 border border-light-error/30 rounded-md px-3 py-2">
              {{ createEventError }}
            </div>
            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="showCreateEventForm = false"
                type="button"
                class="px-4 py-2 rounded-md text-sm font-label text-light-on-surface-variant hover:bg-light-surface-container-low transition-colors cursor-pointer"
              >
                Batal
              </button>
              <button
                @click="createEvent"
                :disabled="creatingEvent"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-60 text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="creatingEvent" class="w-4 h-4 animate-spin" />
                <Plus v-else class="w-4 h-4" />
                Simpan Event
              </button>
            </div>
          </div>
        </Transition>

        <!-- ── Edit Event Form (collapsible) ──────────────────────────── -->
        <Transition
          enter-active-class="transition-all duration-200 ease-out"
          enter-from-class="opacity-0 -translate-y-2"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition-all duration-150 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-2"
        >
          <div v-if="showEditEventForm" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant p-6 space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="font-headline text-headline-sm font-bold text-light-on-surface uppercase tracking-wider flex items-center gap-2">
                <Pencil class="w-4 h-4 text-light-primary" />
                Edit Pengaturan Event — {{ selectedEvent?.name }}
              </h3>
              <button @click="showEditEventForm = false" class="text-light-on-surface-variant hover:text-light-on-surface p-1">
                <X class="w-4 h-4" />
              </button>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama Event <span class="text-light-error">*</span></label>
                <input
                  v-model="editEventForm.name"
                  type="text"
                  placeholder="e.g. Nyaris Pop Up Vol. 6"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Venue / Lokasi</label>
                <input
                  v-model="editEventForm.venue"
                  type="text"
                  placeholder="e.g. Toko Kopi Mas Boy"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary"
                />
              </div>
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Status Event</label>
                <select
                  v-model="editEventForm.status"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary cursor-pointer"
                >
                  <option value="ACTIVE">ACTIVE (Sedang Berjalan / Kasir Aktif)</option>
                  <option value="COMPLETED">COMPLETED (Selesai / Diarsipkan dari Kasir)</option>
                </select>
              </div>
              <div class="space-y-1 sm:col-span-2">
                <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
                  <label class="text-xs font-label font-semibold text-light-on-surface-variant">Tanggal Pelaksanaan (Rentang Kalender)</label>
                  <div class="text-xs text-light-on-surface-variant flex items-center gap-1.5 flex-wrap">
                    <span>Saat ini:</span>
                    <strong class="text-light-on-surface font-mono">{{ editEventForm.event_dates || 'Belum diatur' }}</strong>
                    <span v-if="editDateChanged" class="text-light-primary ml-1">
                      → Berubah ke: <strong>{{ formatEventDates(editStartDate, editEndDate) }}</strong>
                    </span>
                    <button
                      v-if="editDateChanged"
                      type="button"
                      @click="editDateChanged = false"
                      class="text-[11px] text-light-tertiary hover:underline ml-1 cursor-pointer"
                    >
                      (Batal ganti tanggal)
                    </button>
                  </div>
                </div>
                <DateRangePicker
                  :start="editStartDate"
                  :end="editEndDate"
                  @update:start="(v) => { editStartDate = v; editDateChanged = true }"
                  @update:end="(v) => { editEndDate = v; editDateChanged = true }"
                />
              </div>
              <div class="space-y-1.5 sm:col-span-2">
                <div class="flex items-center justify-between flex-wrap gap-2">
                  <label class="text-xs font-label font-semibold text-light-on-surface-variant">Skema Default Bagi Hasil (3-Way Split)</label>
                  <span class="font-mono text-mono-sm px-2.5 py-0.5 rounded-full bg-light-surface-container-low text-light-on-surface border border-light-outline-variant tabular-nums font-semibold">
                    Total Potongan: <strong class="text-light-error font-bold">{{ editEventTotalCut }}%</strong> • Hak Tenant: <strong class="text-light-primary font-bold">{{ editEventTenantTakeHome }}%</strong>
                  </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div class="space-y-1">
                    <label class="text-[11px] font-label font-semibold text-light-secondary flex items-center justify-between">
                      <span>Bagian Venue %</span>
                      <span class="text-light-on-surface-variant font-normal">Lokasi / Tempat</span>
                    </label>
                    <input
                      v-model.number="editEventForm.venue_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary tabular-nums font-mono"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[11px] font-label font-semibold text-light-secondary flex items-center justify-between">
                      <span>Bagian Organizer %</span>
                      <span class="text-light-on-surface-variant font-normal">Penyelenggara / EO</span>
                    </label>
                    <input
                      v-model.number="editEventForm.organizer_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary tabular-nums font-mono"
                    />
                  </div>
                </div>
              </div>

              <!-- Bulk Sync Checkbox -->
              <div class="sm:col-span-2">
                <label class="flex items-start gap-3 cursor-pointer bg-light-surface-container-low border border-light-outline-variant rounded-md p-3.5 select-none hover:border-light-primary transition-colors">
                  <input
                    type="checkbox"
                    v-model="editEventForm.syncTenants"
                    class="mt-0.5 w-4 h-4 rounded text-light-primary focus:ring-light-primary border-light-outline-variant bg-light-surface-container-lowest accent-light-primary cursor-pointer"
                  />
                  <div class="text-xs">
                    <span class="text-light-on-surface font-semibold block">Terapkan default share % baru ke semua tenant di event ini</span>
                    <span class="text-light-on-surface-variant font-normal block mt-0.5">
                      Jika dicentang, persentase bagi hasil pada {{ tenants.length }} tenant terdaftar akan otomatis diselaraskan dengan setting baru.
                    </span>
                  </div>
                </label>
              </div>
            </div>

            <div v-if="editEventError" class="text-sm text-light-error bg-light-error-container/20 border border-light-error/30 rounded-md px-3 py-2">
              {{ editEventError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="showEditEventForm = false"
                type="button"
                class="px-4 py-2 rounded-md text-sm font-label text-light-on-surface-variant hover:bg-light-surface-container-low transition-colors cursor-pointer"
              >
                Batal
              </button>
              <button
                @click="saveEditEvent"
                :disabled="savingEditEvent"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-60 text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="savingEditEvent" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                Simpan Perubahan
              </button>
            </div>
          </div>
        </Transition>

        <!-- ── Sections 2–4 shown only when event is selected ────────────── -->
        <template v-if="selectedEventId">
          <!-- ── Section 2: Daftar Booth & Tenant Terdaftar ─────────────── -->
          <section aria-label="Daftar Booth dan Tenant Terdaftar" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant overflow-hidden">
            <div class="p-gutter-lg border-b border-light-outline-variant flex flex-col gap-gutter-md">
              <div class="flex flex-wrap items-center justify-between gap-gutter-md">
                <div>
                  <h2 class="font-headline text-headline-md text-light-on-surface">Daftar Booth &amp; Tenant Terdaftar</h2>
                  <p class="font-body text-body-sm text-light-on-surface-variant">Atur nomor booth, komisi bagi hasil kustom, dan kelola akses portal tenant.</p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="font-mono text-mono-sm px-gutter-md py-gutter-xs rounded-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface-variant">
                    {{ tenants.length }} Booth Terdaftar
                  </span>
                </div>
              </div>

              <!-- Lineup Error / Alert Banner -->
              <div
                v-if="lineupError"
                class="flex items-start gap-3 bg-light-error-container/20 border border-light-error/30 rounded-md p-4 text-light-error text-sm"
              >
                <AlertCircle class="w-5 h-5 text-light-error shrink-0 mt-0.5" />
                <div class="flex-1">
                  <p class="font-semibold text-light-on-surface">Pemberitahuan Lineup</p>
                  <p class="text-xs text-light-on-surface-variant mt-0.5 leading-relaxed">{{ lineupError }}</p>
                </div>
                <button
                  @click="lineupError = ''"
                  class="text-light-error hover:opacity-80 p-1 rounded-sm cursor-pointer shrink-0"
                  title="Tutup pemberitahuan"
                >
                  <X class="w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- Tenant List Content -->
            <div v-if="loadingTenants" class="flex justify-center py-10">
              <Loader2 class="w-7 h-7 text-light-primary animate-spin" />
            </div>
            <div v-else-if="tenants.length === 0" class="text-center py-12 text-light-on-surface-variant text-sm font-body">
              Belum ada booth/tenant terdaftar di event ini. Gunakan tombol "+ Tugaskan Brand dari Database" di atas.
            </div>
            <div v-else>
              <!-- Desktop / Tablet Table View (>= 768px: hidden on mobile) -->
              <div class="hidden md:block overflow-x-auto">
                <table class="w-full text-left border-collapse">
                  <thead>
                    <tr class="bg-light-surface-container-low border-b border-light-outline-variant">
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase">Booth #</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase">Brand &amp; Kategori</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase">Skema Bagi Hasil</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase">Portal &amp; WhatsApp</th>
                      <th scope="col" class="py-gutter-md px-gutter-md font-label text-label-sm text-light-on-surface-variant uppercase text-right">Aksi</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-light-outline-variant">
                    <tr
                      v-for="tenant in tenants"
                      :key="tenant.id"
                      class="hover:bg-light-surface-container-low transition-colors duration-state-change ease-state-change"
                    >
                      <td class="py-gutter-md px-gutter-md">
                        <span class="font-mono text-mono-sm px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container text-light-on-surface font-semibold">
                          {{ tenant.booth_number || '—' }}
                        </span>
                      </td>
                      <td class="py-gutter-md px-gutter-md">
                        <p class="font-label text-label-lg font-bold text-light-on-surface">{{ tenant.name }}</p>
                        <p class="font-body text-body-sm text-light-on-surface-variant">{{ tenant.category || 'Umum' }}</p>
                      </td>
                      <td class="py-gutter-md px-gutter-md">
                        <div class="flex flex-wrap items-center gap-gutter-xs">
                          <span class="font-mono text-mono-sm text-light-on-surface tabular-nums">
                            Venue {{ tenant.venue_share_percent ?? 10 }}% / EO {{ tenant.organizer_share_percent ?? 0 }}% • <strong class="text-light-primary font-bold">Hak Tenant {{ 100 - (Number(tenant.venue_share_percent ?? 10) + Number(tenant.organizer_share_percent ?? 0)) }}%</strong>
                          </span>
                          <span
                            v-if="Number(tenant.venue_share_percent) !== Number(selectedEvent?.venue_share_percent) || Number(tenant.organizer_share_percent) !== Number(selectedEvent?.organizer_share_percent)"
                            class="px-gutter-xs py-0.5 rounded-sm bg-light-tertiary-container text-light-on-tertiary-container font-label text-label-sm font-semibold"
                          >
                            Override
                          </span>
                        </div>
                      </td>
                      <td class="py-gutter-md px-gutter-md">
                        <div class="flex items-center gap-gutter-xs">
                          <!-- Salin Undangan WA -->
                          <button
                            type="button"
                            @click="copyTenantPortalInvite(tenant)"
                            :class="copiedInviteId === tenant.id
                              ? 'bg-light-secondary-container text-light-primary border border-light-primary'
                              : 'bg-light-secondary-container text-light-on-secondary-container hover:bg-light-surface-variant'"
                            class="px-gutter-sm py-gutter-xs rounded-sm font-label text-label-sm shrink-0 cursor-pointer transition-colors inline-flex items-center gap-1 font-semibold"
                            :title="`Salin format pesan undangan portal WhatsApp untuk ${tenant.name}`"
                          >
                            <Check v-if="copiedInviteId === tenant.id" class="w-3.5 h-3.5 text-light-primary" />
                            <span v-else class="material-symbols-outlined text-[14px]">chat</span>
                            <span>{{ copiedInviteId === tenant.id ? 'Tersalin!' : 'Undangan WA' }}</span>
                          </button>

                          <!-- Buka WA Chat jika ada nomor HP -->
                          <a
                            v-if="getTenantWhatsappUrl(tenant)"
                            :href="getTenantWhatsappUrl(tenant)"
                            target="_blank"
                            rel="noopener noreferrer"
                            class="w-7 h-7 rounded-sm bg-light-surface-container-lowest border border-light-outline-variant text-light-primary inline-flex items-center justify-center hover:bg-light-surface-container-low shrink-0 cursor-pointer"
                            :title="`Buka chat WhatsApp ke ${tenant.name}`"
                          >
                            <span class="material-symbols-outlined text-[16px]" aria-hidden="true">chat</span>
                          </a>

                          <!-- Salin Raw Link Portal -->
                          <button
                            type="button"
                            @click="copyPortalLink(tenant)"
                            class="px-gutter-xs py-gutter-xs font-label text-label-sm text-light-primary hover:underline shrink-0 cursor-pointer inline-flex items-center gap-1"
                            title="Salin raw URL link portal tenant"
                          >
                            <Check v-if="copiedId === tenant.id" class="w-3.5 h-3.5 text-light-primary" />
                            <Copy v-else class="w-3.5 h-3.5 text-light-primary" />
                            <span>{{ copiedId === tenant.id ? 'Copied!' : 'Portal' }}</span>
                          </button>
                        </div>
                      </td>
                      <td class="py-gutter-md px-gutter-md text-right">
                        <div class="inline-flex items-center gap-gutter-xs shrink-0">
                          <button
                            type="button"
                            @click="openEditTenant(tenant)"
                            class="px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-on-surface hover:bg-light-surface-container-low transition-colors cursor-pointer"
                          >
                            Edit
                          </button>
                          <button
                            type="button"
                            @click="removeTenantFromLineup(tenant)"
                            class="px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-tertiary hover:bg-light-tertiary-container hover:text-light-on-tertiary-container transition-colors cursor-pointer"
                          >
                            Hapus
                          </button>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <!-- Mobile Stacked Card View (< 768px: md:hidden) -->
              <div class="md:hidden flex flex-col gap-gutter-md p-gutter-md">
                <article
                  v-for="tenant in tenants"
                  :key="tenant.id"
                  class="p-gutter-lg rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-md"
                >
                  <div class="flex items-start justify-between gap-gutter-sm">
                    <div class="flex items-center gap-gutter-sm min-w-0">
                      <span class="shrink-0 font-mono text-mono-sm px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container text-light-on-surface font-semibold">
                        {{ tenant.booth_number || '—' }}
                      </span>
                      <div class="min-w-0">
                        <h3 class="font-title text-title-md font-bold text-light-on-surface truncate">{{ tenant.name }}</h3>
                        <span class="font-body text-body-sm text-light-on-surface-variant">{{ tenant.category || 'Umum' }}</span>
                      </div>
                    </div>
                    <span
                      v-if="Number(tenant.venue_share_percent) !== Number(selectedEvent?.venue_share_percent) || Number(tenant.organizer_share_percent) !== Number(selectedEvent?.organizer_share_percent)"
                      class="shrink-0 px-gutter-sm py-0.5 rounded-sm bg-light-tertiary-container text-light-on-tertiary-container font-label text-label-sm font-semibold"
                    >
                      Override
                    </span>
                  </div>

                  <!-- Split Schema box -->
                  <div class="p-gutter-sm rounded-sm bg-light-surface-container-low">
                    <span class="font-mono text-mono-sm text-light-on-surface tabular-nums block">
                      Venue {{ tenant.venue_share_percent ?? 10 }}% / EO {{ tenant.organizer_share_percent ?? 0 }}% • <strong class="text-light-primary font-bold">Hak Tenant {{ 100 - (Number(tenant.venue_share_percent ?? 10) + Number(tenant.organizer_share_percent ?? 0)) }}%</strong>
                    </span>
                  </div>

                  <!-- Mobile Actions Grid -->
                  <div class="grid grid-cols-2 gap-gutter-xs">
                    <button
                      type="button"
                      @click="copyTenantPortalInvite(tenant)"
                      :class="copiedInviteId === tenant.id
                        ? 'bg-light-secondary-container text-light-primary border border-light-primary'
                        : 'bg-light-secondary-container text-light-on-secondary-container'"
                      class="py-gutter-sm px-gutter-sm rounded-sm font-label text-label-sm font-semibold text-center cursor-pointer"
                    >
                      {{ copiedInviteId === tenant.id ? 'Tersalin!' : 'Undangan WA' }}
                    </button>
                    <a
                      v-if="getTenantWhatsappUrl(tenant)"
                      :href="getTenantWhatsappUrl(tenant)"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="py-gutter-sm px-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-primary flex items-center justify-center gap-1 cursor-pointer"
                    >
                      <span class="material-symbols-outlined text-[15px]">chat</span>
                      <span>Buka WA</span>
                    </a>
                    <button
                      v-else
                      type="button"
                      @click="copyPortalLink(tenant)"
                      class="py-gutter-sm px-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-primary text-center cursor-pointer"
                    >
                      {{ copiedId === tenant.id ? 'Copied!' : 'Portal' }}
                    </button>
                    <button
                      type="button"
                      @click="openEditTenant(tenant)"
                      class="py-gutter-sm px-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-on-surface text-center cursor-pointer"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      @click="removeTenantFromLineup(tenant)"
                      class="py-gutter-sm px-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-tertiary text-center cursor-pointer"
                    >
                      Hapus
                    </button>
                  </div>
                </article>
              </div>
            </div>
          </section>
        </template>

        <!-- ── Placeholder when no event is selected (in Tab 2) ────────── -->
        <div v-else class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant p-12 text-center space-y-3">
          <Building2 class="w-10 h-10 text-light-on-surface-variant mx-auto" />
          <p class="font-headline text-headline-sm font-bold text-light-on-surface">Pilih atau Buat Event Baru</p>
          <p class="font-body text-body-sm text-light-on-surface-variant">Gunakan tombol "+ Buat Event Baru" di atas untuk memulai lineup tenant event baru.</p>
        </div>
      </div>
            <!-- ════════════════════════════════════════════════════════════════
           TAB 3: MASTER TENANT DIRECTORY (DATABASE BRAND)
      ═════════════════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'master'" class="flex flex-col gap-gutter-lg">

        <!-- Page Header & Primary CTA -->
        <header class="flex flex-wrap items-start justify-between gap-gutter-lg">
          <div>
            <h1 class="font-headline text-headline-lg text-light-on-surface">Database Brand</h1>
            <p class="font-body text-body-md text-light-on-surface-variant mt-gutter-xs">Direktori induk seluruh brand tenant, kontak PIC, dan rekening pencairan dana.</p>
          </div>

          <div class="flex items-center gap-gutter-sm">
            <button
              @click="lockAdmin"
              type="button"
              class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md bg-light-surface-container-low hover:bg-light-surface-container text-light-on-surface-variant hover:text-light-on-surface border border-light-outline-variant font-label text-label-md transition-colors cursor-pointer shrink-0"
              title="Kunci sesi Admin"
            >
              <Lock class="w-4 h-4 text-light-primary" />
              <span class="hidden sm:inline">Kunci Admin</span>
            </button>
            <button
              @click="openAddMasterModal"
              type="button"
              class="inline-flex items-center gap-gutter-sm px-gutter-lg py-gutter-md rounded-md bg-light-primary text-light-on-primary hover:bg-light-primary-container transition-colors duration-state-change ease-state-change shrink-0 font-label text-label-lg font-bold cursor-pointer shadow-xs"
            >
              <Plus class="w-4 h-4 shrink-0" />
              <span>+ Tambah Brand Baru</span>
            </button>
          </div>
        </header>

        <!-- Search & Category Filter Bar -->
        <section aria-label="Pencarian dan filter kategori brand" class="p-gutter-lg rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-md">
          <div class="flex flex-wrap items-center justify-between gap-gutter-md">
            <div class="relative flex items-center flex-1 min-w-[280px] max-w-xl">
              <Search class="w-4 h-4 text-light-on-surface-variant absolute left-gutter-md pointer-events-none" />
              <input
                v-model="masterSearchQuery"
                type="search"
                placeholder="Cari nama brand, PIC, Instagram, atau nomor rekening..."
                class="w-full pl-9 pr-gutter-md py-gutter-sm rounded-md bg-light-surface-container-low border border-light-outline-variant text-body-md font-body text-light-on-surface placeholder:text-light-on-surface-variant focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none"
              />
            </div>

            <span class="inline-flex items-center gap-gutter-xs px-gutter-md py-gutter-xs rounded-full bg-light-secondary-container text-light-on-secondary-container shrink-0">
              <Store class="w-4 h-4 text-light-primary" />
              <span class="font-label text-label-md font-bold font-mono tabular-nums">{{ masterTenants.length }} Brand Tersimpan</span>
            </span>
          </div>

          <!-- Category Pills -->
          <div class="flex items-center gap-gutter-xs overflow-x-auto pb-gutter-xs no-scrollbar" role="group" aria-label="Filter kategori brand">
            <button
              v-for="pill in masterCategoriesWithCounts"
              :key="pill.key"
              type="button"
              @click="masterCategoryFilter = pill.key"
              :class="[
                'px-gutter-md py-gutter-xs rounded-full font-label text-label-md transition-colors cursor-pointer flex items-center gap-1.5 shrink-0',
                masterCategoryFilter === pill.key
                  ? 'bg-light-primary text-light-on-primary font-bold shadow-xs'
                  : 'bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface-variant hover:bg-light-surface-container-low'
              ]"
            >
              <span>{{ pill.label }}</span>
              <span
                :class="[
                  'px-1.5 py-0.5 rounded-full text-[10px] font-bold font-mono tabular-nums',
                  masterCategoryFilter === pill.key
                    ? 'bg-white/20 text-white'
                    : 'bg-light-surface-container text-light-on-surface-variant'
                ]"
              >
                {{ pill.count }}
              </span>
            </button>
          </div>
        </section>

        <!-- Main Content: Loading, Empty, or Master Brand Directory Table/Cards -->
        <div v-if="loadingMasterTenants" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant p-12 flex justify-center items-center">
          <Loader2 class="w-8 h-8 text-light-primary animate-spin" />
        </div>

        <div v-else-if="filteredMasterTenants.length === 0" class="rounded-lg bg-light-surface-container-lowest border border-light-outline-variant p-12 text-center space-y-3">
          <Store class="w-10 h-10 text-light-on-surface-variant mx-auto opacity-40" />
          <p class="font-headline text-headline-sm font-bold text-light-on-surface">Tidak ada brand master ditemukan</p>
          <p class="font-body text-body-sm text-light-on-surface-variant">Coba ubah kata kunci pencarian atau reset filter kategori.</p>
          <button
            v-if="masterSearchQuery || masterCategoryFilter !== 'ALL'"
            @click="masterSearchQuery = ''; masterCategoryFilter = 'ALL'"
            class="font-label text-label-sm text-light-primary font-bold hover:underline cursor-pointer inline-flex items-center gap-1"
          >
            Reset filter &amp; pencarian
          </button>
        </div>

        <div v-else class="space-y-4">
          <!-- Desktop Table View (>= 768px) -->
          <section aria-label="Direktori Induk Brand Tenant" class="hidden md:block rounded-lg bg-light-surface-container-lowest border border-light-outline-variant overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-left border-collapse">
                <thead>
                  <tr class="bg-light-surface-container-low border-b border-light-outline-variant">
                    <th scope="col" class="px-gutter-md py-gutter-md">
                      <span class="font-label text-label-sm text-light-on-surface-variant uppercase tracking-wide">Brand &amp; IG</span>
                    </th>
                    <th scope="col" class="px-gutter-sm py-gutter-md">
                      <span class="font-label text-label-sm text-light-on-surface-variant uppercase tracking-wide">Kategori</span>
                    </th>
                    <th scope="col" class="px-gutter-sm py-gutter-md">
                      <span class="font-label text-label-sm text-light-on-surface-variant uppercase tracking-wide">Kontak PIC &amp; WA</span>
                    </th>
                    <th scope="col" class="px-gutter-sm py-gutter-md">
                      <span class="font-label text-label-sm text-light-on-surface-variant uppercase tracking-wide">Rekening Pencairan</span>
                    </th>
                    <th scope="col" class="px-gutter-sm py-gutter-md">
                      <span class="font-label text-label-sm text-light-on-surface-variant uppercase tracking-wide">Status Event</span>
                    </th>
                    <th scope="col" class="px-gutter-md py-gutter-md text-right">
                      <span class="font-label text-label-sm text-light-on-surface-variant uppercase tracking-wide">Aksi</span>
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-light-outline-variant">
                  <tr
                    v-for="m in filteredMasterTenants"
                    :key="m.id"
                    class="hover:bg-light-surface-container-low transition-colors"
                  >
                    <!-- Brand & IG -->
                    <td class="px-gutter-md py-gutter-md">
                      <div class="flex items-center gap-gutter-sm">
                        <div class="w-9 h-9 rounded-md bg-light-secondary-container text-light-primary font-headline font-bold text-label-md flex items-center justify-center shrink-0">
                          {{ m.name ? m.name.charAt(0).toUpperCase() : 'B' }}
                        </div>
                        <div class="flex flex-col min-w-0">
                          <span class="font-title text-title-md text-light-on-surface truncate">{{ m.name }}</span>
                          <div class="flex items-center gap-1.5 flex-wrap">
                            <a
                              v-if="m.instagram"
                              :href="'https://instagram.com/' + m.instagram.replace(/^@/, '')"
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-0.5 text-light-primary hover:underline font-body text-body-sm"
                            >
                              <span>@{{ m.instagram.replace(/^@/, '') }}</span>
                            </a>
                            <span v-if="m.lastEventName" class="font-body text-body-sm text-light-on-surface-variant">
                              • {{ m.lastEventName }}
                            </span>
                          </div>
                        </div>
                      </div>
                    </td>

                    <!-- Kategori -->
                    <td class="px-gutter-sm py-gutter-md">
                      <span class="inline-flex items-center px-gutter-sm py-gutter-xs rounded-full bg-light-surface-container text-light-on-surface font-label text-label-sm">
                        {{ m.category || '—' }}
                      </span>
                    </td>

                    <!-- Kontak PIC & WA -->
                    <td class="px-gutter-sm py-gutter-md">
                      <div v-if="m.pic_name || m.whatsapp" class="flex items-center gap-gutter-xs">
                        <div class="flex flex-col">
                          <span v-if="m.pic_name" class="font-label text-label-md text-light-on-surface">{{ m.pic_name }}</span>
                          <span v-if="m.whatsapp" class="font-mono text-mono-sm text-light-on-surface-variant tabular-nums">{{ m.whatsapp }}</span>
                        </div>
                        <a
                          v-if="m.whatsapp"
                          :href="'https://wa.me/' + m.whatsapp.replace(/\D/g, '')"
                          target="_blank"
                          rel="noopener noreferrer"
                          :aria-label="'Chat WhatsApp ' + (m.pic_name || m.name)"
                          class="w-7 h-7 rounded-sm bg-light-secondary-container text-light-primary inline-flex items-center justify-center hover:bg-light-primary hover:text-light-on-primary transition-colors shrink-0 cursor-pointer"
                        >
                          <MessageSquare class="w-4 h-4" />
                        </a>
                      </div>
                      <span v-else class="font-body text-body-sm text-light-on-surface-variant">{{ m.contact_info || '—' }}</span>
                    </td>

                    <!-- Rekening Pencairan -->
                    <td class="px-gutter-sm py-gutter-md">
                      <div v-if="m.bank_name || m.bank_account || m.bank_info">
                        <span class="font-mono text-mono-sm text-light-on-surface tabular-nums block font-bold">
                          {{ m.bank_name ? m.bank_name.toUpperCase() : '' }} {{ m.bank_account ? '• ' + m.bank_account : '' }}
                        </span>
                        <span v-if="m.bank_holder" class="font-body text-body-sm text-light-on-surface-variant block">
                          a.n. {{ m.bank_holder }}
                        </span>
                        <span v-else-if="!m.bank_name && !m.bank_account" class="font-mono text-mono-sm text-light-on-surface tabular-nums block">
                          {{ m.bank_info }}
                        </span>
                      </div>
                      <span v-else class="font-body text-body-sm text-light-on-surface-variant">—</span>
                    </td>

                    <!-- Status Event -->
                    <td class="px-gutter-sm py-gutter-md">
                      <span
                        v-if="tenants.some((t) => t.master_tenant_id === m.id || t.name.toLowerCase().trim() === m.name.toLowerCase().trim())"
                        class="inline-flex items-center gap-1 px-gutter-sm py-gutter-xs rounded-full bg-light-secondary-container text-light-primary border border-light-primary font-label text-label-sm font-semibold"
                      >
                        <Check class="w-3.5 h-3.5" />
                        <span>Terdaftar (Booth {{ tenants.find((t) => t.master_tenant_id === m.id || t.name.toLowerCase().trim() === m.name.toLowerCase().trim())?.booth_number || '—' }})</span>
                      </span>
                      <span
                        v-else-if="selectedEventId"
                        class="inline-flex items-center px-gutter-sm py-gutter-xs rounded-full bg-light-surface-container text-light-on-surface-variant font-label text-label-sm"
                      >
                        Belum di Lineup
                      </span>
                      <span
                        v-else
                        class="font-body text-body-sm text-light-on-surface-variant italic"
                      >
                        Pilih event di Tab 1/2
                      </span>
                    </td>

                    <!-- Aksi -->
                    <td class="px-gutter-md py-gutter-md text-right">
                      <div class="inline-flex flex-col items-end gap-gutter-xs">
                        <button
                          type="button"
                          @click="openAssignSingleMasterModal(m)"
                          :disabled="events.length === 0"
                          class="px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container-low border border-light-outline-variant text-light-primary hover:bg-light-secondary-container transition-colors disabled:opacity-40 disabled:pointer-events-none cursor-pointer"
                          :title="events.length === 0 ? 'Belum ada event' : 'Tugaskan brand ke event'"
                        >
                          <span class="font-label text-label-sm font-semibold">+ Tugaskan ke Event</span>
                        </button>
                        <div class="inline-flex items-center gap-gutter-xs">
                          <button
                            type="button"
                            @click="openEditMasterModal(m)"
                            class="px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface hover:bg-light-surface-container-low transition-colors cursor-pointer"
                            title="Edit profil brand"
                          >
                            <span class="font-label text-label-sm">Edit</span>
                          </button>
                          <button
                            type="button"
                            @click="deleteMasterTenant(m)"
                            class="px-gutter-sm py-gutter-xs rounded-sm bg-light-surface-container-lowest border border-light-outline-variant text-light-tertiary hover:bg-light-tertiary-container hover:text-light-on-tertiary-container transition-colors cursor-pointer"
                            title="Hapus brand"
                          >
                            <span class="font-label text-label-sm">Hapus</span>
                          </button>
                        </div>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Mobile Stacked Card View (< 768px) -->
          <section aria-label="Daftar Brand Tenant Mobile" class="md:hidden flex flex-col gap-gutter-md">
            <article
              v-for="m in filteredMasterTenants"
              :key="m.id"
              class="p-gutter-lg rounded-lg bg-light-surface-container-lowest border border-light-outline-variant flex flex-col gap-gutter-md"
            >
              <!-- Brand Header & Category -->
              <div class="flex items-start justify-between gap-gutter-sm">
                <div class="min-w-0">
                  <h2 class="font-title text-title-md text-light-on-surface truncate">{{ m.name }}</h2>
                  <div class="flex items-center gap-1.5 flex-wrap mt-0.5">
                    <a
                      v-if="m.instagram"
                      :href="'https://instagram.com/' + m.instagram.replace(/^@/, '')"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-block text-light-primary hover:underline font-body text-body-sm"
                    >
                      @{{ m.instagram.replace(/^@/, '') }}
                    </a>
                    <span v-if="m.lastEventName" class="font-body text-body-sm text-light-on-surface-variant">
                      • {{ m.lastEventName }}
                    </span>
                  </div>
                </div>
                <span
                  v-if="m.category"
                  class="shrink-0 px-gutter-sm py-gutter-xs rounded-full bg-light-surface-container text-light-on-surface font-label text-label-sm"
                >
                  {{ m.category }}
                </span>
              </div>

              <!-- PIC & WA Link -->
              <div
                v-if="m.pic_name || m.whatsapp"
                class="flex items-center justify-between gap-gutter-sm p-gutter-sm rounded-sm bg-light-surface-container-low"
              >
                <div class="flex items-center gap-gutter-xs min-w-0">
                  <Users class="w-4 h-4 text-light-primary shrink-0" />
                  <span class="font-body text-body-sm text-light-on-surface truncate">
                    {{ m.pic_name || 'PIC' }}
                    <span v-if="m.whatsapp" class="font-mono text-mono-sm tabular-nums text-light-on-surface-variant"> • {{ m.whatsapp }}</span>
                  </span>
                </div>
                <a
                  v-if="m.whatsapp"
                  :href="'https://wa.me/' + m.whatsapp.replace(/\D/g, '')"
                  target="_blank"
                  rel="noopener noreferrer"
                  :aria-label="'Chat WhatsApp ' + (m.pic_name || m.name)"
                  class="w-7 h-7 rounded-sm bg-light-secondary-container text-light-primary inline-flex items-center justify-center hover:bg-light-primary hover:text-light-on-primary transition-colors shrink-0 cursor-pointer"
                >
                  <MessageSquare class="w-4 h-4" />
                </a>
              </div>

              <!-- Bank Info -->
              <div
                v-if="m.bank_name || m.bank_account || m.bank_info"
                class="p-gutter-sm rounded-sm bg-light-surface-container-low border border-light-outline-variant flex flex-col gap-0.5"
              >
                <span class="font-label text-label-sm text-light-on-surface-variant font-semibold">Rekening Pencairan</span>
                <span class="font-mono text-mono-sm text-light-on-surface tabular-nums font-bold">
                  {{ m.bank_name ? m.bank_name.toUpperCase() : '' }} {{ m.bank_account ? '• ' + m.bank_account : '' }}
                </span>
                <span v-if="m.bank_holder" class="font-body text-body-sm text-light-on-surface-variant">
                  a.n. {{ m.bank_holder }}
                </span>
                <span v-else-if="!m.bank_name && !m.bank_account" class="font-mono text-mono-sm text-light-on-surface tabular-nums">
                  {{ m.bank_info }}
                </span>
              </div>

              <!-- Status Event -->
              <div class="flex items-center justify-between gap-gutter-sm">
                <span
                  v-if="tenants.some((t) => t.master_tenant_id === m.id || t.name.toLowerCase().trim() === m.name.toLowerCase().trim())"
                  class="inline-flex items-center gap-1 px-gutter-sm py-gutter-xs rounded-full bg-light-secondary-container text-light-primary border border-light-primary font-label text-label-sm font-semibold"
                >
                  <Check class="w-3.5 h-3.5" />
                  Booth {{ tenants.find((t) => t.master_tenant_id === m.id || t.name.toLowerCase().trim() === m.name.toLowerCase().trim())?.booth_number || '—' }}
                </span>
                <span
                  v-else-if="selectedEventId"
                  class="inline-flex items-center px-gutter-sm py-gutter-xs rounded-full bg-light-surface-container text-light-on-surface-variant font-label text-label-sm"
                >
                  Belum di Lineup
                </span>
                <span v-else class="font-body text-body-sm text-light-on-surface-variant italic">
                  Pilih event di Tab 1/2
                </span>
              </div>

              <!-- Action Buttons -->
              <div class="flex flex-col gap-gutter-xs">
                <button
                  type="button"
                  @click="openAssignSingleMasterModal(m)"
                  :disabled="events.length === 0"
                  class="w-full py-gutter-sm px-gutter-md rounded-sm bg-light-surface-container-low border border-light-outline-variant text-light-primary font-label text-label-sm font-semibold hover:bg-light-secondary-container transition-colors disabled:opacity-40 disabled:pointer-events-none cursor-pointer touch-manipulation select-none"
                >
                  + Tugaskan ke Event
                </button>
                <div class="grid grid-cols-2 gap-gutter-xs">
                  <button
                    type="button"
                    @click="openEditMasterModal(m)"
                    class="py-gutter-sm px-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-on-surface hover:bg-light-surface-container-low transition-colors cursor-pointer text-center touch-manipulation select-none"
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    @click="deleteMasterTenant(m)"
                    class="py-gutter-sm px-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant font-label text-label-sm text-light-tertiary hover:bg-light-tertiary-container hover:text-light-on-tertiary-container transition-colors cursor-pointer text-center touch-manipulation select-none"
                  >
                    Hapus
                  </button>
                </div>
              </div>
            </article>
          </section>
        </div>
      </div>
    </main>
<!-- ── Edit Tenant Modal ─────────────────────────────────────────── -->
    <Transition name="modal">
      <div v-if="editingTenantModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="closeEditTenantModal" />
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-lg w-full max-w-lg shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-light-outline-variant bg-light-surface-container-low">
            <div>
              <p class="font-label text-label-sm text-light-primary font-bold uppercase tracking-wider">Tenant Override Settings</p>
              <h3 class="font-headline text-headline-md text-light-on-surface font-bold mt-0.5">{{ editingTenant?.name }}</h3>
            </div>
            <button @click="closeEditTenantModal" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-sm transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 pb-24 sm:pb-6 space-y-4 max-h-[85vh] sm:max-h-[80vh] overflow-y-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Tenant Name <span class="text-light-error">*</span></label>
                <input
                  v-model="editingTenant.name"
                  type="text"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Booth #</label>
                <input
                  v-model="editingTenant.booth_number"
                  type="text"
                  placeholder="e.g. A-12"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary font-mono"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Category <span class="text-light-error">*</span></label>
                <select
                  v-model="editTenantCategory"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary cursor-pointer"
                >
                  <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
              </div>

              <div v-if="editTenantCategory === 'Other (Custom)'" class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-primary">Custom Category <span class="text-light-error">*</span></label>
                <input
                  v-model="editTenantCustomCategory"
                  type="text"
                  placeholder="e.g. Handmade Candles"
                  class="w-full bg-light-surface-container-lowest border border-light-primary text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Bank Info (for payout)</label>
                <input
                  v-model="editingTenant.bank_info"
                  type="text"
                  placeholder="e.g. BCA 1234567890 a/n Budi"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary"
                />
              </div>

              <!-- Revenue Split 3-Way Override -->
              <div class="space-y-2 sm:col-span-2 bg-light-surface-container-low border border-light-outline-variant rounded-md p-4">
                <div class="flex items-center justify-between flex-wrap gap-2">
                  <label class="text-xs font-label font-semibold text-light-on-surface">Custom Revenue Split (3-Way)</label>
                  <span class="font-mono text-mono-sm px-2.5 py-0.5 rounded-full bg-light-surface-container-lowest text-light-on-surface border border-light-outline-variant tabular-nums font-semibold">
                    Total Potongan: <strong class="text-light-error font-bold">{{ editTenantTotalCut }}%</strong> • Hak Tenant: <strong class="text-light-primary font-bold">{{ editTenantTakeHome }}%</strong>
                  </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                  <div class="space-y-1">
                    <label class="text-[11px] font-label font-semibold text-light-secondary">Venue Share %</label>
                    <input
                      v-model.number="editingTenant.venue_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary tabular-nums font-mono"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[11px] font-label font-semibold text-light-secondary">Organizer Share %</label>
                    <input
                      v-model.number="editingTenant.organizer_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary tabular-nums font-mono"
                    />
                  </div>
                </div>
              </div>
            </div>

            <div v-if="editTenantError" class="text-sm text-light-error bg-light-error-container/20 border border-light-error/30 rounded-md px-3 py-2">
              {{ editTenantError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="closeEditTenantModal"
                type="button"
                class="px-4 py-2 rounded-md font-label text-label-md text-light-on-surface-variant hover:bg-light-surface-container-low transition-colors cursor-pointer"
              >
                Batal
              </button>
              <button
                @click="saveEditTenant"
                :disabled="savingEditTenant"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-60 text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="savingEditTenant" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                Simpan Perubahan
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
    <!-- ── Assign from Master to Lineup Modal ──────────────────────────── -->
    <Transition name="modal">
      <div v-if="showAssignLineupModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showAssignLineupModal = false" />
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-lg w-full max-w-3xl shadow-2xl z-10 overflow-hidden flex flex-col max-h-[90vh]">
          <!-- Header -->
          <div class="flex items-center justify-between px-6 py-4 border-b border-light-outline-variant bg-light-surface-container-low">
            <div>
              <p class="font-label text-label-sm text-light-primary font-bold uppercase tracking-wider">Event Lineup Builder</p>
              <h3 class="font-headline text-headline-lg text-light-on-surface font-bold mt-0.5">Tugaskan Brand dari Master Directory</h3>
            </div>
            <button @click="showAssignLineupModal = false" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-sm transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Filters bar -->
          <div class="p-4 border-b border-light-outline-variant bg-light-surface-container-low flex flex-wrap gap-3 items-center justify-between">
            <div class="flex items-center gap-3 flex-1 min-w-[240px]">
              <div class="relative flex-1">
                <Search class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-light-on-surface-variant pointer-events-none" />
                <input
                  v-model="assignLineupSearch"
                  type="text"
                  placeholder="Cari brand master atau kategori…"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md pl-9 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary placeholder:text-light-on-surface-variant"
                />
              </div>
              <div class="relative min-w-[170px]">
                <select
                  v-model="assignLineupCategory"
                  class="w-full bg-light-surface-container-lowest border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 text-sm appearance-none focus:outline-none focus:ring-2 focus:ring-light-primary pr-8 cursor-pointer"
                >
                  <option value="ALL">Semua Kategori</option>
                  <option v-for="cat in PRESET_CATEGORIES.filter(c => c !== 'Other (Custom)')" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
                <ChevronDown class="w-4 h-4 absolute right-2.5 top-1/2 -translate-y-1/2 text-light-on-surface-variant pointer-events-none" />
              </div>
            </div>

            <div class="text-xs text-light-on-surface-variant font-label">
              Target Event: <strong class="text-light-on-surface font-bold">{{ selectedEvent?.name }}</strong>
            </div>
          </div>

          <!-- Body / List -->
          <div class="flex-1 overflow-y-auto p-4 space-y-3">
            <div v-if="filteredLineupMasterTenants.length === 0" class="text-center py-12 text-light-on-surface-variant text-sm font-body">
              Tidak ada brand master yang cocok.
            </div>

            <div v-else class="space-y-2">
              <div class="flex items-center justify-between px-2 text-xs text-light-on-surface-variant mb-1 font-label">
                <button
                  type="button"
                  @click="toggleSelectAllLineupMasters"
                  class="text-light-primary hover:underline font-semibold cursor-pointer"
                >
                  Pilih / Batal Semua yang Tersedia
                </button>
                <span>{{ filteredLineupMasterTenants.length }} brands ditemukan</span>
              </div>

              <div
                v-for="m in filteredLineupMasterTenants"
                :key="m.id"
                :class="[
                  'border rounded-md p-3 flex items-center gap-3 transition-colors',
                  activeEventMasterIds.has(m.id) || activeEventTenantNames.has(m.name.toLowerCase().trim())
                    ? 'bg-light-surface-container-low border-light-outline-variant opacity-60'
                    : selectedMasterIds.has(m.id)
                      ? 'bg-light-secondary-container/40 border-light-primary'
                      : 'bg-light-surface-container-lowest border-light-outline-variant hover:bg-light-surface-container-low'
                ]"
              >
                <!-- Checkbox -->
                <input
                  type="checkbox"
                  :disabled="activeEventMasterIds.has(m.id) || activeEventTenantNames.has(m.name.toLowerCase().trim())"
                  :checked="selectedMasterIds.has(m.id)"
                  @change="toggleSelectMaster(m)"
                  class="w-4 h-4 rounded text-light-primary focus:ring-light-primary border-light-outline-variant bg-light-surface-container-lowest accent-light-primary cursor-pointer disabled:cursor-not-allowed"
                />

                <!-- Master Info -->
                <div class="flex-1 min-w-0 cursor-pointer" @click="toggleSelectMaster(m)">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="font-bold text-light-on-surface text-sm truncate font-label">{{ m.name }}</span>
                    <span class="text-xs bg-light-surface-container text-light-on-surface-variant rounded-sm px-2 py-0.5 font-label">{{ m.category || 'Umum' }}</span>
                    <span
                      v-if="activeEventMasterIds.has(m.id) || activeEventTenantNames.has(m.name.toLowerCase().trim())"
                      class="text-[10px] font-semibold bg-light-secondary-container text-light-primary border border-light-primary rounded-sm px-1.5 py-0.5 font-label"
                    >
                      Sudah di Lineup
                    </span>
                  </div>
                  <div class="flex items-center gap-2 text-xs text-light-on-surface-variant mt-1 flex-wrap">
                    <span class="text-light-on-surface-variant">Event terakhir:</span>
                    <span v-if="m.lastEventName" class="text-light-primary font-semibold">{{ m.lastEventName }}</span>
                    <span v-else class="text-light-on-surface-variant italic">Belum pernah ikut event</span>
                    <span v-if="m.contact_info" class="text-light-on-surface-variant">• {{ m.contact_info }}</span>
                    <span v-if="m.bank_info" class="text-light-on-surface-variant font-mono text-[11px]">• {{ m.bank_info }}</span>
                  </div>
                </div>

                <!-- Booth Input -->
                <div v-if="!activeEventMasterIds.has(m.id) && !activeEventTenantNames.has(m.name.toLowerCase().trim())" class="w-28 flex-shrink-0">
                  <label class="text-[10px] text-light-on-surface-variant block mb-0.5 font-label">Booth #:</label>
                  <input
                    v-model="lineupAssignBooths[m.id]"
                    type="text"
                    placeholder="e.g. B-01"
                    @focus="selectedMasterIds.add(m.id)"
                    class="w-full bg-light-surface-container-lowest border border-light-outline-variant focus:border-light-primary text-light-on-surface rounded-sm px-2 py-1 text-xs focus:outline-none font-mono"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="px-6 py-4 pb-8 sm:pb-4 border-t border-light-outline-variant bg-light-surface-container-low flex items-center justify-between flex-wrap gap-3">
            <span class="text-xs text-light-on-surface-variant font-label">
              Terpilih: <strong class="text-light-primary font-bold">{{ selectedMasterIds.size }}</strong> brand
            </span>
            <div class="flex items-center gap-3">
              <button
                @click="showAssignLineupModal = false"
                type="button"
                class="px-4 py-2 rounded-md text-sm font-label text-light-on-surface-variant hover:bg-light-surface-container transition-colors cursor-pointer"
              >
                Batal
              </button>
              <button
                @click="confirmAssignMastersToLineup"
                :disabled="selectedMasterIds.size === 0 || assigningLineup"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-50 text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="assigningLineup" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                Tugaskan {{ selectedMasterIds.size }} Brand
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
        <!-- ── Add Master Tenant Modal ────────────────────────────────────── -->
    <Transition name="modal">
      <div v-if="showAddMasterModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showAddMasterModal = false" />
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-lg w-full max-w-lg shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-light-outline-variant bg-light-surface-container-low">
            <div>
              <p class="font-label text-label-sm text-light-primary font-bold uppercase tracking-wider">Master Directory</p>
              <h3 class="font-headline text-headline-md text-light-on-surface font-bold mt-0.5">Tambah Brand Master Baru</h3>
            </div>
            <button @click="showAddMasterModal = false" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-sm transition-colors cursor-pointer">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 pb-24 sm:pb-6 space-y-4 max-h-[85vh] sm:max-h-[80vh] overflow-y-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <!-- Brand Name -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama Brand <span class="text-light-error">*</span></label>
                <input
                  v-model="newMasterTenant.name"
                  type="text"
                  placeholder="e.g. Kopi Tuku / SneakerLab"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <!-- Kategori -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Kategori <span class="text-light-error">*</span></label>
                <select
                  v-model="newMasterTenant.category"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none"
                >
                  <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
              </div>

              <div v-if="newMasterTenant.category === 'Other (Custom)'" class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-amber-600">Custom Category <span class="text-light-error">*</span></label>
                <input
                  v-model="newMasterTenant.customCategory"
                  type="text"
                  placeholder="e.g. Leather Craft"
                  class="w-full bg-light-surface-container-low border border-amber-500/50 text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none"
                />
              </div>

              <!-- Kontak Brand & PIC -->
              <div class="sm:col-span-2 pt-2 border-t border-light-outline-variant">
                <span class="font-label text-label-sm font-bold text-light-on-surface uppercase tracking-wider block">Kontak Brand &amp; PIC (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Instagram (@handle)</label>
                <input
                  v-model="newMasterTenant.instagram"
                  type="text"
                  placeholder="e.g. @kopituku"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama PIC</label>
                <input
                  v-model="newMasterTenant.pic_name"
                  type="text"
                  placeholder="e.g. Nadia Kusuma"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nomor WhatsApp PIC</label>
                <input
                  v-model="newMasterTenant.whatsapp"
                  type="text"
                  placeholder="e.g. 081234567890"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none font-mono tabular-nums placeholder:text-light-on-surface-variant"
                />
              </div>

              <!-- Informasi Rekening Bank -->
              <div class="sm:col-span-2 pt-2 border-t border-light-outline-variant">
                <span class="font-label text-label-sm font-bold text-light-on-surface uppercase tracking-wider block">Informasi Rekening Bank (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama Bank</label>
                <input
                  v-model="newMasterTenant.bank_name"
                  type="text"
                  placeholder="e.g. BCA / Mandiri"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nomor Rekening</label>
                <input
                  v-model="newMasterTenant.bank_account"
                  type="text"
                  placeholder="e.g. 0118492031"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-mono text-mono-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none tabular-nums placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Atas Nama Rekening</label>
                <input
                  v-model="newMasterTenant.bank_holder"
                  type="text"
                  placeholder="e.g. Nadia Kusuma Putri"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>
            </div>

            <div v-if="createMasterError" class="text-body-sm font-body text-light-error bg-light-error-container/20 border border-light-error/30 rounded-md px-3 py-2">
              {{ createMasterError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="showAddMasterModal = false"
                type="button"
                class="px-4 py-2 rounded-md font-label text-label-md font-semibold text-light-on-surface-variant hover:bg-light-surface-container transition-colors cursor-pointer"
              >
                Cancel
              </button>
              <button
                @click="createMasterTenant"
                :disabled="creatingMaster"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-50 text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="creatingMaster" class="w-4 h-4 animate-spin" />
                <Plus v-else class="w-4 h-4" />
                Simpan Brand
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>

    <!-- ── Edit Master Tenant Modal ───────────────────────────────────── -->
    <Transition name="modal">
      <div v-if="editingMasterModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="editingMasterModal = false" />
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-lg w-full max-w-lg shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-light-outline-variant bg-light-surface-container-low">
            <div>
              <p class="font-label text-label-sm text-light-primary font-bold uppercase tracking-wider">Master Directory</p>
              <h3 class="font-headline text-headline-md text-light-on-surface font-bold mt-0.5">Edit Profil Brand Master</h3>
            </div>
            <button @click="editingMasterModal = false" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-sm transition-colors cursor-pointer">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 pb-24 sm:pb-6 space-y-4 max-h-[85vh] sm:max-h-[80vh] overflow-y-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <!-- Brand Name -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama Brand <span class="text-light-error">*</span></label>
                <input
                  v-model="editingMasterTenant.name"
                  type="text"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none"
                />
              </div>

              <!-- Kategori -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Kategori <span class="text-light-error">*</span></label>
                <select
                  v-model="editMasterCategory"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none"
                >
                  <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
              </div>

              <div v-if="editMasterCategory === 'Other (Custom)'" class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-amber-600">Custom Category <span class="text-light-error">*</span></label>
                <input
                  v-model="editMasterCustomCategory"
                  type="text"
                  placeholder="e.g. Leather Craft"
                  class="w-full bg-light-surface-container-low border border-amber-500/50 text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none"
                />
              </div>

              <!-- Kontak Brand & PIC -->
              <div class="sm:col-span-2 pt-2 border-t border-light-outline-variant">
                <span class="font-label text-label-sm font-bold text-light-on-surface uppercase tracking-wider block">Kontak Brand &amp; PIC (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Instagram (@handle)</label>
                <input
                  v-model="editingMasterTenant.instagram"
                  type="text"
                  placeholder="e.g. @kopituku"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama PIC</label>
                <input
                  v-model="editingMasterTenant.pic_name"
                  type="text"
                  placeholder="e.g. Nadia Kusuma"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nomor WhatsApp PIC</label>
                <input
                  v-model="editingMasterTenant.whatsapp"
                  type="text"
                  placeholder="e.g. 081234567890"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none font-mono tabular-nums placeholder:text-light-on-surface-variant"
                />
              </div>

              <!-- Informasi Rekening Bank -->
              <div class="sm:col-span-2 pt-2 border-t border-light-outline-variant">
                <span class="font-label text-label-sm font-bold text-light-on-surface uppercase tracking-wider block">Informasi Rekening Bank (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nama Bank</label>
                <input
                  v-model="editingMasterTenant.bank_name"
                  type="text"
                  placeholder="e.g. BCA / Mandiri"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nomor Rekening</label>
                <input
                  v-model="editingMasterTenant.bank_account"
                  type="text"
                  placeholder="e.g. 0118492031"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-mono text-mono-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none tabular-nums placeholder:text-light-on-surface-variant"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Atas Nama Rekening</label>
                <input
                  v-model="editingMasterTenant.bank_holder"
                  type="text"
                  placeholder="e.g. Nadia Kusuma Putri"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>
            </div>

            <div v-if="editMasterError" class="text-body-sm font-body text-light-error bg-light-error-container/20 border border-light-error/30 rounded-md px-3 py-2">
              {{ editMasterError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="editingMasterModal = false"
                type="button"
                class="px-4 py-2 rounded-md font-label text-label-md font-semibold text-light-on-surface-variant hover:bg-light-surface-container transition-colors cursor-pointer"
              >
                Cancel
              </button>
              <button
                @click="saveEditMasterTenant"
                :disabled="savingMaster"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-50 text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="savingMaster" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                Simpan Perubahan
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>

    <!-- ── Quick Assign Single Master Tenant to Active Event Modal ──────── -->
    <Transition name="modal">
      <div v-if="assigningMasterModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="assigningMasterModal = false" />
        <div class="relative bg-light-surface-container-lowest border border-light-outline-variant rounded-lg w-full max-w-md shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-light-outline-variant bg-light-surface-container-low">
            <div>
              <p class="font-label text-label-sm text-light-primary font-bold uppercase tracking-wider">Tugaskan Brand ke Event</p>
              <h3 class="font-headline text-headline-md text-light-on-surface font-bold mt-0.5">{{ targetMasterTenant?.name }}</h3>
            </div>
            <button @click="assigningMasterModal = false" class="text-light-on-surface-variant hover:text-light-on-surface p-1 rounded-sm transition-colors cursor-pointer">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 pb-24 sm:pb-6 space-y-4 max-h-[85vh] sm:max-h-[80vh] overflow-y-auto">
            <div class="space-y-3">
              <div class="space-y-1.5">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Target Event <span class="text-light-error">*</span></label>
                <div class="relative">
                  <select
                    v-model="assignTargetEventId"
                    class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2.5 font-body text-body-md appearance-none focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none pr-8 cursor-pointer"
                  >
                    <option v-for="ev in events" :key="ev.id" :value="ev.id">
                      {{ ev.name }} ({{ ev.venue || 'No Venue' }})
                    </option>
                  </select>
                  <ChevronDown class="w-4 h-4 absolute right-3 top-1/2 -translate-y-1/2 text-light-on-surface-variant pointer-events-none" />
                </div>
              </div>

              <!-- Target Event Revenue Split & Details -->
              <div v-if="assignTargetEvent" class="bg-light-surface-container-low border border-light-outline-variant rounded-md p-3 text-xs space-y-1.5">
                <div class="flex items-center justify-between text-light-on-surface flex-wrap gap-1">
                  <span class="text-light-on-surface-variant font-label">Default Split:</span>
                  <span class="font-mono tabular-nums text-mono-sm">
                    Venue <strong class="text-light-primary">{{ assignTargetEvent.venue_share_percent ?? 10 }}%</strong>
                    • EO <strong class="text-amber-600">{{ assignTargetEvent.organizer_share_percent ?? 0 }}%</strong>
                    • Tenant <strong class="text-light-primary">{{ Math.max(0, 100 - (Number(assignTargetEvent.venue_share_percent ?? 10) + Number(assignTargetEvent.organizer_share_percent ?? 0))) }}%</strong>
                  </span>
                </div>
                <div v-if="assignTargetEvent.event_dates" class="text-[11px] font-body text-light-on-surface-variant">
                  Tanggal: {{ assignTargetEvent.event_dates }}
                </div>
              </div>

              <!-- Warning if brand is already registered in this target event -->
              <div v-if="isBrandAlreadyInTargetEvent" class="flex items-center gap-2.5 p-3 rounded-md bg-amber-500/10 border border-amber-500/30 text-amber-800 text-xs font-body">
                <AlertCircle class="w-4 h-4 shrink-0 text-amber-600" />
                <span>Brand ini sudah terdaftar di lineup event terpilih.</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-label font-semibold text-light-on-surface-variant">Nomor Booth di Event Ini</label>
                <input
                  v-model="assignBoothNumber"
                  type="text"
                  placeholder="e.g. A-08"
                  class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface rounded-md px-3 py-2 font-body text-body-md focus:border-light-primary focus:ring-2 focus:ring-light-primary focus:outline-none placeholder:text-light-on-surface-variant"
                />
              </div>
            </div>

            <div v-if="assignMasterError" class="text-body-sm font-body text-light-error bg-light-error-container/20 border border-light-error/30 rounded-md px-3 py-2">
              {{ assignMasterError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="assigningMasterModal = false"
                type="button"
                class="px-4 py-2 rounded-md font-label text-label-md font-semibold text-light-on-surface-variant hover:bg-light-surface-container transition-colors cursor-pointer"
              >
                Cancel
              </button>
              <button
                @click="confirmAssignMasterToActiveEvent"
                :disabled="assigningToActiveEvent || isBrandAlreadyInTargetEvent || !assignTargetEventId"
                type="button"
                class="inline-flex items-center gap-2 bg-light-primary hover:bg-light-primary-container disabled:opacity-50 disabled:cursor-not-allowed text-light-on-primary px-5 py-2 rounded-md font-label text-label-md font-bold transition-colors cursor-pointer"
              >
                <Loader2 v-if="assigningToActiveEvent" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                <span>{{ isBrandAlreadyInTargetEvent ? 'Sudah Terdaftar' : 'Tugaskan Sekarang' }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
    <!-- ── Floating Global Toast Notification ────────────────────────────── -->
    <Transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="opacity-0 translate-y-4 sm:translate-y-0 sm:translate-x-4"
      enter-to-class="opacity-100 translate-y-0 sm:translate-x-0"
      leave-active-class="transition duration-200 ease-in"
      leave-from-class="opacity-100 translate-y-0 sm:translate-x-0"
      leave-to-class="opacity-0 translate-y-4 sm:translate-y-0 sm:translate-x-4"
    >
      <div
        v-if="toast.show"
        class="fixed bottom-6 right-6 z-50 max-w-md shadow-2xl rounded-lg border p-4 flex items-start gap-3 backdrop-blur-md bg-light-surface-container-lowest text-light-on-surface"
        :class="{
          'border-light-primary/40': toast.type === 'success',
          'border-light-error/40': toast.type === 'error',
          'border-sky-500/40': toast.type === 'info',
        }"
      >
        <CheckCircle2 v-if="toast.type === 'success'" class="w-5 h-5 text-light-primary shrink-0 mt-0.5" />
        <AlertCircle v-else-if="toast.type === 'error'" class="w-5 h-5 text-light-error shrink-0 mt-0.5" />
        <AlertCircle v-else class="w-5 h-5 text-sky-600 shrink-0 mt-0.5" />

        <div class="flex-1 font-body text-body-sm leading-relaxed">
          {{ toast.message }}
        </div>

        <button
          @click="toast.show = false"
          class="p-1 rounded-sm hover:bg-light-surface-container text-light-on-surface-variant hover:text-light-on-surface transition-colors cursor-pointer shrink-0"
          title="Tutup"
        >
          <X class="w-4 h-4" />
        </button>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
@keyframes shake {
  0%, 100% {
    transform: translateX(0);
  }
  20%, 60% {
    transform: translateX(-6px);
  }
  40%, 80% {
    transform: translateX(6px);
  }
}

.animate-shake {
  animation: shake 0.35s ease-in-out;
}

.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
  transform: scale(0.97);
}
</style>
