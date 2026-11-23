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

function handleLockAdmin() {
  sessionStorage.removeItem('popuppos_admin_unlocked')
  window.dispatchEvent(new Event('lock-admin'))
  if (route.path !== '/admin') {
    router.push('/admin')
  }
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

const userEmail = computed(() => user.value?.email || 'staff@popuppos.com')
const userName = computed(() => {
  if (!user.value?.email) return 'Relawan Kasir'
  const namePart = user.value.email.split('@')[0]
  return namePart.charAt(0).toUpperCase() + namePart.slice(1)
})
const userInitial = computed(() => {
  return userName.value.slice(0, 2).toUpperCase()
})
</script>

<template>
  <div>
    <!-- Desktop Left Sidebar (240px wide, sticky full viewport) -->
    <aside
      id="sidebar"
      class="hidden lg:flex w-[240px] shrink-0 h-screen sticky top-0 overflow-y-auto bg-light-surface-container-lowest border-r border-light-outline-variant flex-col justify-between p-gutter-lg select-none z-40"
    >
      <div class="flex flex-col gap-gutter-xl">
        <!-- Brand & Title -->
        <div class="flex items-center justify-between gap-gutter-sm">
          <router-link to="/" class="flex items-center gap-gutter-sm group">
            <div class="w-9 h-9 rounded-md bg-light-primary text-light-on-primary flex items-center justify-center shrink-0 shadow-xs transition-transform group-hover:scale-105">
              <span class="material-symbols-outlined text-[20px]" style="font-variation-settings: 'FILL' 1;" aria-hidden="true">point_of_sale</span>
            </div>
            <div class="sidebar-label min-w-0">
              <span class="font-headline text-headline-md font-bold text-light-on-surface block leading-none">PopUpPOS</span>
              <span class="font-label text-label-sm text-light-on-surface-variant block mt-0.5">Multi-Tenant POS</span>
            </div>
          </router-link>
        </div>

        <!-- Active Event Switcher Pill -->
        <div class="relative w-full">
          <div class="w-full flex items-center justify-between gap-gutter-xs px-gutter-md py-gutter-sm rounded-md bg-light-secondary-container text-light-on-secondary-container border border-light-outline-variant/40 hover:bg-light-surface-variant transition-colors">
            <div class="flex items-center gap-gutter-sm min-w-0 flex-1">
              <span class="material-symbols-outlined text-[16px] text-light-primary shrink-0" style="font-variation-settings: 'FILL' 1;" aria-hidden="true">festival</span>
              <select
                :value="selectedEventId"
                @change="handleEventSelect"
                aria-label="Pilih Event Aktif"
                class="bg-transparent text-light-on-secondary-container font-label text-label-md font-semibold focus:outline-none cursor-pointer truncate w-full"
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
        </div>

        <!-- Primary Navigation Menus -->
        <nav aria-label="Navigasi utama" class="flex flex-col gap-gutter-xs">
          <!-- 1. Terminal Kasir -->
          <router-link
            to="/"
            :class="isNavActive('cashier')
              ? 'bg-light-primary text-light-on-primary font-bold shadow-xs'
              : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
            class="flex items-center gap-gutter-sm px-gutter-sm py-gutter-md rounded-md font-label text-label-md transition-colors duration-state-change"
          >
            <span
              class="material-symbols-outlined text-[18px] shrink-0"
              :style="isNavActive('cashier') ? 'font-variation-settings: \'FILL\' 1;' : ''"
              aria-hidden="true"
            >storefront</span>
            <span class="font-label text-label-md">Terminal Kasir</span>
          </router-link>

          <!-- 2. Ringkasan & Tutup Buku -->
          <router-link
            to="/admin?tab=overview"
            :class="isNavActive('overview')
              ? 'bg-light-primary text-light-on-primary font-bold shadow-xs'
              : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
            class="flex items-center gap-gutter-sm px-gutter-sm py-gutter-md rounded-md font-label text-label-md transition-colors duration-state-change"
          >
            <span
              class="material-symbols-outlined text-[18px] shrink-0"
              :style="isNavActive('overview') ? 'font-variation-settings: \'FILL\' 1;' : ''"
              aria-hidden="true"
            >receipt_long</span>
            <span class="font-label text-label-md">Ringkasan &amp; Tutup Buku</span>
          </router-link>

          <!-- 3. Kelola Event & Booth -->
          <router-link
            to="/admin?tab=lineup"
            :class="isNavActive('lineup')
              ? 'bg-light-primary text-light-on-primary font-bold shadow-xs'
              : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
            class="flex items-center gap-gutter-sm px-gutter-sm py-gutter-md rounded-md font-label text-label-md transition-colors duration-state-change"
          >
            <span
              class="material-symbols-outlined text-[18px] shrink-0"
              :style="isNavActive('lineup') ? 'font-variation-settings: \'FILL\' 1;' : ''"
              aria-hidden="true"
            >calendar_month</span>
            <span class="font-label text-label-md">Kelola Event &amp; Booth</span>
          </router-link>

          <!-- 4. Database Brand -->
          <router-link
            to="/admin?tab=master"
            :class="isNavActive('master')
              ? 'bg-light-primary text-light-on-primary font-bold shadow-xs'
              : 'text-light-on-surface-variant hover:text-light-on-surface hover:bg-light-surface-container-low font-medium'"
            class="flex items-center gap-gutter-sm px-gutter-sm py-gutter-md rounded-md font-label text-label-md transition-colors duration-state-change"
          >
            <span
              class="material-symbols-outlined text-[18px] shrink-0"
              :style="isNavActive('master') ? 'font-variation-settings: \'FILL\' 1;' : ''"
              aria-hidden="true"
            >inventory_2</span>
            <span class="font-label text-label-md">Database Brand</span>
          </router-link>
        </nav>
      </div>

      <!-- Bottom User Profile & Actions -->
      <div class="flex flex-col gap-gutter-md pt-gutter-lg border-t border-light-outline-variant">
        <div class="flex items-center gap-gutter-md">
          <div class="w-9 h-9 rounded-full bg-light-secondary-container text-light-on-secondary-container flex items-center justify-center font-headline text-label-lg font-bold shrink-0">
            {{ userInitial }}
          </div>
          <div class="min-w-0">
            <p class="font-label text-label-lg text-light-on-surface truncate font-semibold">{{ userName }}</p>
            <p class="font-body text-body-sm text-light-on-surface-variant truncate">{{ userEmail }}</p>
          </div>
        </div>

        <div class="flex flex-col gap-gutter-xs">
          <!-- Kunci Admin (Tampil jika di halaman admin /admin) -->
          <button
            v-if="route.path === '/admin'"
            @click="handleLockAdmin"
            type="button"
            class="w-full inline-flex items-center justify-center gap-gutter-sm px-gutter-md py-gutter-sm rounded-sm bg-light-surface-container-low border border-light-outline-variant text-light-on-surface hover:bg-light-surface-container transition-colors duration-state-change cursor-pointer font-label text-label-md font-semibold"
            title="Kunci sesi Admin"
          >
            <span class="material-symbols-outlined text-[16px]" aria-hidden="true">lock</span>
            <span>Kunci Admin</span>
          </button>

          <!-- Logout -->
          <button
            @click="handleLogout"
            type="button"
            class="w-full inline-flex items-center justify-center gap-gutter-sm px-gutter-md py-gutter-sm rounded-sm bg-light-surface-container-lowest border border-light-outline-variant text-light-tertiary hover:bg-light-tertiary-container hover:text-light-on-tertiary-container transition-colors duration-state-change cursor-pointer font-label text-label-md font-semibold"
          >
            <span class="material-symbols-outlined text-[16px]" aria-hidden="true">logout</span>
            <span>Keluar</span>
          </button>
        </div>
      </div>
    </aside>

    <!-- Bottom Navigation Mobile (< 1024px) -->
    <nav
      aria-label="Navigasi bawah"
      class="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-light-surface-container-lowest border-t border-light-outline-variant h-[72px] px-2 grid grid-cols-4 items-center select-none shadow-lg"
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
