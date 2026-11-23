<script setup>
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuth } from '@/lib/useAuth.js'
import { useEvents } from '@/lib/useEvents.js'

const route = useRoute()
const router = useRouter()
const { signOut, user } = useAuth()
const { events, activeEvent, selectedEventId, selectEventId, isEventActive } = useEvents()

const isCashier = computed(() => route.path === '/')

const displayedEvents = computed(() => {
  if (isCashier.value) {
    return events.value.filter(isEventActive)
  }
  return events.value
})

// Auto-fallback: if cashier view has a COMPLETED/inactive event selected, fallback to first ACTIVE event
watch(
  [() => route.path, events, selectedEventId],
  () => {
    if (isCashier.value && events.value.length > 0) {
      const current = events.value.find((e) => e.id === selectedEventId.value)
      if (!current || !isEventActive(current)) {
        const firstActive = events.value.find(isEventActive)
        if (firstActive) {
          selectEventId(firstActive.id)
        } else {
          selectEventId('')
        }
      }
    }
  },
  { immediate: true }
)

async function handleLogout() {
  await signOut()
  router.push('/login')
}

function handleEventSelect(event) {
  const newId = event.target.value
  selectEventId(newId)
}

function isNavActive(menuKey) {
  if (menuKey === 'cashier') {
    return route.path === '/'
  }
  if (route.path === '/admin') {
    const currentTab = (route.query.tab || 'overview').toLowerCase()
    return currentTab === menuKey
  }
  return false
}
</script>

