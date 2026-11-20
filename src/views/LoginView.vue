<template>
  <div class="min-h-screen bg-slate-950 text-slate-100 flex flex-col items-center justify-center p-4 selection:bg-emerald-500/30">
    <div class="w-full max-w-sm">
      <!-- Logo & Branding -->
      <div class="text-center mb-8">
        <div class="w-16 h-16 rounded-3xl bg-emerald-500/10 border border-emerald-500/25 flex items-center justify-center mx-auto mb-4 text-emerald-400 shadow-xl shadow-emerald-500/10">
          <ShieldCheck class="w-8 h-8" />
        </div>
        <h1 class="text-2xl font-black tracking-tight text-white">
          PopUpPOS <span class="text-emerald-400">Staff</span>
        </h1>
        <p class="text-xs text-slate-400 mt-1.5 leading-relaxed">
          Masuk dengan akun staf untuk mengakses terminal kasir dan dashboard admin
        </p>
      </div>

      <!-- Login Card -->
      <div class="bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-2xl space-y-5">
        <!-- Error Banner -->
        <div
          v-if="errorMessage"
          class="flex items-start gap-2.5 bg-rose-500/10 border border-rose-500/30 rounded-xl p-3 text-xs text-rose-300"
        >
          <AlertCircle class="w-4 h-4 text-rose-400 shrink-0 mt-0.5" />
          <span class="leading-relaxed">{{ errorMessage }}</span>
        </div>

        <form @submit.prevent="handleLogin" class="space-y-4">
          <!-- Email Input -->
          <div class="space-y-1.5">
            <label class="text-xs font-semibold text-slate-300 uppercase tracking-wider block">
              Email Staf
            </label>
            <div class="relative">
              <Mail class="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                v-model="email"
                type="email"
                required
                autocomplete="email"
                placeholder="staff@popuppos.com"
                class="w-full bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 rounded-xl pl-10 pr-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-transparent transition-all"
              />
            </div>
          </div>

          <!-- Password Input -->
          <div class="space-y-1.5">
            <div class="flex items-center justify-between">
              <label class="text-xs font-semibold text-slate-300 uppercase tracking-wider block">
                Password
              </label>
            </div>
            <div class="relative">
              <Lock class="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                required
                autocomplete="current-password"
                placeholder="••••••••"
                class="w-full bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 rounded-xl pl-10 pr-10 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-transparent transition-all"
              />
              <button
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200 transition-colors p-1"
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
            class="w-full py-3 rounded-xl font-bold text-sm bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-lg shadow-emerald-500/20 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-150 flex items-center justify-center gap-2 active:scale-[0.98] cursor-pointer mt-2"
          >
            <Loader2 v-if="isSubmitting" class="w-4 h-4 animate-spin" />
            <LogIn v-else class="w-4 h-4" />
            {{ isSubmitting ? 'Memverifikasi…' : 'Masuk ke POS' }}
          </button>
        </form>

        <!-- Help Info Box -->
        <div class="pt-3 border-t border-slate-800/80 text-[11px] text-slate-500 space-y-1">
          <p class="flex items-center gap-1.5 text-slate-400 font-medium">
            <KeyRound class="w-3.5 h-3.5 text-emerald-400" />
            Akses Staf Terproteksi
          </p>
          <p>
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
