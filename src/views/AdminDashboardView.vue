<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
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
import { formatRupiah } from '@/lib/currency.js'
import DateRangePicker from '@/components/DateRangePicker.vue'
import { generateEventSettlementPdf, generateTenantSettlementPdf } from '@/lib/exportSettlementPdf.js'

const router = useRouter()
const { signOut } = useAuth()

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
      selectedEventId.value = events.value[0].id
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

const activeTab = ref('overview') // 'overview' | 'lineup' | 'master'
const events = ref([])
const selectedEventId = ref(null)
const tenants = ref([])
const transactionItems = ref([]) // items with joined transaction info
const transactions = ref([]) // transactions for active event

const loadingEvents = ref(false)
const loadingTenants = ref(false)
const loadingItems = ref(false)

const showCreateEventForm = ref(false)
const showAddTenantForm = ref(false)

const copiedId = ref(null) // track which tenant link was just copied
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
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
  if (!eventId) return

  realtimeChannel = supabase
    .channel(`admin-items-${eventId}`)
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
    .subscribe()
}

// ─── Watch selected event ─────────────────────────────────────────────────────

watch(selectedEventId, (id) => {
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
      selectedEventId.value = events.value[0].id
    }
  }
  window.addEventListener('keydown', handleKeydown)
})

onUnmounted(() => {
  if (realtimeChannel) supabase.removeChannel(realtimeChannel)
  if (masterRealtimeChannel) supabase.removeChannel(masterRealtimeChannel)
  window.removeEventListener('keydown', handleKeydown)
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
  if (!newTenant.value.name.trim()) {
    addTenantError.value = 'Tenant name is required.'
    return
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

// ─── Copy Portal Link ─────────────────────────────────────────────────────────

async function copyPortalLink(tenant) {
  const url = `${window.location.origin}/tenant/${tenant.access_token}`
  await navigator.clipboard.writeText(url)
  copiedId.value = tenant.id
  setTimeout(() => { copiedId.value = null }, 2000)
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

  const { data: updatedEvent, error: evError } = await supabase
    .from('events')
    .update({
      name: editEventForm.value.name.trim(),
      venue: editEventForm.value.venue.trim(),
      event_dates: finalDates,
      venue_share_percent: venueShare,
      organizer_share_percent: orgShare,
      default_share_percent: totalShare,
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

  if (!editingTenant.value.name.trim()) {
    editTenantError.value = 'Nama tenant tidak boleh kosong.'
    return
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
    supabase.removeChannel(masterRealtimeChannel)
    masterRealtimeChannel = null
  }
  masterRealtimeChannel = supabase
    .channel('admin-master-tenants-sync')
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'master_tenants' },
      () => { fetchMasterTenants() }
    )
    .subscribe()
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
  if (!newMasterTenant.value.name.trim()) {
    createMasterError.value = 'Brand name is required.'
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
  if (!editingMasterTenant.value.name.trim()) {
    editMasterError.value = 'Brand name is required.'
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
  if (!targetMasterTenant.value || !assignTargetEventId.value || isBrandAlreadyInTargetEvent.value) return
  assignMasterError.value = ''
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
    class="min-h-screen bg-slate-950 text-slate-100 font-sans flex flex-col items-center justify-center p-4 selection:bg-emerald-500/30"
  >
    <div class="w-full max-w-sm flex flex-col items-center text-center">
      <!-- Shield / Lock Badge -->
      <div
        class="w-16 h-16 rounded-3xl bg-emerald-500/10 border border-emerald-500/25 flex items-center justify-center mb-5 text-emerald-400 shadow-xl shadow-emerald-500/10"
      >
        <Lock class="w-7 h-7" />
      </div>

      <!-- Header Title & Subtitle -->
      <h1 class="text-2xl font-bold tracking-tight text-white mb-1.5">
        PopUpPOS <span class="text-emerald-400">Admin</span>
      </h1>
      <p class="text-xs text-slate-400 max-w-[280px] leading-relaxed mb-6">
        Masukkan 6-digit PIN untuk akses dashboard event, settlements & komisi
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
              ? 'bg-emerald-500/15 border-emerald-400 shadow-sm shadow-emerald-500/30 scale-105'
              : 'bg-slate-900 border-slate-800',
          ]"
        >
          <span
            v-if="enteredPin.length >= i"
            class="w-3 h-3 rounded-full bg-emerald-400 shadow-sm shadow-emerald-400"
          />
        </div>
      </div>

      <!-- Error / Helper Message -->
      <div class="h-6 mb-5 flex items-center justify-center">
        <p v-if="pinError" class="text-xs font-semibold text-rose-400">
          {{ pinError }}
        </p>
        <p v-else class="text-[11px] text-slate-500">
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
          class="h-14 rounded-2xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-800 hover:border-slate-700 text-xl font-bold text-slate-100 flex items-center justify-center transition-all duration-100 shadow-sm cursor-pointer select-none"
        >
          {{ n }}
        </button>

        <!-- Clear Button -->
        <button
          type="button"
          @click="clearPin"
          class="h-14 rounded-2xl bg-slate-900/60 hover:bg-slate-800 active:scale-95 border border-slate-800/80 hover:border-slate-700 text-xs font-bold text-slate-400 hover:text-slate-200 flex items-center justify-center transition-all duration-100 uppercase tracking-wider cursor-pointer select-none"
        >
          Clear
        </button>

        <!-- 0 Button -->
        <button
          type="button"
          @click="appendDigit('0')"
          class="h-14 rounded-2xl bg-slate-900 hover:bg-slate-800 active:scale-95 border border-slate-800 hover:border-slate-700 text-xl font-bold text-slate-100 flex items-center justify-center transition-all duration-100 shadow-sm cursor-pointer select-none"
        >
          0
        </button>

        <!-- Backspace Button -->
        <button
          type="button"
          @click="deleteDigit"
          class="h-14 rounded-2xl bg-slate-900/60 hover:bg-slate-800 active:scale-95 border border-slate-800/80 hover:border-slate-700 text-slate-400 hover:text-slate-200 flex items-center justify-center transition-all duration-100 cursor-pointer select-none"
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
          class="flex items-center gap-2 text-xs font-semibold text-slate-400 hover:text-slate-200 bg-slate-900/80 hover:bg-slate-800 border border-slate-800 px-3.5 py-2 rounded-xl transition-colors cursor-pointer"
        >
          <ArrowLeft class="w-4 h-4 text-emerald-400" />
          Kembali ke Kasir
        </button>
        <button
          type="button"
          @click="handleLogout"
          class="flex items-center gap-1.5 text-xs font-semibold text-slate-400 hover:text-rose-400 bg-slate-900/80 hover:bg-rose-500/10 border border-slate-800 hover:border-rose-500/30 px-3 py-2 rounded-xl transition-colors cursor-pointer"
          title="Keluar dari akun staf"
        >
          <LogOut class="w-3.5 h-3.5" />
          Keluar
        </button>
      </div>
    </div>
  </div>

  <!-- ── Unlocked Admin Dashboard ──────────────────────────────────────── -->
  <div v-else class="min-h-screen bg-slate-950 text-slate-100 font-sans">

    <!-- ── Top Navigation Bar ───────────────────────────────────────────── -->
    <header class="bg-slate-900 border-b border-slate-800 sticky top-0 z-30 shadow-lg shadow-black/20">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <ShieldCheck class="w-7 h-7 text-emerald-400" />
          <span class="text-xl font-bold tracking-tight text-white">PopUpPOS <span class="text-emerald-400">Admin</span></span>
        </div>
        <div class="flex items-center gap-2.5">
          <button
            @click="lockAdmin"
            class="flex items-center gap-1.5 bg-slate-800 hover:bg-amber-500/20 text-slate-400 hover:text-amber-400 border border-slate-700 hover:border-amber-500/30 px-3 py-2 rounded-xl font-semibold text-xs transition-colors cursor-pointer"
            title="Kunci sesi Admin"
          >
            <Lock class="w-3.5 h-3.5" />
            <span>Kunci</span>
          </button>
          <button
            @click="handleLogout"
            class="flex items-center gap-1.5 bg-slate-800 hover:bg-rose-500/20 text-slate-400 hover:text-rose-400 border border-slate-700 hover:border-rose-500/30 px-3 py-2 rounded-xl font-semibold text-xs transition-colors cursor-pointer"
            title="Keluar dari akun staf"
          >
            <LogOut class="w-3.5 h-3.5" />
            <span>Keluar</span>
          </button>
          <button
            @click="router.push('/')"
            class="flex items-center gap-2 bg-slate-800 hover:bg-slate-700 text-slate-200 px-4 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
          >
            <ShoppingCart class="w-4 h-4" />
            Cashier View
          </button>
        </div>
      </div>

      <!-- ── 3-Tab Workspace Bar ───────────────────────────────────────── -->
      <div class="border-t border-slate-800/80 bg-slate-900/90 backdrop-blur-md">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center gap-2 overflow-x-auto py-2">
          <button
            @click="activeTab = 'overview'"
            :class="activeTab === 'overview'
              ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/40 shadow-sm'
              : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 border-transparent'"
            class="flex items-center gap-2 px-4 py-2 rounded-xl font-semibold text-sm border transition-all cursor-pointer whitespace-nowrap"
          >
            <TrendingUp class="w-4 h-4" />
            <span>Overview & Settlement</span>
          </button>

          <button
            @click="activeTab = 'lineup'"
            :class="activeTab === 'lineup'
              ? 'bg-amber-500/15 text-amber-400 border-amber-500/40 shadow-sm'
              : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 border-transparent'"
            class="flex items-center gap-2 px-4 py-2 rounded-xl font-semibold text-sm border transition-all cursor-pointer whitespace-nowrap"
          >
            <CalendarCheck class="w-4 h-4" />
            <span>Event & Lineup</span>
            <span v-if="selectedEvent" class="ml-1 text-xs px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 font-normal">
              {{ tenants.length }}
            </span>
          </button>

          <button
            @click="activeTab = 'master'"
            :class="activeTab === 'master'
              ? 'bg-sky-500/15 text-sky-400 border-sky-500/40 shadow-sm'
              : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60 border-transparent'"
            class="flex items-center gap-2 px-4 py-2 rounded-xl font-semibold text-sm border transition-all cursor-pointer whitespace-nowrap"
          >
            <Store class="w-4 h-4" />
            <span>Master Tenant</span>
            <span class="ml-1 text-xs px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 font-normal">
              {{ masterTenants.length }}
            </span>
          </button>
        </div>
      </div>
    </header>

    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">

      <!-- ════════════════════════════════════════════════════════════════
           TAB 1: OVERVIEW & SETTLEMENT
      ═════════════════════════════════════════════════════════════════ -->
      <div v-if="activeTab === 'overview'" class="space-y-8">
        <!-- Compact Event Selector Bar -->
        <section class="bg-slate-900 border border-slate-800 rounded-2xl p-4 sm:p-5 flex flex-wrap items-center justify-between gap-4">
          <div class="flex items-center gap-3 flex-wrap flex-1 min-w-[280px]">
            <div class="flex items-center gap-2">
              <Building2 class="w-5 h-5 text-emerald-400" />
              <label class="text-sm font-semibold text-slate-300">Active Event:</label>
            </div>
            <div class="relative flex-1 max-w-md min-w-[220px]">
              <select
                v-model="selectedEventId"
                class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-xl px-4 py-2.5 text-sm appearance-none focus:outline-none focus:ring-2 focus:ring-emerald-500 pr-9 cursor-pointer"
              >
                <option value="" disabled>-- Select an event --</option>
                <option v-for="ev in events" :key="ev.id" :value="ev.id">
                  {{ ev.name }} {{ ev.event_dates ? `(${ev.event_dates})` : '' }}
                </option>
              </select>
              <ChevronDown class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
            </div>
            <Loader2 v-if="loadingEvents" class="w-5 h-5 text-slate-400 animate-spin" />
          </div>

          <div v-if="selectedEvent" class="flex items-center gap-2 text-xs flex-wrap">
            <span class="px-2.5 py-1 rounded-lg bg-slate-800 text-slate-300 border border-slate-700">
              Venue: <strong class="text-white">{{ selectedEvent.venue || '—' }}</strong>
            </span>
            <span v-if="selectedEvent.event_dates" class="px-2.5 py-1 rounded-lg bg-slate-800 text-emerald-400 border border-emerald-500/20">
              {{ selectedEvent.event_dates }}
            </span>
            <button
              @click="activeTab = 'lineup'; openEditEvent()"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-sky-400 border border-slate-700 transition-colors cursor-pointer"
              title="Edit event settings & share %"
            >
              <Pencil class="w-3.5 h-3.5" />
              <span>Edit Event</span>
            </button>
          </div>
        </section>

        <!-- If no event is selected -->
        <div v-if="!selectedEventId" class="bg-slate-900 border border-slate-800 rounded-2xl p-16 text-center space-y-4">
          <CalendarCheck class="w-12 h-12 text-slate-700 mx-auto" />
          <div>
            <p class="text-slate-300 text-lg font-semibold">Pilih Event Terlebih Dahulu</p>
            <p class="text-slate-500 text-sm mt-1">Silakan pilih event aktif di dropdown atas, atau buka tab Event & Lineup untuk membuat event baru.</p>
          </div>
          <button
            @click="activeTab = 'lineup'"
            class="inline-flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 text-slate-950 px-5 py-2.5 rounded-xl font-bold text-sm transition-colors cursor-pointer"
          >
            <CalendarCheck class="w-4 h-4" />
            Kelola Event & Lineup
          </button>
        </div>

        <!-- If event is selected -->
        <template v-else>
          <!-- Live Revenue Summary Cards (Cards 1-5) -->
          <section class="space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold text-white flex items-center gap-2">
                <TrendingUp class="w-5 h-5 text-sky-400" />
                Live Revenue Summary
                <span class="text-xs font-normal text-slate-500">— Realtime calculations</span>
              </h2>
              <div v-if="loadingItems" class="flex items-center gap-2 text-sm text-slate-400">
                <Loader2 class="w-4 h-4 animate-spin" />
                Updating…
              </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4">
              <!-- Card 1: Total Gross Revenue -->
              <div class="bg-slate-900 border border-slate-800 rounded-2xl p-5 space-y-2">
                <p class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Total Gross Revenue</p>
                <p class="text-2xl font-bold text-white">{{ formatRupiah(totalGross) }}</p>
                <p class="text-xs text-slate-500">Semua transaksi non-voided</p>
              </div>

              <!-- Card 2: Venue Cut -->
              <div class="bg-slate-900 border border-violet-500/20 rounded-2xl p-5 space-y-2">
                <p class="text-xs font-semibold text-violet-400 uppercase tracking-wider">Venue Cut</p>
                <p class="text-2xl font-bold text-violet-400">{{ formatRupiah(totalVenueCut) }}</p>
                <p class="text-xs text-slate-500">Lokasi / venue share</p>
              </div>

              <!-- Card 3: Organizer Cut -->
              <div class="bg-slate-900 border border-amber-500/20 rounded-2xl p-5 space-y-2">
                <p class="text-xs font-semibold text-amber-400 uppercase tracking-wider">Organizer Cut</p>
                <p class="text-2xl font-bold text-amber-400">{{ formatRupiah(totalOrganizerCut) }}</p>
                <p class="text-xs text-slate-500">Penyelenggara / EO share</p>
              </div>

              <!-- Card 4: Tenant Net Payout -->
              <div class="bg-slate-900 border border-emerald-500/20 rounded-2xl p-5 space-y-2">
                <p class="text-xs font-semibold text-emerald-400 uppercase tracking-wider">Tenant Net Payout</p>
                <p class="text-2xl font-bold text-emerald-400">{{ formatRupiah(totalTenantNet) }}</p>
                <p class="text-xs text-slate-500">Hak bersih semua tenant</p>
              </div>

              <!-- Card 5: Payment Breakdown -->
              <div class="bg-slate-900 border border-sky-500/20 rounded-2xl p-5 space-y-3 sm:col-span-2 lg:col-span-1 xl:col-span-1">
                <p class="text-xs font-semibold text-sky-400 uppercase tracking-wider">Payment Breakdown</p>
                <div class="flex justify-between items-center">
                  <div class="space-y-0.5">
                    <p class="text-xs text-slate-500 flex items-center gap-1">
                      <CreditCard class="w-3.5 h-3.5 text-sky-400" /> QRIS
                    </p>
                    <p class="text-lg font-bold text-sky-400">{{ formatRupiah(totalQris) }}</p>
                  </div>
                  <div class="w-px h-10 bg-slate-700" />
                  <div class="space-y-0.5 text-right">
                    <p class="text-xs text-slate-500 flex items-center gap-1 justify-end">
                      <Banknote class="w-3.5 h-3.5 text-slate-300" /> CASH
                    </p>
                    <p class="text-lg font-bold text-slate-200">{{ formatRupiah(totalCash) }}</p>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <!-- End-of-Day Payment Reconciliation Card -->
          <section class="bg-slate-900 border border-slate-800 rounded-2xl p-5 space-y-4">
            <div class="flex items-center justify-between flex-wrap gap-2">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-xl bg-slate-800 border border-slate-700/80 flex items-center justify-center text-emerald-400">
                  <Banknote class="w-4 h-4" />
                </div>
                <div>
                  <h3 class="text-sm font-bold text-white flex items-center gap-2">
                    Rekonsiliasi Metode Pembayaran (End-of-Day)
                  </h3>
                  <p class="text-xs text-slate-400">
                    Pemisahan setoran kas masuk QRIS vs fisik laci kasir (CASH)
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2 text-xs font-mono">
                <span class="px-2.5 py-1 rounded-lg bg-slate-800 text-slate-300 border border-slate-700">
                  Total Transaksi: <strong class="text-white">{{ paymentBreakdown.qrisCount + paymentBreakdown.cashCount }}</strong>
                </span>
              </div>
            </div>

            <!-- Two Columns: QRIS vs CASH -->
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <!-- QRIS Column -->
              <div class="bg-slate-950/60 border border-sky-500/30 rounded-xl p-4 flex flex-col justify-between gap-3">
                <div class="flex items-start justify-between">
                  <div class="space-y-1">
                    <div class="flex items-center gap-2">
                      <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-lg text-xs font-bold bg-sky-500/15 text-sky-400 border border-sky-500/30">
                        <CreditCard class="w-3.5 h-3.5" />
                        QRIS Settlement
                      </span>
                      <span class="text-xs text-slate-400 font-mono font-medium">
                        {{ paymentBreakdown.qrisCount }} transaksi
                      </span>
                    </div>
                    <p class="text-2xl font-black text-sky-400 tracking-tight pt-1">
                      {{ formatRupiah(paymentBreakdown.qrisTotal) }}
                    </p>
                  </div>
                  <span class="text-xs font-bold px-2 py-1 rounded-lg bg-sky-500/10 text-sky-400 border border-sky-500/20 font-mono">
                    {{ paymentBreakdown.qrisPct }}%
                  </span>
                </div>
                <p class="text-[11px] text-slate-400">
                  Langsung masuk ke rekening settlement QRIS penyelenggara
                </p>
              </div>

              <!-- CASH (Laci Kasir) Column -->
              <div class="bg-slate-950/60 border border-emerald-500/30 rounded-xl p-4 flex flex-col justify-between gap-3">
                <div class="flex items-start justify-between">
                  <div class="space-y-1">
                    <div class="flex items-center gap-2">
                      <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-lg text-xs font-bold bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
                        <Banknote class="w-3.5 h-3.5" />
                        CASH (Laci Kasir)
                      </span>
                      <span class="text-xs text-slate-400 font-mono font-medium">
                        {{ paymentBreakdown.cashCount }} transaksi
                      </span>
                    </div>
                    <p class="text-2xl font-black text-emerald-400 tracking-tight pt-1">
                      {{ formatRupiah(paymentBreakdown.cashTotal) }}
                    </p>
                  </div>
                  <span class="text-xs font-bold px-2 py-1 rounded-lg bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-mono">
                    {{ paymentBreakdown.cashPct }}%
                  </span>
                </div>

                <!-- Cash Tendered & Change Breakdown Line -->
                <div class="text-[11px] text-slate-400 font-mono flex items-center justify-between flex-wrap gap-1 border-t border-slate-800/80 pt-2">
                  <span v-if="paymentBreakdown.cashChangeTotal > 0">
                    Diterima: <span class="text-slate-200">{{ formatRupiah(paymentBreakdown.cashTenderedTotal) }}</span> • Kembalian: <span class="text-rose-400">-{{ formatRupiah(paymentBreakdown.cashChangeTotal) }}</span>
                  </span>
                  <span v-else>
                    Fisik kas laci kasir wajib cocok dengan nominal di atas
                  </span>
                  <span class="text-emerald-400 font-semibold font-sans text-[10px]">Net Cash Fisik</span>
                </div>
              </div>
            </div>

            <!-- Visual Split Progress Bar -->
            <div class="space-y-1.5">
              <div class="h-2.5 w-full bg-slate-800 rounded-full overflow-hidden flex">
                <div
                  v-if="paymentBreakdown.qrisPct > 0"
                  :style="{ width: `${paymentBreakdown.qrisPct}%` }"
                  class="h-full bg-sky-500 transition-all duration-300"
                  :title="`QRIS: ${paymentBreakdown.qrisPct}%`"
                />
                <div
                  v-if="paymentBreakdown.cashPct > 0"
                  :style="{ width: `${paymentBreakdown.cashPct}%` }"
                  class="h-full bg-emerald-500 transition-all duration-300"
                  :title="`CASH: ${paymentBreakdown.cashPct}%`"
                />
                <div
                  v-if="paymentBreakdown.qrisPct === 0 && paymentBreakdown.cashPct === 0"
                  class="h-full w-full bg-slate-800"
                />
              </div>
              <div class="flex justify-between text-[11px] font-mono text-slate-400 px-0.5">
                <span class="flex items-center gap-1.5 text-sky-400">
                  <span class="w-2 h-2 rounded-full bg-sky-500 inline-block"></span>
                  QRIS: {{ paymentBreakdown.qrisPct }}% ({{ formatRupiah(paymentBreakdown.qrisTotal) }})
                </span>
                <span class="flex items-center gap-1.5 text-emerald-400">
                  <span class="w-2 h-2 rounded-full bg-emerald-500 inline-block"></span>
                  CASH: {{ paymentBreakdown.cashPct }}% ({{ formatRupiah(paymentBreakdown.cashTotal) }})
                </span>
              </div>
            </div>
          </section>

          <!-- Settlement Table -->
          <section class="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-5">
            <div class="flex items-center justify-between flex-wrap gap-3">
              <div>
                <h2 class="text-lg font-bold text-white flex items-center gap-2">
                  <Download class="w-5 h-5 text-emerald-400" />
                  Settlement & Payout Table
                </h2>
                <p class="text-xs text-slate-400 mt-0.5">Pantau bagi hasil per tenant dan tandai status pembayaran (Pending / Settled)</p>
              </div>
              <button
                @click="exportAllPdf"
                class="flex items-center gap-2 bg-slate-800 hover:bg-slate-700 text-emerald-400 hover:text-emerald-300 px-4 py-2 rounded-xl font-semibold text-sm transition-colors border border-slate-700 hover:border-emerald-500/40 cursor-pointer shadow-sm"
                title="Unduh laporan lengkap settlement & bagi hasil event dalam format PDF"
              >
                <FileText class="w-4 h-4 text-emerald-400" />
                <span>Export All PDF</span>
              </button>
            </div>

            <div v-if="loadingTenants || loadingItems" class="flex justify-center py-10">
              <Loader2 class="w-7 h-7 text-slate-400 animate-spin" />
            </div>
            <div v-else-if="settlementRows.length === 0" class="text-center py-10 text-slate-500 text-sm">
              Belum ada tenant di event ini. Masukkan tenant di tab Event & Lineup.
            </div>
            <div v-else class="overflow-x-auto rounded-xl border border-slate-800">
              <table class="w-full text-sm">
                <thead>
                  <tr class="bg-slate-800/90 text-slate-400 text-xs uppercase tracking-wider">
                    <th class="px-4 py-3 text-left">Booth #</th>
                    <th class="px-4 py-3 text-left">Tenant Name</th>
                    <th class="px-4 py-3 text-left">Category</th>
                    <th class="px-4 py-3 text-right">Gross Sales</th>
                    <th class="px-4 py-3 text-right">Venue Cut</th>
                    <th class="px-4 py-3 text-right">Org. Cut</th>
                    <th class="px-4 py-3 text-right">Net Payout</th>
                    <th class="px-4 py-3 text-center">Payout Status</th>
                    <th class="px-4 py-3 text-center">Actions</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-800">
                  <tr
                    v-for="row in settlementRows"
                    :key="row.id"
                    class="hover:bg-slate-800/50 transition-colors"
                  >
                    <td class="px-4 py-3 font-mono text-slate-300 text-xs">{{ row.booth_number || '—' }}</td>
                    <td class="px-4 py-3 font-medium text-slate-100">{{ row.name }}</td>
                    <td class="px-4 py-3 text-slate-400">{{ row.category || '—' }}</td>
                    <td class="px-4 py-3 text-right text-slate-200 font-mono">{{ formatRupiah(row.gross) }}</td>
                    <td class="px-4 py-3 text-right text-violet-400 font-mono font-semibold">{{ formatRupiah(row.venueCut) }}</td>
                    <td class="px-4 py-3 text-right text-amber-400 font-mono font-semibold">{{ formatRupiah(row.orgCut) }}</td>
                    <td class="px-4 py-3 text-right text-emerald-400 font-mono font-semibold">{{ formatRupiah(row.net) }}</td>
                    <td class="px-4 py-3 text-center">
                      <button
                        @click="togglePayoutStatus(row)"
                        :class="row.payout_status === 'SETTLED'
                          ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30 hover:bg-emerald-500/30'
                          : 'bg-amber-500/20 text-amber-400 border-amber-500/30 hover:bg-amber-500/30'"
                        class="inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-semibold border transition-colors cursor-pointer"
                      >
                        <Check v-if="row.payout_status === 'SETTLED'" class="w-3 h-3" />
                        {{ row.payout_status }}
                      </button>
                    </td>
                    <td class="px-4 py-3 text-center">
                      <div class="flex items-center justify-center gap-1.5">
                        <button
                          @click="exportTenantPdf(row)"
                          class="flex items-center gap-1 bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-emerald-400 text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-slate-700 hover:border-emerald-500/40 transition-colors cursor-pointer"
                          :title="`Unduh slip settlement PDF untuk ${row.name}`"
                        >
                          <FileText class="w-3.5 h-3.5 text-emerald-400" />
                          <span>PDF</span>
                        </button>
                        <button
                          @click="copyTenantWaSummary(row)"
                          :class="copiedWaId === row.id
                            ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                            : 'bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-green-400 border-slate-700 hover:border-green-500/40'"
                          class="flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg border transition-colors cursor-pointer"
                          :title="`Salin ringkasan settlement WhatsApp untuk ${row.name}`"
                        >
                          <Check v-if="copiedWaId === row.id" class="w-3.5 h-3.5 text-emerald-400" />
                          <MessageSquare v-else class="w-3.5 h-3.5 text-green-400" />
                          <span>{{ copiedWaId === row.id ? 'Tersalin' : 'WA' }}</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
                <!-- Totals footer -->
                <tfoot>
                  <tr class="bg-slate-800/80 text-xs font-bold border-t-2 border-slate-700">
                    <td colspan="3" class="px-4 py-3 text-slate-400 uppercase tracking-wider">Totals</td>
                    <td class="px-4 py-3 text-right text-slate-200 font-mono">{{ formatRupiah(totalGross) }}</td>
                    <td class="px-4 py-3 text-right text-violet-400 font-mono">{{ formatRupiah(totalVenueCut) }}</td>
                    <td class="px-4 py-3 text-right text-amber-400 font-mono">{{ formatRupiah(totalOrganizerCut) }}</td>
                    <td class="px-4 py-3 text-right text-emerald-400 font-mono">{{ formatRupiah(totalTenantNet) }}</td>
                    <td colspan="2"></td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </section>
        </template>
      </div>

      <!-- ════════════════════════════════════════════════════════════════
           TAB 2: EVENT & LINEUP
      ═════════════════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'lineup'" class="space-y-8">

        <!-- ── Section 1: Event Management ──────────────────────────────── -->
      <section class="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-5">
        <div class="flex items-center justify-between flex-wrap gap-3">
          <h2 class="text-lg font-bold text-white flex items-center gap-2">
            <TrendingUp class="w-5 h-5 text-sky-400" />
            Event Management
          </h2>
          <button
            @click="showCreateEventForm = !showCreateEventForm"
            class="flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 text-slate-950 px-4 py-2 rounded-xl font-semibold text-sm transition-colors"
          >
            <Plus class="w-4 h-4" />
            Create New Event
            <ChevronUp v-if="showCreateEventForm" class="w-4 h-4" />
            <ChevronDown v-else class="w-4 h-4" />
          </button>
        </div>

        <!-- Event Selector -->
        <div class="flex items-center gap-3 flex-wrap">
          <label class="text-sm font-medium text-slate-400 whitespace-nowrap">Active Event:</label>
          <div class="relative flex-1 max-w-sm">
            <select
              v-model="selectedEventId"
              class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-xl px-4 py-2.5 text-sm appearance-none focus:outline-none focus:ring-2 focus:ring-emerald-500"
            >
              <option value="" disabled>-- Select an event --</option>
              <option v-for="ev in events" :key="ev.id" :value="ev.id">
                {{ ev.name }} {{ ev.event_dates ? `(${ev.event_dates})` : '' }}
              </option>
            </select>
            <ChevronDown class="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
          </div>

          <button
            v-if="selectedEvent"
            @click="openEditEvent"
            :class="showEditEventForm ? 'bg-sky-500 text-slate-950 font-bold' : 'bg-slate-800 hover:bg-slate-700 text-sky-400 border border-slate-700'"
            class="flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
            title="Edit event settings & share %"
          >
            <Pencil class="w-4 h-4" />
            <span>Edit Event</span>
            <ChevronUp v-if="showEditEventForm" class="w-4 h-4" />
            <ChevronDown v-else class="w-4 h-4" />
          </button>

          <Loader2 v-if="loadingEvents" class="w-5 h-5 text-slate-400 animate-spin" />
        </div>

        <!-- Create Event Form (collapsible) -->
        <Transition
          enter-active-class="transition-all duration-200 ease-out"
          enter-from-class="opacity-0 -translate-y-2"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition-all duration-150 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-2"
        >
          <div v-if="showCreateEventForm" class="bg-slate-800/60 border border-slate-700 rounded-xl p-5 space-y-4">
            <h3 class="text-sm font-semibold text-slate-300 uppercase tracking-wider">New Event Details</h3>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Event Name <span class="text-rose-400">*</span></label>
                <input
                  v-model="newEvent.name"
                  type="text"
                  placeholder="e.g. Market Minggu #12"
                  class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 placeholder-slate-500"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Venue</label>
                <input
                  v-model="newEvent.venue"
                  type="text"
                  placeholder="e.g. Lapangan Banteng"
                  class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 placeholder-slate-500"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Event Dates (Calendar Range)</label>
                <DateRangePicker v-model:start="eventStartDate" v-model:end="eventEndDate" />
              </div>
              <div class="space-y-1.5 sm:col-span-2">
                <div class="flex items-center justify-between flex-wrap gap-2">
                  <label class="text-xs font-medium text-slate-400">Default Revenue Split (3-Way)</label>
                  <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
                    Total Potongan: <strong class="text-amber-400">{{ newEventTotalCut }}%</strong> • Hak Tenant: <strong class="text-emerald-400">{{ newEventTenantTakeHome }}%</strong>
                  </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div class="space-y-1">
                    <label class="text-[11px] font-medium text-violet-400 flex items-center justify-between">
                      <span>Venue Share %</span>
                      <span class="text-slate-500 font-normal">Lokasi / Tempat</span>
                    </label>
                    <input
                      v-model.number="newEvent.venue_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-slate-700 border border-slate-600 focus:border-violet-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[11px] font-medium text-amber-400 flex items-center justify-between">
                      <span>Organizer Share %</span>
                      <span class="text-slate-500 font-normal">Penyelenggara / EO</span>
                    </label>
                    <input
                      v-model.number="newEvent.organizer_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-slate-700 border border-slate-600 focus:border-amber-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500/30"
                    />
                  </div>
                </div>
              </div>
            </div>
            <div v-if="createEventError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
              {{ createEventError }}
            </div>
            <div class="flex justify-end gap-3">
              <button
                @click="showCreateEventForm = false"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                @click="createEvent"
                :disabled="creatingEvent"
                class="flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-60 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors"
              >
                <Loader2 v-if="creatingEvent" class="w-4 h-4 animate-spin" />
                <Plus v-else class="w-4 h-4" />
                Create Event
              </button>
            </div>
          </div>
        </Transition>

        <!-- Edit Event Form (collapsible) -->
        <Transition
          enter-active-class="transition-all duration-200 ease-out"
          enter-from-class="opacity-0 -translate-y-2"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition-all duration-150 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-2"
        >
          <div v-if="showEditEventForm" class="bg-slate-800/80 border border-sky-500/30 rounded-xl p-5 space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="text-sm font-semibold text-sky-400 uppercase tracking-wider flex items-center gap-2">
                <Pencil class="w-4 h-4" />
                Edit Event Settings — {{ selectedEvent?.name }}
              </h3>
              <button @click="showEditEventForm = false" class="text-slate-400 hover:text-slate-200 p-1">
                <X class="w-4 h-4" />
              </button>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Event Name <span class="text-rose-400">*</span></label>
                <input
                  v-model="editEventForm.name"
                  type="text"
                  placeholder="e.g. Market Minggu #12"
                  class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-500"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Venue</label>
                <input
                  v-model="editEventForm.venue"
                  type="text"
                  placeholder="e.g. Lapangan Banteng"
                  class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-500"
                />
              </div>
              <div class="space-y-1 sm:col-span-2">
                <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
                  <label class="text-xs font-medium text-slate-400">Event Dates (Calendar Range)</label>
                  <div class="text-xs text-slate-400 flex items-center gap-1.5 flex-wrap">
                    <span>Saat ini:</span>
                    <strong class="text-slate-200 font-mono">{{ editEventForm.event_dates || 'Belum diatur' }}</strong>
                    <span v-if="editDateChanged" class="text-emerald-400 ml-1">
                      → Berubah ke: <strong>{{ formatEventDates(editStartDate, editEndDate) }}</strong>
                    </span>
                    <button
                      v-if="editDateChanged"
                      type="button"
                      @click="editDateChanged = false"
                      class="text-[11px] text-amber-400 hover:underline ml-1 cursor-pointer"
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
                  <label class="text-xs font-medium text-slate-400">Default Revenue Split (3-Way)</label>
                  <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-slate-900 text-slate-300 border border-slate-700">
                    Total Potongan: <strong class="text-amber-400">{{ editEventTotalCut }}%</strong> • Hak Tenant: <strong class="text-emerald-400">{{ editEventTenantTakeHome }}%</strong>
                  </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div class="space-y-1">
                    <label class="text-[11px] font-medium text-violet-400 flex items-center justify-between">
                      <span>Venue Share %</span>
                      <span class="text-slate-500 font-normal">Lokasi / Tempat</span>
                    </label>
                    <input
                      v-model.number="editEventForm.venue_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-slate-700 border border-slate-600 focus:border-violet-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[11px] font-medium text-amber-400 flex items-center justify-between">
                      <span>Organizer Share %</span>
                      <span class="text-slate-500 font-normal">Penyelenggara / EO</span>
                    </label>
                    <input
                      v-model.number="editEventForm.organizer_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-slate-700 border border-slate-600 focus:border-amber-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500/30"
                    />
                  </div>
                </div>
              </div>

              <!-- Bulk Sync Checkbox -->
              <div class="sm:col-span-2">
                <label class="flex items-start gap-3 cursor-pointer bg-slate-900/70 border border-slate-700 rounded-xl p-3.5 select-none hover:border-sky-500/40 transition-colors">
                  <input
                    type="checkbox"
                    v-model="editEventForm.syncTenants"
                    class="mt-0.5 w-4 h-4 rounded text-sky-500 focus:ring-sky-500 border-slate-600 bg-slate-800 accent-sky-500 cursor-pointer"
                  />
                  <div class="text-xs">
                    <span class="text-slate-200 font-semibold block">Terapkan default share % baru ke semua tenant di event ini</span>
                    <span class="text-slate-400 font-normal block mt-0.5">
                      Jika dicentang, persentase bagi hasil pada {{ tenants.length }} tenant terdaftar akan otomatis diselaraskan dengan setting baru.
                    </span>
                  </div>
                </label>
              </div>
            </div>

            <div v-if="editEventError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
              {{ editEventError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="showEditEventForm = false"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                @click="saveEditEvent"
                :disabled="savingEditEvent"
                class="flex items-center gap-2 bg-sky-500 hover:bg-sky-400 disabled:opacity-60 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
              >
                <Loader2 v-if="savingEditEvent" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                Save Changes
              </button>
            </div>
          </div>
        </Transition>
      </section>

      <!-- ── Sections 2–4 shown only when event is selected ────────────── -->
      <template v-if="selectedEventId">

        <!-- ── Section 2: Tenant Management ───────────────────────────── -->
        <section class="bg-slate-900 border border-slate-800 rounded-2xl p-6 space-y-5">
          <div class="flex items-center justify-between flex-wrap gap-3">
            <h2 class="text-lg font-bold text-white flex items-center gap-2">
              <Wallet class="w-5 h-5 text-amber-400" />
              Tenant Management
              <span class="text-sm font-normal text-slate-500">— {{ selectedEvent?.name }}</span>
            </h2>
            <div class="flex items-center gap-2.5 flex-wrap">
              <button
                @click="openAssignLineupModal"
                class="flex items-center gap-2 bg-emerald-600 hover:bg-emerald-500 text-white px-4 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer shadow-sm shadow-emerald-950/40"
                title="Pilih brand dari Master Directory untuk dimasukkan ke event ini"
              >
                <Plus class="w-4 h-4" />
                <span>Pilih dari Master</span>
              </button>
              <button
                @click="showAddTenantForm = !showAddTenantForm"
                class="flex items-center gap-2 bg-amber-500 hover:bg-amber-400 text-slate-950 px-4 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer shadow-sm shadow-amber-950/40"
              >
                <Plus class="w-4 h-4" />
                <span>Tenant Baru</span>
                <ChevronUp v-if="showAddTenantForm" class="w-4 h-4" />
                <ChevronDown v-else class="w-4 h-4" />
              </button>
            </div>
          </div>

          <!-- Lineup Error / Alert Banner -->
          <div
            v-if="lineupError"
            class="flex items-start gap-3 bg-rose-500/10 border border-rose-500/30 rounded-xl p-4 text-rose-300 text-sm"
          >
            <AlertCircle class="w-5 h-5 text-rose-400 shrink-0 mt-0.5" />
            <div class="flex-1">
              <p class="font-semibold text-rose-200">Pemberitahuan Lineup</p>
              <p class="text-xs text-rose-300/90 mt-0.5 leading-relaxed">{{ lineupError }}</p>
            </div>
            <button
              @click="lineupError = ''"
              class="text-rose-400 hover:text-rose-200 p-1 rounded-lg hover:bg-rose-500/20 transition-colors cursor-pointer shrink-0"
              title="Tutup pemberitahuan"
            >
              <X class="w-4 h-4" />
            </button>
          </div>

          <!-- Add Tenant Form (collapsible) -->
          <Transition
            enter-active-class="transition-all duration-200 ease-out"
            enter-from-class="opacity-0 -translate-y-2"
            enter-to-class="opacity-100 translate-y-0"
            leave-active-class="transition-all duration-150 ease-in"
            leave-from-class="opacity-100 translate-y-0"
            leave-to-class="opacity-0 -translate-y-2"
          >
            <div v-if="showAddTenantForm" class="bg-slate-800/60 border border-slate-700 rounded-xl p-5 space-y-4">
              <h3 class="text-sm font-semibold text-slate-300 uppercase tracking-wider">New Tenant Details</h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <div class="space-y-1">
                  <label class="text-xs font-medium text-slate-400">Tenant Name <span class="text-rose-400">*</span></label>
                  <input
                    v-model="newTenant.name"
                    type="text"
                    placeholder="e.g. Warung Kopi Josss"
                    class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 placeholder-slate-500"
                  />
                </div>
                <div class="space-y-1">
                  <label class="text-xs font-medium text-slate-400">Category <span class="text-rose-400">*</span></label>
                  <select
                    v-model="selectedCategory"
                    class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
                  >
                    <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                      {{ cat }}
                    </option>
                  </select>
                </div>
                <div v-if="selectedCategory === 'Other (Custom)'" class="space-y-1 sm:col-span-2 lg:col-span-1">
                  <label class="text-xs font-medium text-amber-400">Custom Category <span class="text-rose-400">*</span></label>
                  <input
                    v-model="customCategory"
                    type="text"
                    placeholder="e.g. Handmade Candles"
                    class="w-full bg-slate-700 border border-amber-500/50 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 placeholder-slate-500"
                  />
                </div>
                <div class="space-y-1">
                  <label class="text-xs font-medium text-slate-400">Booth #</label>
                  <input
                    v-model="newTenant.booth_number"
                    type="text"
                    placeholder="e.g. A-12"
                    class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 placeholder-slate-500"
                  />
                </div>
                <div class="space-y-1.5 sm:col-span-2 lg:col-span-3">
                  <div class="flex items-center justify-between flex-wrap gap-2">
                    <label class="text-xs font-medium text-slate-400">Revenue Split (3-Way)</label>
                    <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
                      Total Potongan: <strong class="text-amber-400">{{ newTenantTotalCut }}%</strong> • Hak Tenant: <strong class="text-emerald-400">{{ newTenantTakeHome }}%</strong>
                    </span>
                  </div>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div class="space-y-1">
                      <label class="text-[11px] font-medium text-violet-400 flex items-center justify-between">
                        <span>Venue Share %</span>
                        <span class="text-slate-500 font-normal">Lokasi / Tempat</span>
                      </label>
                      <input
                        v-model.number="newTenant.venue_share_percent"
                        type="number"
                        min="0"
                        max="100"
                        step="0.5"
                        class="w-full bg-slate-700 border border-slate-600 focus:border-violet-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                      />
                    </div>
                    <div class="space-y-1">
                      <label class="text-[11px] font-medium text-amber-400 flex items-center justify-between">
                        <span>Organizer Share %</span>
                        <span class="text-slate-500 font-normal">Penyelenggara / EO</span>
                      </label>
                      <input
                        v-model.number="newTenant.organizer_share_percent"
                        type="number"
                        min="0"
                        max="100"
                        step="0.5"
                        class="w-full bg-slate-700 border border-slate-600 focus:border-amber-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500/30"
                      />
                    </div>
                  </div>
                </div>
                <div class="space-y-1 sm:col-span-2 lg:col-span-3">
                  <label class="text-xs font-medium text-slate-400">Bank Info (for payout)</label>
                  <input
                    v-model="newTenant.bank_info"
                    type="text"
                    placeholder="e.g. BCA 1234567890 a/n Budi"
                    class="w-full bg-slate-700 border border-slate-600 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 placeholder-slate-500"
                  />
                </div>
              </div>
              <div v-if="addTenantError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
                {{ addTenantError }}
              </div>
              <div class="flex justify-end gap-3">
                <button
                  @click="showAddTenantForm = false"
                  class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
                >
                  Cancel
                </button>
                <button
                  @click="addTenant"
                  :disabled="addingTenant"
                  class="flex items-center gap-2 bg-amber-500 hover:bg-amber-400 disabled:opacity-60 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors"
                >
                  <Loader2 v-if="addingTenant" class="w-4 h-4 animate-spin" />
                  <Plus v-else class="w-4 h-4" />
                  Add Tenant
                </button>
              </div>
            </div>
          </Transition>

          <!-- Tenant List Table -->
          <div v-if="loadingTenants" class="flex justify-center py-10">
            <Loader2 class="w-7 h-7 text-slate-400 animate-spin" />
          </div>
          <div v-else-if="tenants.length === 0" class="text-center py-10 text-slate-500 text-sm">
            No tenants for this event yet. Add one above.
          </div>
          <div v-else class="overflow-x-auto rounded-xl border border-slate-800">
            <table class="w-full text-sm">
              <thead>
                <tr class="bg-slate-800 text-slate-400 text-xs uppercase tracking-wider">
                  <th class="px-4 py-3 text-left">Booth #</th>
                  <th class="px-4 py-3 text-left">Name</th>
                  <th class="px-4 py-3 text-left">Category</th>
                  <th class="px-4 py-3 text-center">Share % (Venue / EO)</th>
                  <th class="px-4 py-3 text-center">Payout Status</th>
                  <th class="px-4 py-3 text-left">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-800">
                <tr
                  v-for="tenant in tenants"
                  :key="tenant.id"
                  class="hover:bg-slate-800/50 transition-colors"
                >
                  <td class="px-4 py-3 font-mono text-slate-300">{{ tenant.booth_number || '—' }}</td>
                  <td class="px-4 py-3 font-medium text-slate-100">{{ tenant.name }}</td>
                  <td class="px-4 py-3 text-slate-400">{{ tenant.category || '—' }}</td>
                  <td class="px-4 py-3 text-center font-medium">
                    <span class="text-violet-400">{{ tenant.venue_share_percent ?? 10 }}%</span>
                    <span class="text-slate-500 mx-1">/</span>
                    <span class="text-amber-400">{{ tenant.organizer_share_percent ?? 0 }}%</span>
                    <span class="block text-[10px] text-slate-400 font-normal">Total: {{ (Number(tenant.venue_share_percent ?? 10) + Number(tenant.organizer_share_percent ?? 0)) }}%</span>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <span
                      :class="tenant.payout_status === 'SETTLED'
                        ? 'bg-emerald-400/15 text-emerald-400 border border-emerald-400/30'
                        : 'bg-amber-400/15 text-amber-400 border border-amber-400/30'"
                      class="inline-block px-2.5 py-0.5 rounded-full text-xs font-semibold"
                    >
                      {{ tenant.payout_status }}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <div class="flex items-center gap-2">
                      <button
                        @click="openEditTenant(tenant)"
                        class="flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-slate-700 bg-slate-800 hover:bg-slate-700 text-sky-400 hover:text-sky-300 transition-colors cursor-pointer"
                        title="Edit tenant / share override"
                      >
                        <Pencil class="w-3.5 h-3.5" />
                        Edit
                      </button>
                      <button
                        @click="copyPortalLink(tenant)"
                        :class="copiedId === tenant.id
                          ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                          : 'bg-slate-700 hover:bg-slate-600 text-slate-300 border-slate-600'"
                        class="flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1.5 rounded-lg border transition-colors cursor-pointer"
                        title="Copy private portal link"
                      >
                        <Check v-if="copiedId === tenant.id" class="w-3.5 h-3.5" />
                        <Copy v-else class="w-3.5 h-3.5" />
                        {{ copiedId === tenant.id ? 'Copied!' : 'Portal' }}
                      </button>
                      <button
                        @click="removeTenantFromLineup(tenant)"
                        class="p-1.5 rounded-lg border border-slate-700 bg-slate-800 hover:bg-rose-500/20 text-slate-400 hover:text-rose-400 hover:border-rose-500/30 transition-colors cursor-pointer"
                        title="Hapus tenant dari lineup event ini"
                      >
                        <Trash2 class="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

      </template>

      <!-- Placeholder when no event is selected (in Tab 2) -->
      <div v-else class="bg-slate-900 border border-slate-800 rounded-2xl p-12 text-center space-y-3">
        <Building2 class="w-10 h-10 text-slate-700 mx-auto" />
        <p class="text-slate-300 text-base font-semibold">Pilih atau Buat Event Baru</p>
        <p class="text-slate-500 text-sm">Gunakan tombol "Create New Event" di atas untuk memulai lineup tenant event baru.</p>
      </div>
    </div>

      <!-- ════════════════════════════════════════════════════════════════
           TAB 3: MASTER TENANT DIRECTORY
      ═════════════════════════════════════════════════════════════════ -->
      <div v-else-if="activeTab === 'master'" class="space-y-6">
        <!-- Directory Header -->
        <section class="bg-slate-900 border border-slate-800 rounded-2xl p-6 flex flex-wrap items-center justify-between gap-4">
          <div>
            <h2 class="text-xl font-bold text-white flex items-center gap-2">
              <Store class="w-6 h-6 text-sky-400" />
              Master Tenant Directory
            </h2>
            <p class="text-xs sm:text-sm text-slate-400 mt-1">
              Katalog master brand & vendor terpusat. Simpan profil vendor sekali dan gunakan berulang kali di berbagai event.
            </p>
          </div>
          <button
            @click="openAddMasterModal"
            class="flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 text-slate-950 px-5 py-2.5 rounded-xl font-bold text-sm transition-colors cursor-pointer"
          >
            <Plus class="w-4 h-4" />
            Tambah Master Brand
          </button>
        </section>

        <!-- Search & Filter Bar with Category Pills -->
        <section class="bg-slate-900 border border-slate-800 rounded-2xl p-4 space-y-3">
          <!-- Horizontal Category Filter Pills -->
          <div class="flex items-center gap-2 overflow-x-auto pb-1.5 scrollbar-thin">
            <button
              v-for="pill in masterCategoriesWithCounts"
              :key="pill.key"
              type="button"
              @click="masterCategoryFilter = pill.key"
              :class="[
                'flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition-all duration-150 cursor-pointer',
                masterCategoryFilter === pill.key
                  ? 'bg-sky-500 text-slate-950 shadow-md shadow-sky-500/20'
                  : 'bg-slate-800 text-slate-400 hover:text-slate-200 border border-slate-700 hover:bg-slate-700/70'
              ]"
            >
              <span>{{ pill.label }}</span>
              <span
                :class="[
                  'px-1.5 py-0.5 rounded-full text-[10px] font-bold',
                  masterCategoryFilter === pill.key
                    ? 'bg-slate-950/20 text-slate-950'
                    : 'bg-slate-900 text-slate-400 border border-slate-700'
                ]"
              >
                {{ pill.count }}
              </span>
            </button>
          </div>

          <div class="flex flex-wrap items-center justify-between gap-4 pt-1 border-t border-slate-800/80">
            <div class="flex items-center gap-3 flex-1 min-w-[280px]">
              <div class="relative flex-1">
                <Search class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                <input
                  v-model="masterSearchQuery"
                  type="text"
                  placeholder="Cari nama brand, instagram, PIC, WhatsApp, bank, atau rekening…"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-xl pl-9 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-500"
                />
              </div>
            </div>
            <div class="text-xs font-medium text-slate-400">
              Menampilkan <strong class="text-sky-400">{{ filteredMasterTenants.length }}</strong> dari <strong class="text-slate-300">{{ masterTenants.length }}</strong> brand
            </div>
          </div>
        </section>

        <!-- Master Tenants Table -->
        <section class="bg-slate-900 border border-slate-800 rounded-2xl p-6">
          <div v-if="loadingMasterTenants" class="flex justify-center py-12">
            <Loader2 class="w-8 h-8 text-sky-400 animate-spin" />
          </div>

          <div v-else-if="filteredMasterTenants.length === 0" class="text-center py-12 space-y-3">
            <Store class="w-10 h-10 text-slate-700 mx-auto" />
            <p class="text-slate-400 text-sm">Tidak ada brand master ditemukan.</p>
            <button
              v-if="masterSearchQuery || masterCategoryFilter !== 'ALL'"
              @click="masterSearchQuery = ''; masterCategoryFilter = 'ALL'"
              class="text-xs text-sky-400 hover:underline cursor-pointer"
            >
              Reset filter & pencarian
            </button>
          </div>

          <div v-else class="overflow-x-auto rounded-xl border border-slate-800">
            <table class="w-full text-sm">
              <thead>
                <tr class="bg-slate-800/80 text-slate-400 text-xs uppercase tracking-wider">
                  <th class="px-4 py-3 text-left">Brand Name</th>
                  <th class="px-4 py-3 text-left">Kategori</th>
                  <th class="px-4 py-3 text-left">PIC & Kontak</th>
                  <th class="px-4 py-3 text-left">Bank / Rekening</th>
                  <th class="px-4 py-3 text-center">Status di Event Aktif</th>
                  <th class="px-4 py-3 text-center">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-800">
                <tr
                  v-for="m in filteredMasterTenants"
                  :key="m.id"
                  class="hover:bg-slate-800/50 transition-colors"
                >
                  <td class="px-4 py-3">
                    <div class="flex items-center gap-2 flex-wrap">
                      <span class="font-bold text-slate-100 block">{{ m.name }}</span>
                      <a
                        v-if="m.instagram"
                        :href="'https://instagram.com/' + m.instagram.replace(/^@/, '')"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center gap-0.5 text-[11px] font-semibold text-pink-400 hover:text-pink-300 hover:underline bg-pink-500/10 border border-pink-500/20 rounded-md px-1.5 py-0.5"
                      >
                        @{{ m.instagram.replace(/^@/, '') }}
                      </a>
                    </div>
                    <span class="text-[11px] text-slate-400 block mt-0.5">
                      {{ m.lastEventName ? `Event terakhir: ${m.lastEventName}` : 'Belum pernah ikut event' }}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <span class="inline-block px-2.5 py-0.5 rounded-md text-xs font-medium bg-slate-800 text-slate-300 border border-slate-700">
                      {{ m.category || '—' }}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-xs">
                    <div v-if="m.pic_name || m.whatsapp" class="space-y-0.5">
                      <span v-if="m.pic_name" class="font-medium text-slate-200 block">{{ m.pic_name }}</span>
                      <div v-if="m.whatsapp" class="flex items-center gap-1 text-slate-400 font-mono text-[11px]">
                        <span class="text-emerald-400 font-semibold">WA:</span>
                        <a
                          :href="'https://wa.me/' + m.whatsapp.replace(/\D/g, '')"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="hover:text-emerald-300 hover:underline"
                        >
                          {{ m.whatsapp }}
                        </a>
                      </div>
                    </div>
                    <span v-else class="text-slate-400">{{ m.contact_info || '—' }}</span>
                  </td>
                  <td class="px-4 py-3 text-xs">
                    <div v-if="m.bank_name || m.bank_account" class="space-y-0.5">
                      <div class="flex items-center gap-1.5">
                        <span v-if="m.bank_name" class="font-bold text-slate-200 uppercase tracking-wide">{{ m.bank_name }}</span>
                        <span v-if="m.bank_account" class="font-mono text-slate-300">{{ m.bank_account }}</span>
                      </div>
                      <span v-if="m.bank_holder" class="text-[11px] text-slate-400 block">
                        a.n. {{ m.bank_holder }}
                      </span>
                    </div>
                    <span v-else class="font-mono text-slate-300">{{ m.bank_info || '—' }}</span>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <span
                      v-if="tenants.some((t) => t.master_tenant_id === m.id || t.name.toLowerCase().trim() === m.name.toLowerCase().trim())"
                      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/15 text-emerald-400 border border-emerald-500/30"
                    >
                      <Check class="w-3 h-3" />
                      Terdaftar (Booth {{ tenants.find((t) => t.master_tenant_id === m.id || t.name.toLowerCase().trim() === m.name.toLowerCase().trim())?.booth_number || '—' }})
                    </span>
                    <span
                      v-else-if="selectedEventId"
                      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-slate-800 text-slate-400 border border-slate-700"
                    >
                      Belum di event ini
                    </span>
                    <span
                      v-else
                      class="text-xs text-slate-500 italic"
                    >
                      Pilih event di Tab 1/2
                    </span>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <div class="flex items-center justify-center gap-2">
                      <button
                        @click="openAssignSingleMasterModal(m)"
                        :disabled="events.length === 0"
                        class="flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-slate-700 bg-slate-800 hover:bg-emerald-500/20 text-emerald-400 hover:text-emerald-300 hover:border-emerald-500/40 disabled:opacity-40 disabled:pointer-events-none transition-colors cursor-pointer"
                        :title="events.length === 0 ? 'Belum ada event' : 'Tugaskan brand ke event'"
                      >
                        <Plus class="w-3.5 h-3.5" />
                        <span>Assign</span>
                      </button>
                      <button
                        @click="openEditMasterModal(m)"
                        class="p-1.5 rounded-lg border border-slate-700 bg-slate-800 hover:bg-slate-700 text-sky-400 hover:text-sky-300 transition-colors cursor-pointer"
                        title="Edit profil brand"
                      >
                        <Pencil class="w-3.5 h-3.5" />
                      </button>
                      <button
                        @click="deleteMasterTenant(m)"
                        class="p-1.5 rounded-lg border border-slate-700 bg-slate-800 hover:bg-rose-500/20 text-slate-400 hover:text-rose-400 hover:border-rose-500/30 transition-colors cursor-pointer"
                        title="Hapus dari master directory"
                      >
                        <Trash2 class="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

    </main>

    <!-- ── Edit Tenant Modal ─────────────────────────────────────────── -->
    <Transition name="modal">
      <div v-if="editingTenantModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="closeEditTenantModal" />
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-lg shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-800/40">
            <div>
              <p class="text-xs text-sky-400 font-semibold uppercase tracking-wider">Tenant Override Settings</p>
              <h3 class="font-bold text-slate-100 text-base mt-0.5">{{ editingTenant?.name }}</h3>
            </div>
            <button @click="closeEditTenantModal" class="text-slate-400 hover:text-slate-200 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 space-y-4 max-h-[80vh] overflow-y-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Tenant Name <span class="text-rose-400">*</span></label>
                <input
                  v-model="editingTenant.name"
                  type="text"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Booth #</label>
                <input
                  v-model="editingTenant.booth_number"
                  type="text"
                  placeholder="e.g. A-12"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Category <span class="text-rose-400">*</span></label>
                <select
                  v-model="editTenantCategory"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                >
                  <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
              </div>

              <div v-if="editTenantCategory === 'Other (Custom)'" class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-amber-400">Custom Category <span class="text-rose-400">*</span></label>
                <input
                  v-model="editTenantCustomCategory"
                  type="text"
                  placeholder="e.g. Handmade Candles"
                  class="w-full bg-slate-800 border border-amber-500/50 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Bank Info (for payout)</label>
                <input
                  v-model="editingTenant.bank_info"
                  type="text"
                  placeholder="e.g. BCA 1234567890 a/n Budi"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <!-- Revenue Split 3-Way Override -->
              <div class="space-y-2 sm:col-span-2 bg-slate-800/50 border border-slate-700/80 rounded-xl p-4">
                <div class="flex items-center justify-between flex-wrap gap-2">
                  <label class="text-xs font-semibold text-slate-300">Custom Revenue Split (3-Way)</label>
                  <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-slate-900 text-slate-300 border border-slate-700">
                    Total Potongan: <strong class="text-amber-400">{{ editTenantTotalCut }}%</strong> • Hak Tenant: <strong class="text-emerald-400">{{ editTenantTakeHome }}%</strong>
                  </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                  <div class="space-y-1">
                    <label class="text-[11px] font-medium text-violet-400">Venue Share %</label>
                    <input
                      v-model.number="editingTenant.venue_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-slate-700 border border-slate-600 focus:border-violet-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500/30"
                    />
                  </div>
                  <div class="space-y-1">
                    <label class="text-[11px] font-medium text-amber-400">Organizer Share %</label>
                    <input
                      v-model.number="editingTenant.organizer_share_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.5"
                      class="w-full bg-slate-700 border border-slate-600 focus:border-amber-500 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500/30"
                    />
                  </div>
                </div>
              </div>
            </div>

            <div v-if="editTenantError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
              {{ editTenantError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="closeEditTenantModal"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                @click="saveEditTenant"
                :disabled="savingEditTenant"
                class="flex items-center gap-2 bg-sky-500 hover:bg-sky-400 disabled:opacity-60 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
              >
                <Loader2 v-if="savingEditTenant" class="w-4 h-4 animate-spin" />
                <Check v-else class="w-4 h-4" />
                Save Changes
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
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-3xl shadow-2xl z-10 overflow-hidden flex flex-col max-h-[90vh]">
          <!-- Header -->
          <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-800/40">
            <div>
              <p class="text-xs text-emerald-400 font-semibold uppercase tracking-wider">Event Lineup Builder</p>
              <h3 class="font-bold text-slate-100 text-lg mt-0.5">Assign Brands from Master Directory</h3>
            </div>
            <button @click="showAssignLineupModal = false" class="text-slate-400 hover:text-slate-200 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <!-- Filters bar -->
          <div class="p-4 border-b border-slate-800 bg-slate-800/20 flex flex-wrap gap-3 items-center justify-between">
            <div class="flex items-center gap-3 flex-1 min-w-[240px]">
              <div class="relative flex-1">
                <Search class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                <input
                  v-model="assignLineupSearch"
                  type="text"
                  placeholder="Cari brand master atau kategori…"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-xl pl-9 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 placeholder-slate-500"
                />
              </div>
              <div class="relative min-w-[170px]">
                <select
                  v-model="assignLineupCategory"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-xl px-3 py-2 text-sm appearance-none focus:outline-none focus:ring-2 focus:ring-emerald-500 pr-8 cursor-pointer"
                >
                  <option value="ALL">Semua Kategori</option>
                  <option v-for="cat in PRESET_CATEGORIES.filter(c => c !== 'Other (Custom)')" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
                <ChevronDown class="w-4 h-4 absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
              </div>
            </div>

            <div class="text-xs text-slate-400">
              Target: <strong class="text-white">{{ selectedEvent?.name }}</strong>
            </div>
          </div>

          <!-- Body / List -->
          <div class="flex-1 overflow-y-auto p-4 space-y-3">
            <div v-if="filteredLineupMasterTenants.length === 0" class="text-center py-12 text-slate-500 text-sm">
              Tidak ada brand master yang cocok.
            </div>

            <div v-else class="space-y-2">
              <div class="flex items-center justify-between px-2 text-xs text-slate-400 mb-1">
                <button
                  type="button"
                  @click="toggleSelectAllLineupMasters"
                  class="text-emerald-400 hover:underline font-semibold cursor-pointer"
                >
                  Pilih / Batal Semua yang Tersedia
                </button>
                <span>{{ filteredLineupMasterTenants.length }} brands ditemukan</span>
              </div>

              <div
                v-for="m in filteredLineupMasterTenants"
                :key="m.id"
                :class="[
                  'border rounded-xl p-3 flex items-center gap-3 transition-colors',
                  activeEventMasterIds.has(m.id) || activeEventTenantNames.has(m.name.toLowerCase().trim())
                    ? 'bg-slate-800/30 border-slate-800 opacity-60'
                    : selectedMasterIds.has(m.id)
                      ? 'bg-emerald-500/10 border-emerald-500/40'
                      : 'bg-slate-800/60 border-slate-700/60 hover:border-slate-600'
                ]"
              >
                <!-- Checkbox -->
                <input
                  type="checkbox"
                  :disabled="activeEventMasterIds.has(m.id) || activeEventTenantNames.has(m.name.toLowerCase().trim())"
                  :checked="selectedMasterIds.has(m.id)"
                  @change="toggleSelectMaster(m)"
                  class="w-4 h-4 rounded text-emerald-500 focus:ring-emerald-500 border-slate-600 bg-slate-800 accent-emerald-500 cursor-pointer disabled:cursor-not-allowed"
                />

                <!-- Master Info -->
                <div class="flex-1 min-w-0 cursor-pointer" @click="toggleSelectMaster(m)">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="font-semibold text-slate-100 text-sm truncate">{{ m.name }}</span>
                    <span class="text-xs bg-slate-700 text-slate-300 rounded-md px-2 py-0.5">{{ m.category || 'Umum' }}</span>
                    <span
                      v-if="activeEventMasterIds.has(m.id) || activeEventTenantNames.has(m.name.toLowerCase().trim())"
                      class="text-[10px] font-semibold bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 rounded-md px-1.5 py-0.5"
                    >
                      Sudah di Lineup
                    </span>
                  </div>
                  <div class="flex items-center gap-2 text-xs text-slate-400 mt-1 flex-wrap">
                    <span class="text-slate-500">Event terakhir:</span>
                    <span v-if="m.lastEventName" class="text-sky-400 font-semibold">{{ m.lastEventName }}</span>
                    <span v-else class="text-slate-500 italic">Belum pernah ikut event</span>
                    <span v-if="m.contact_info" class="text-slate-500">• {{ m.contact_info }}</span>
                    <span v-if="m.bank_info" class="text-slate-600 font-mono text-[11px]">• {{ m.bank_info }}</span>
                  </div>
                </div>

                <!-- Booth Input -->
                <div v-if="!activeEventMasterIds.has(m.id) && !activeEventTenantNames.has(m.name.toLowerCase().trim())" class="w-28 flex-shrink-0">
                  <label class="text-[10px] text-slate-400 block mb-0.5">Booth #:</label>
                  <input
                    v-model="lineupAssignBooths[m.id]"
                    type="text"
                    placeholder="e.g. B-01"
                    @focus="selectedMasterIds.add(m.id)"
                    class="w-full bg-slate-700 border border-slate-600 focus:border-emerald-500 text-slate-100 rounded-lg px-2 py-1 text-xs focus:outline-none"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="px-6 py-4 border-t border-slate-800 bg-slate-800/40 flex items-center justify-between flex-wrap gap-3">
            <span class="text-xs text-slate-400 font-medium">
              Terpilih: <strong class="text-emerald-400">{{ selectedMasterIds.size }}</strong> brand
            </span>
            <div class="flex items-center gap-3">
              <button
                @click="showAssignLineupModal = false"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors cursor-pointer"
              >
                Cancel
              </button>
              <button
                @click="confirmAssignMastersToLineup"
                :disabled="selectedMasterIds.size === 0 || assigningLineup"
                class="flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
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
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-lg shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-800/40">
            <div>
              <p class="text-xs text-emerald-400 font-semibold uppercase tracking-wider">Master Directory</p>
              <h3 class="font-bold text-slate-100 text-base mt-0.5">Tambah Brand Master Baru</h3>
            </div>
            <button @click="showAddMasterModal = false" class="text-slate-400 hover:text-slate-200 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 space-y-4 max-h-[80vh] overflow-y-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <!-- Brand Name -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Nama Brand <span class="text-rose-400">*</span></label>
                <input
                  v-model="newMasterTenant.name"
                  type="text"
                  placeholder="e.g. Kopi Tuku / SneakerLab"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>

              <!-- Kategori -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Kategori <span class="text-rose-400">*</span></label>
                <select
                  v-model="newMasterTenant.category"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                >
                  <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
              </div>

              <div v-if="newMasterTenant.category === 'Other (Custom)'" class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-amber-400">Custom Category <span class="text-rose-400">*</span></label>
                <input
                  v-model="newMasterTenant.customCategory"
                  type="text"
                  placeholder="e.g. Leather Craft"
                  class="w-full bg-slate-800 border border-amber-500/50 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>

              <!-- Kontak Brand & PIC -->
              <div class="sm:col-span-2 pt-2 border-t border-slate-800">
                <span class="text-xs font-semibold text-slate-300 uppercase tracking-wider block">Kontak Brand & PIC (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Instagram (@handle)</label>
                <input
                  v-model="newMasterTenant.instagram"
                  type="text"
                  placeholder="e.g. @kopituku"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nama PIC</label>
                <input
                  v-model="newMasterTenant.pic_name"
                  type="text"
                  placeholder="e.g. Nadia Kusuma"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Nomor WhatsApp PIC</label>
                <input
                  v-model="newMasterTenant.whatsapp"
                  type="text"
                  placeholder="e.g. 081234567890"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>

              <!-- Informasi Rekening Bank -->
              <div class="sm:col-span-2 pt-2 border-t border-slate-800">
                <span class="text-xs font-semibold text-slate-300 uppercase tracking-wider block">Informasi Rekening Bank (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nama Bank</label>
                <input
                  v-model="newMasterTenant.bank_name"
                  type="text"
                  placeholder="e.g. BCA / Mandiri"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nomor Rekening</label>
                <input
                  v-model="newMasterTenant.bank_account"
                  type="text"
                  placeholder="e.g. 0118492031"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 font-mono"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Atas Nama Rekening</label>
                <input
                  v-model="newMasterTenant.bank_holder"
                  type="text"
                  placeholder="e.g. Nadia Kusuma Putri"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>
            </div>

            <div v-if="createMasterError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
              {{ createMasterError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="showAddMasterModal = false"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                @click="createMasterTenant"
                :disabled="creatingMaster"
                class="flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-60 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
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
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-lg shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-800/40">
            <div>
              <p class="text-xs text-sky-400 font-semibold uppercase tracking-wider">Master Directory</p>
              <h3 class="font-bold text-slate-100 text-base mt-0.5">Edit Profil Brand Master</h3>
            </div>
            <button @click="editingMasterModal = false" class="text-slate-400 hover:text-slate-200 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 space-y-4 max-h-[80vh] overflow-y-auto">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <!-- Brand Name -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Nama Brand <span class="text-rose-400">*</span></label>
                <input
                  v-model="editingMasterTenant.name"
                  type="text"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <!-- Kategori -->
              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Kategori <span class="text-rose-400">*</span></label>
                <select
                  v-model="editMasterCategory"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                >
                  <option v-for="cat in PRESET_CATEGORIES" :key="cat" :value="cat">
                    {{ cat }}
                  </option>
                </select>
              </div>

              <div v-if="editMasterCategory === 'Other (Custom)'" class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-amber-400">Custom Category <span class="text-rose-400">*</span></label>
                <input
                  v-model="editMasterCustomCategory"
                  type="text"
                  placeholder="e.g. Leather Craft"
                  class="w-full bg-slate-800 border border-amber-500/50 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>

              <!-- Kontak Brand & PIC -->
              <div class="sm:col-span-2 pt-2 border-t border-slate-800">
                <span class="text-xs font-semibold text-slate-300 uppercase tracking-wider block">Kontak Brand & PIC (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Instagram (@handle)</label>
                <input
                  v-model="editingMasterTenant.instagram"
                  type="text"
                  placeholder="e.g. @kopituku"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nama PIC</label>
                <input
                  v-model="editingMasterTenant.pic_name"
                  type="text"
                  placeholder="e.g. Nadia Kusuma"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Nomor WhatsApp PIC</label>
                <input
                  v-model="editingMasterTenant.whatsapp"
                  type="text"
                  placeholder="e.g. 081234567890"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <!-- Informasi Rekening Bank -->
              <div class="sm:col-span-2 pt-2 border-t border-slate-800">
                <span class="text-xs font-semibold text-slate-300 uppercase tracking-wider block">Informasi Rekening Bank (Opsional)</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nama Bank</label>
                <input
                  v-model="editingMasterTenant.bank_name"
                  type="text"
                  placeholder="e.g. BCA / Mandiri"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nomor Rekening</label>
                <input
                  v-model="editingMasterTenant.bank_account"
                  type="text"
                  placeholder="e.g. 0118492031"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500 font-mono"
                />
              </div>

              <div class="space-y-1 sm:col-span-2">
                <label class="text-xs font-medium text-slate-400">Atas Nama Rekening</label>
                <input
                  v-model="editingMasterTenant.bank_holder"
                  type="text"
                  placeholder="e.g. Nadia Kusuma Putri"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
                />
              </div>
            </div>

            <div v-if="editMasterError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
              {{ editMasterError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="editingMasterModal = false"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                @click="saveEditMasterTenant"
                :disabled="savingMaster"
                class="flex items-center gap-2 bg-sky-500 hover:bg-sky-400 disabled:opacity-60 text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
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
        <div class="relative bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-md shadow-2xl z-10 overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-800/40">
            <div>
              <p class="text-xs text-emerald-400 font-semibold uppercase tracking-wider">Tugaskan Brand ke Event</p>
              <h3 class="font-bold text-slate-100 text-base mt-0.5">{{ targetMasterTenant?.name }}</h3>
            </div>
            <button @click="assigningMasterModal = false" class="text-slate-400 hover:text-slate-200 p-1 rounded-lg hover:bg-slate-800 transition-colors">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 space-y-4">
            <div class="space-y-3">
              <div class="space-y-1.5">
                <label class="text-xs font-medium text-slate-400">Target Event <span class="text-rose-400">*</span></label>
                <div class="relative">
                  <select
                    v-model="assignTargetEventId"
                    class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-xl px-3 py-2.5 text-sm appearance-none focus:outline-none focus:ring-2 focus:ring-emerald-500 pr-8 cursor-pointer"
                  >
                    <option v-for="ev in events" :key="ev.id" :value="ev.id">
                      {{ ev.name }} ({{ ev.venue || 'No Venue' }})
                    </option>
                  </select>
                  <ChevronDown class="w-4 h-4 absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                </div>
              </div>

              <!-- Target Event Revenue Split & Details -->
              <div v-if="assignTargetEvent" class="bg-slate-800/60 border border-slate-700/60 rounded-xl p-3 text-xs space-y-1.5">
                <div class="flex items-center justify-between text-slate-300">
                  <span class="text-slate-400">Default Split:</span>
                  <span class="font-medium">
                    Venue <strong class="text-violet-400">{{ assignTargetEvent.venue_share_percent ?? 10 }}%</strong>
                    • EO <strong class="text-amber-400">{{ assignTargetEvent.organizer_share_percent ?? 0 }}%</strong>
                    • Tenant <strong class="text-emerald-400">{{ Math.max(0, 100 - (Number(assignTargetEvent.venue_share_percent ?? 10) + Number(assignTargetEvent.organizer_share_percent ?? 0))) }}%</strong>
                  </span>
                </div>
                <div v-if="assignTargetEvent.event_dates" class="text-[11px] text-slate-500">
                  Tanggal: {{ assignTargetEvent.event_dates }}
                </div>
              </div>

              <!-- Warning if brand is already registered in this target event -->
              <div v-if="isBrandAlreadyInTargetEvent" class="flex items-center gap-2.5 p-3 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-300 text-xs">
                <AlertCircle class="w-4 h-4 shrink-0 text-amber-400" />
                <span>Brand ini sudah terdaftar di lineup event terpilih.</span>
              </div>

              <div class="space-y-1">
                <label class="text-xs font-medium text-slate-400">Nomor Booth di Event Ini</label>
                <input
                  v-model="assignBoothNumber"
                  type="text"
                  placeholder="e.g. A-08"
                  class="w-full bg-slate-800 border border-slate-700 text-slate-100 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>
            </div>

            <div v-if="assignMasterError" class="text-sm text-rose-400 bg-rose-400/10 border border-rose-400/30 rounded-lg px-3 py-2">
              {{ assignMasterError }}
            </div>

            <div class="flex justify-end gap-3 pt-2">
              <button
                @click="assigningMasterModal = false"
                class="px-4 py-2 rounded-xl text-sm font-semibold text-slate-400 hover:text-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                @click="confirmAssignMasterToActiveEvent"
                :disabled="assigningToActiveEvent || isBrandAlreadyInTargetEvent || !assignTargetEventId"
                class="flex items-center gap-2 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50 disabled:cursor-not-allowed text-slate-950 px-5 py-2 rounded-xl font-semibold text-sm transition-colors cursor-pointer"
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
        class="fixed bottom-6 right-6 z-50 max-w-md shadow-2xl rounded-2xl border p-4 flex items-start gap-3 backdrop-blur-md"
        :class="{
          'bg-slate-900/95 border-emerald-500/40 text-emerald-300': toast.type === 'success',
          'bg-slate-900/95 border-rose-500/40 text-rose-300': toast.type === 'error',
          'bg-slate-900/95 border-sky-500/40 text-sky-300': toast.type === 'info',
        }"
      >
        <CheckCircle2 v-if="toast.type === 'success'" class="w-5 h-5 text-emerald-400 shrink-0 mt-0.5" />
        <AlertCircle v-else-if="toast.type === 'error'" class="w-5 h-5 text-rose-400 shrink-0 mt-0.5" />
        <AlertCircle v-else class="w-5 h-5 text-sky-400 shrink-0 mt-0.5" />

        <div class="flex-1 text-xs sm:text-sm font-medium leading-relaxed">
          {{ toast.message }}
        </div>

        <button
          @click="toast.show = false"
          class="p-1 rounded-lg hover:bg-white/10 text-slate-400 hover:text-slate-200 transition-colors cursor-pointer shrink-0"
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