<template>
  <div>
    <!-- Top Navbar Desktop (64px) -->
    <header
      class="hidden md:flex h-16 sticky top-0 z-40 bg-light-surface-container-lowest border-b border-light-outline-variant px-6 items-center justify-between gap-4 select-none"
    >
      <!-- Left: Brand Identity -->
      <router-link to="/" class="flex items-center gap-2.5 shrink-0 group">
        <div class="w-9 h-9 rounded-md bg-light-primary text-light-on-primary flex items-center justify-center shrink-0 shadow-sm transition-transform group-hover:scale-105">
          <span class="material-symbols-outlined text-[20px]" style="font-variation-settings: 'FILL' 1;" aria-hidden="true">point_of_sale</span>
        </div>
        <div class="flex flex-col">
          <span class="font-headline text-headline-md font-bold text-light-on-surface leading-none">PopUpPOS</span>
          <span class="font-label text-label-sm text-light-on-surface-variant leading-tight mt-0.5">Multi-Tenant POS</span>
        </div>
      </router-link>

      <!-- Center: 4 Primary Desktop Navigation Menus -->
      <nav class="flex items-center gap-1.5" aria-label="Navigasi Utama">
        <!-- 1. Terminal Kasir -->
        <router-link
          to="/"
          :class="isNavActive('cashier')
            ? 'bg-light-primary text-light-on-primary shadow-sm font-semibold'
            : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
          class="inline-flex items-center gap-2 px-3.5 py-2 rounded-md font-label text-label-md transition-colors duration-state-change"
        >
          <span
            class="material-symbols-outlined text-[18px]"
            :style="isNavActive('cashier') ? 'font-variation-settings: \'FILL\' 1;' : ''"
            aria-hidden="true"
          >storefront</span>
          <span>Terminal Kasir</span>
        </router-link>

        <!-- 2. Tutup Buku -->
        <router-link
          to="/admin?tab=overview"
          :class="isNavActive('overview')
            ? 'bg-light-primary text-light-on-primary shadow-sm font-semibold'
            : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
          class="inline-flex items-center gap-2 px-3.5 py-2 rounded-md font-label text-label-md transition-colors duration-state-change"
        >
          <span
            class="material-symbols-outlined text-[18px]"
            :style="isNavActive('overview') ? 'font-variation-settings: \'FILL\' 1;' : ''"
            aria-hidden="true"
          >receipt_long</span>
          <span>Tutup Buku</span>
        </router-link>

        <!-- 3. Kelola Event -->
        <router-link
          to="/admin?tab=lineup"
          :class="isNavActive('lineup')
            ? 'bg-light-primary text-light-on-primary shadow-sm font-semibold'
            : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
          class="inline-flex items-center gap-2 px-3.5 py-2 rounded-md font-label text-label-md transition-colors duration-state-change"
        >
          <span
            class="material-symbols-outlined text-[18px]"
            :style="isNavActive('lineup') ? 'font-variation-settings: \'FILL\' 1;' : ''"
            aria-hidden="true"
          >calendar_month</span>
          <span>Kelola Event</span>
        </router-link>

        <!-- 4. Database Brand -->
        <router-link
          to="/admin?tab=master"
          :class="isNavActive('master')
            ? 'bg-light-primary text-light-on-primary shadow-sm font-semibold'
            : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
          class="inline-flex items-center gap-2 px-3.5 py-2 rounded-md font-label text-label-md transition-colors duration-state-change"
        >
          <span
            class="material-symbols-outlined text-[18px]"
            :style="isNavActive('master') ? 'font-variation-settings: \'FILL\' 1;' : ''"
            aria-hidden="true"
          >inventory_2</span>
          <span>Database Brand</span>
        </router-link>
      </nav>

      <!-- Right: Active Event Selector & User Staff Menu -->
      <div class="flex items-center gap-3 shrink-0">
        <!-- Event Selector Dropdown / Pill -->
        <div class="relative flex items-center">
          <div class="flex items-center gap-2 px-3 py-1.5 rounded-md bg-light-secondary-container text-light-on-secondary-container border border-light-outline-variant/50 max-w-[260px]">
            <span class="material-symbols-outlined text-[16px] text-light-primary shrink-0" style="font-variation-settings: 'FILL' 1;" aria-hidden="true">festival</span>
            <select
              :value="selectedEventId"
              @change="handleEventSelect"
              aria-label="Pilih Event Aktif"
              class="bg-transparent text-light-on-secondary-container font-label text-label-sm font-semibold focus:outline-none cursor-pointer truncate max-w-[190px] pr-1"
            >
              <option v-if="displayedEvents.length === 0" value="">
                {{ isCashier ? 'Tidak Ada Event Aktif' : 'Belum Ada Event' }}
              </option>
              <option v-for="ev in displayedEvents" :key="ev.id" :value="ev.id" class="text-light-on-surface bg-light-surface">
                {{ ev.name }}{{ !isCashier && isEventActive(ev) ? ' (Aktif)' : (!isCashier && (ev.status || '').toUpperCase() === 'COMPLETED' ? ' (Selesai)' : '') }}
              </option>
            </select>
          </div>
        </div>

        <!-- Logout Action -->
        <button
          @click="handleLogout"
          type="button"
          title="Keluar dari akun kasir/admin"
          aria-label="Keluar"
          class="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-light-outline-variant text-light-tertiary hover:bg-light-tertiary-container hover:text-light-on-tertiary-container transition-colors font-label text-label-sm"
        >
          <span class="material-symbols-outlined text-[16px]" aria-hidden="true">logout</span>
          <span class="hidden lg:inline">Keluar</span>
        </button>
      </div>
    </header>

    <!-- Bottom Navigation Mobile (72px) -->
    <nav
      aria-label="Navigasi bawah"
      class="md:hidden fixed bottom-0 left-0 right-0 z-40 bg-light-surface-container-lowest border-t border-light-outline-variant h-[72px] px-2 grid grid-cols-4 items-center select-none shadow-lg"
      style="padding-bottom: env(safe-area-inset-bottom, 0px);"
    >
      <!-- 1. Kasir -->
      <router-link
        to="/"
        :aria-current="isNavActive('cashier') ? 'page' : undefined"
        :class="isNavActive('cashier') ? 'text-light-primary' : 'text-light-on-surface-variant hover:text-light-on-surface'"
        class="flex flex-col items-center justify-center gap-1 py-1 rounded-sm transition-colors touch-manipulation"
      >
        <span
          class="material-symbols-outlined text-[22px]"
          :style="isNavActive('cashier') ? 'font-variation-settings: \'FILL\' 1;' : ''"
          aria-hidden="true"
        >storefront</span>
        <span class="font-label text-label-sm leading-none" :class="{ 'font-bold': isNavActive('cashier') }">Kasir</span>
      </router-link>

      <!-- 2. Tutup Buku / Rekap -->
      <router-link
        to="/admin?tab=overview"
        :aria-current="isNavActive('overview') ? 'page' : undefined"
        :class="isNavActive('overview') ? 'text-light-primary' : 'text-light-on-surface-variant hover:text-light-on-surface'"
        class="flex flex-col items-center justify-center gap-1 py-1 rounded-sm transition-colors touch-manipulation"
      >
        <span
          class="material-symbols-outlined text-[22px]"
          :style="isNavActive('overview') ? 'font-variation-settings: \'FILL\' 1;' : ''"
          aria-hidden="true"
        >receipt_long</span>
        <span class="font-label text-label-sm leading-none" :class="{ 'font-bold': isNavActive('overview') }">Tutup Buku</span>
      </router-link>

      <!-- 3. Event -->
      <router-link
        to="/admin?tab=lineup"
        :aria-current="isNavActive('lineup') ? 'page' : undefined"
        :class="isNavActive('lineup') ? 'text-light-primary' : 'text-light-on-surface-variant hover:text-light-on-surface'"
        class="flex flex-col items-center justify-center gap-1 py-1 rounded-sm transition-colors touch-manipulation"
      >
        <span
          class="material-symbols-outlined text-[22px]"
          :style="isNavActive('lineup') ? 'font-variation-settings: \'FILL\' 1;' : ''"
          aria-hidden="true"
        >calendar_month</span>
        <span class="font-label text-label-sm leading-none" :class="{ 'font-bold': isNavActive('lineup') }">Event</span>
      </router-link>

      <!-- 4. Brand -->
      <router-link
        to="/admin?tab=master"
        :aria-current="isNavActive('master') ? 'page' : undefined"
        :class="isNavActive('master') ? 'text-light-primary' : 'text-light-on-surface-variant hover:text-light-on-surface'"
        class="flex flex-col items-center justify-center gap-1 py-1 rounded-sm transition-colors touch-manipulation"
      >
        <span
          class="material-symbols-outlined text-[22px]"
          :style="isNavActive('master') ? 'font-variation-settings: \'FILL\' 1;' : ''"
          aria-hidden="true"
        >inventory_2</span>
        <span class="font-label text-label-sm leading-none" :class="{ 'font-bold': isNavActive('master') }">Brand</span>
      </router-link>
    </nav>
  </div>
</template>
