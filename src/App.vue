<script setup>
import { onMounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAuth } from '@/lib/useAuth.js'
import { useEvents } from '@/lib/useEvents.js'
import GlobalNavigation from '@/components/GlobalNavigation.vue'

const { initAuth, isAuthenticated } = useAuth()
const { fetchEvents } = useEvents()
const route = useRoute()

const showNav = computed(() => {
  // Show navigation only for authenticated POS & Admin views, hide on Login & Tenant Portal
  if (!isAuthenticated.value) return false
  if (route.name === 'Login' || route.name === 'TenantPortal') return false
  if (route.path.startsWith('/tenant/')) return false
  return true
})

onMounted(async () => {
  await initAuth()
  if (isAuthenticated.value) {
    fetchEvents().catch((err) => {
      console.warn('Failed to prefetch events in App.vue:', err.message)
    })
  }
})
</script>

<template>
  <div class="min-h-screen bg-light-surface text-light-on-surface font-body antialiased flex flex-col">
    <!-- Global Navigation: Desktop Top Navbar (64px) & Mobile Bottom Nav (72px) -->
    <GlobalNavigation v-if="showNav" />

    <!-- Main Content Area with Mobile Bottom Nav Clearance -->
    <div class="flex-1 w-full" :class="{ 'pb-[76px] md:pb-0': showNav }">
      <router-view />
    </div>
  </div>
</template>

<style>
/* Global styles are handled via src/style.css */
</style>
