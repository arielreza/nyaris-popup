<script setup>
import { onMounted } from 'vue'
import { useAuth } from '@/lib/useAuth.js'

const { initAuth } = useAuth()

onMounted(() => {
  initAuth()
})
</script>

<template>
  <div class="min-h-screen bg-slate-950">
    <router-view />
  </div>
</template>

<style>
/* Global styles are handled via src/style.css */
</style>
