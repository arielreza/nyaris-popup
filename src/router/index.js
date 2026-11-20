import { createRouter, createWebHistory } from 'vue-router'
import CashierView from '@/views/CashierView.vue'
import AdminDashboardView from '@/views/AdminDashboardView.vue'
import TenantPortalView from '@/views/TenantPortalView.vue'
import LoginView from '@/views/LoginView.vue'
import { supabase } from '@/lib/supabase.js'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: LoginView,
  },
  {
    path: '/',
    name: 'Cashier',
    component: CashierView,
    meta: { requiresAuth: true },
  },
  {
    path: '/admin',
    name: 'AdminDashboard',
    component: AdminDashboardView,
    meta: { requiresAuth: true },
  },
  {
    path: '/tenant/:token',
    name: 'TenantPortal',
    component: TenantPortalView,
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/',
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to, from, next) => {
  // Public routes: Tenant Portal & Login
  if (to.name === 'TenantPortal' || to.name === 'Login' || to.path.startsWith('/tenant/')) {
    if (to.name === 'Login') {
      const { data } = await supabase.auth.getSession()
      if (data?.session) {
        return next('/')
      }
    }
    return next()
  }

  // Protected routes: check Supabase session
  const { data } = await supabase.auth.getSession()
  if (!data?.session) {
    return next({
      path: '/login',
      query: { redirect: to.fullPath !== '/' ? to.fullPath : undefined },
    })
  }

  next()
})

export default router
