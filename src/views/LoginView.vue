<template>
  <div class="min-h-screen bg-light-surface text-light-on-surface font-body flex flex-col items-center justify-center p-4 selection:bg-light-primary/20">
    <div class="w-full max-w-sm">
      <!-- Logo & Branding -->
      <div class="text-center mb-8">
        <div class="w-16 h-16 rounded-2xl bg-light-primary text-light-on-primary flex items-center justify-center mx-auto mb-4 shadow-sm">
          <ShieldCheck class="w-8 h-8" />
        </div>
        <h1 class="text-2xl font-headline font-bold tracking-tight text-light-on-surface">
          PopUpPOS <span class="text-light-primary">Staff</span>
        </h1>
        <p class="text-xs text-light-on-surface-variant mt-1.5 leading-relaxed">
          Masuk dengan akun staf untuk mengakses terminal kasir dan dashboard admin
        </p>
      </div>

      <!-- Login Card -->
      <div class="bg-light-surface-container-lowest border border-light-outline-variant rounded-xl p-6 sm:p-8 shadow-xs space-y-5">
        <!-- Error Banner -->
        <div
          v-if="errorMessage"
          class="flex items-start gap-2.5 bg-light-error-container/20 border border-light-error/30 rounded-lg p-3 text-xs text-light-error"
        >
          <AlertCircle class="w-4 h-4 text-light-error shrink-0 mt-0.5" />
          <span class="leading-relaxed">{{ errorMessage }}</span>
        </div>

        <form @submit.prevent="handleLogin" class="space-y-4">
          <!-- Email Input -->
          <div class="space-y-1.5">
            <label class="text-xs font-label font-semibold text-light-on-surface-variant uppercase tracking-wider block">
              Email Staf
            </label>
            <div class="relative">
              <Mail class="w-4 h-4 text-light-on-surface-variant absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                v-model="email"
                type="email"
                required
                autocomplete="email"
                placeholder="staff@popuppos.com"
                class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface placeholder:text-light-on-surface-variant rounded-md pl-10 pr-4 py-2.5 text-sm font-body focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary transition-all"
              />
            </div>
          </div>

          <!-- Password Input -->
          <div class="space-y-1.5">
            <div class="flex items-center justify-between">
              <label class="text-xs font-label font-semibold text-light-on-surface-variant uppercase tracking-wider block">
                Password
              </label>
            </div>
            <div class="relative">
              <Lock class="w-4 h-4 text-light-on-surface-variant absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                required
                autocomplete="current-password"
                placeholder="••••••••"
                class="w-full bg-light-surface-container-low border border-light-outline-variant text-light-on-surface placeholder:text-light-on-surface-variant rounded-md pl-10 pr-10 py-2.5 text-sm font-body focus:outline-none focus:ring-2 focus:ring-light-primary focus:border-light-primary transition-all"
              />
              <button
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-light-on-surface-variant hover:text-light-on-surface transition-colors p-1 cursor-pointer"
                tabindex="-1"
              >
                <EyeOff v-if="showPassword" class="w-4 h-4" />
                <Eye v-else class="w-4 h-4" />
              </button>
            </div>
          </div>

          <!-- Submit Button -->
          <button
            type="submit"
            :disabled="isSubmitting || !email.trim() || !password"
            class="w-full py-2.5 rounded-md font-label font-bold text-sm bg-light-primary hover:bg-light-primary-container text-light-on-primary shadow-xs disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-150 flex items-center justify-center gap-2 active:scale-[0.98] cursor-pointer mt-2"
          >
            <Loader2 v-if="isSubmitting" class="w-4 h-4 animate-spin" />
            <LogIn v-else class="w-4 h-4" />
            {{ isSubmitting ? 'Memverifikasi…' : 'Masuk ke POS' }}
          </button>
        </form>

        <!-- Help Info Box -->
        <div class="pt-3 border-t border-light-outline-variant text-[11px] text-light-on-surface-variant space-y-1">
          <p class="flex items-center gap-1.5 text-light-on-surface font-semibold font-label">
            <KeyRound class="w-3.5 h-3.5 text-light-primary" />
            Akses Staf Terproteksi
          </p>
          <p class="font-body text-light-on-surface-variant">
            Akun kasir dan admin dikelola terpusat di Supabase Auth. Portal Tenant tetap dapat diakses vendor tanpa login melalui link token.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import {
  ShieldCheck,
  Mail,
  Lock,
  Eye,
  EyeOff,
  LogIn,
  AlertCircle,
  Loader2,
  KeyRound,
} from 'lucide-vue-next'
import { useAuth } from '@/lib/useAuth.js'

const router = useRouter()
const route = useRoute()
const { signIn } = useAuth()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const isSubmitting = ref(false)
const errorMessage = ref('')

async function handleLogin() {
  errorMessage.value = ''
  if (!email.value.trim() || !password.value) return

  isSubmitting.value = true
  const res = await signIn(email.value, password.value)
  isSubmitting.value = false

  if (!res.success) {
    if (res.error?.includes('Invalid login credentials')) {
      errorMessage.value = 'Email atau password salah. Silakan coba lagi.'
    } else {
      errorMessage.value = res.error || 'Gagal masuk. Periksa koneksi internet Anda.'
    }
    return
  }

  // Redirect to original target or cashier
  const redirectPath = route.query.redirect || '/'
  router.replace(redirectPath)
}
</script>
