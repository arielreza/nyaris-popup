import { createRouter, createWebHistory } from 'vue-router'
import CashierView from '@/views/CashierView.vue'
import AdminDashboardView from '@/views/AdminDashboardView.vue'
import TenantPortalView from '@/views/TenantPortalView.vue'

const routes = [
  {
    path: '/',
    name: 'Cashier',
    component: CashierView,
  },
  {
    path: '/admin',
    name: 'AdminDashboard',
    component: AdminDashboardView,
  },
  {
    path: '/tenant/:token',
    name: 'TenantPortal',
    component: TenantPortalView,
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

export default router

