import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  { path: '/login', name: 'Login', component: () => import('../views/Login.vue') },
  { path: '/register', name: 'Register', component: () => import('../views/Register.vue') },
  { path: '/data', name: 'Data', component: () => import('../views/DataCenter.vue'), meta: { auth: true } },
  { path: '/chart', name: 'Chart', component: () => import('../views/ChartCenter.vue'), meta: { auth: true } },
  { path: '/formula', name: 'Formula', component: () => import('../views/FormulaCenter.vue'), meta: { auth: true } },
  { path: '/history', name: 'History', component: () => import('../views/History.vue'), meta: { auth: true } },
  { path: '/admin', name: 'Admin', component: () => import('../views/AdminDashboard.vue'), meta: { auth: true, admin: true } },
  { path: '/', redirect: '/login' }
]

const router = createRouter({ history: createWebHistory(), routes })

router.beforeEach((to, from, next) => {
  const token = localStorage.getItem('token')
  if (to.meta.auth && !token) return next('/login')
  if (to.meta.admin) {
    if (!token) return next('/login')
    try {
      const payload = JSON.parse(atob(token.split('.')[1]))
      if (!payload.roles || !payload.roles.includes('ROLE_ADMIN')) return next('/data')
    } catch (e) {
      return next('/login')
    }
  }
  next()
})

export default router
