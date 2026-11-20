import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase.js'

const user = ref(null)
const session = ref(null)
const loading = ref(true)
const error = ref(null)
let isInitialized = false

export function useAuth() {
  async function initAuth() {
    if (isInitialized) return
    isInitialized = true
    try {
      loading.value = true
      const { data, error: sessionError } = await supabase.auth.getSession()
      if (sessionError) throw sessionError
      session.value = data?.session || null
      user.value = data?.session?.user || null
    } catch (err) {
      error.value = err.message
      session.value = null
      user.value = null
    } finally {
      loading.value = false
    }

    supabase.auth.onAuthStateChange((_event, newSession) => {
      session.value = newSession
      user.value = newSession?.user || null
      loading.value = false
    })
  }

  async function signIn(email, password) {
    loading.value = true
    error.value = null
    try {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      })
      if (signInError) throw signInError
      session.value = data.session
      user.value = data.user
      return { success: true, user: data.user }
    } catch (err) {
      error.value = err.message
      return { success: false, error: err.message }
    } finally {
      loading.value = false
    }
  }

  async function signOut() {
    loading.value = true
    try {
      await supabase.auth.signOut()
    } catch (err) {
      console.warn('Sign out warning:', err.message)
    } finally {
      session.value = null
      user.value = null
      loading.value = false
    }
  }

  const isAuthenticated = computed(() => !!session.value)

  return {
    user,
    session,
    loading,
    error,
    isAuthenticated,
    initAuth,
    signIn,
    signOut,
  }
}
