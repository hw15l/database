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

function isTokenValid() {
  const token = localStorage.getItem('token')
  if (!token) return false
  try {
    const payload = JSON.parse(atob(token.split('.')[1]))
    if (payload.exp && payload.exp * 1000 < Date.now()) {
      localStorage.clear()
      return false
    }
    return true
  } catch (e) {
    localStorage.clear()
    return false
  }
}

function hasRole(role) {
  const token = localStorage.getItem('token')
  if (!token) return false
  try {
    const payload = JSON.parse(atob(token.split('.')[1]))
    return payload.roles && payload.roles.includes(role)
  } catch (e) { return false }
}

router.beforeEach((to, from, next) => {
  const valid = isTokenValid()

  if ((to.path === '/login' || to.path === '/register') && valid) {
    return next('/data')
  }

  if (to.meta.auth && !valid) return next('/login')

  if (to.meta.admin && !hasRole('ROLE_ADMIN')) return next('/data')

  next()
})

export default router
