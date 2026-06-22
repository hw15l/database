import axios from 'axios'
import { ElMessage } from 'element-plus'

const api = axios.create({ baseURL: '/api', timeout: 30000 })

api.interceptors.request.use(config => {
  const token = localStorage.getItem('token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  res => {
    if (res.config.responseType === 'blob') return res.data
    const body = res.data
    if (body && typeof body === 'object' && typeof body.code === 'number') {
      if (body.code === 200) return body.data
      ElMessage.error(body.message || '请求失败')
      return Promise.reject(new Error(body.message || '请求失败'))
    }
    return body
  },
  err => {
    if (err.response?.status === 401 || err.response?.status === 403) {
      localStorage.clear(); window.location.href = '/login'
      return Promise.reject(err)
    }
    const msg = err.response?.data?.message || err.message || '网络错误'
    ElMessage.error(msg)
    return Promise.reject(new Error(msg))
  }
)

export const auth = { login: d => api.post('/auth/login', d), register: d => api.post('/auth/register', d) }
export const user = {
  me: () => api.get('/user/me'),
  update: d => api.put('/user/profile', d),
  changePwd: d => api.put('/user/password', d),
  profile360: () => api.get('/user/profile360'),
  quota: () => api.get('/user/quota'),
  recommend: (n = 5) => api.get(`/user/recommend?limit=${n}`),
  preference: () => api.get('/user/preference')
}
export const dataApi = {
  upload: (fileName, fileData) => api.post('/data/upload', { fileName, fileData }),
  files: () => api.get('/data/files'),
  preview: id => api.get(`/data/preview/${id}`),
  del: id => api.delete(`/data/${id}`),
  audit: id => api.post(`/data/${id}/audit`)
}
export const chartApi = {
  list: () => api.get('/chart/list'),
  byCat: id => api.get(`/chart/category/${id}`),
  generate: d => api.post('/chart/generate', d),
  generateBatch: d => api.post('/chart/generate-batch', d)
}
export const formulaApi = {
  list: () => api.get('/formula/list'),
  byCat: id => api.get(`/formula/category/${id}`),
  generate: d => api.post('/formula/generate', d)
}
export const taskApi = {
  list: () => api.get('/task/list'),
  get: id => api.get(`/task/${id}`),
  detail: id => api.get(`/task/${id}/detail`),
  image: id => api.get(`/task/${id}/image`, { responseType: 'blob' }),
  history: () => api.get('/task/history'),
  delHistory: id => api.delete(`/task/history/${id}`),
  rateHistory: (id, rating) => api.put(`/task/history/${id}/rating?rating=${rating}`),
  toggleFavorite: id => api.put(`/task/history/${id}/favorite`)
}
export const adminApi = {
  stats: () => api.get('/admin/stats'),
  ranking: n => api.get(`/admin/ranking?topN=${n}`),
  users: () => api.get('/admin/users'),
  toggleUser: (id, s) => api.put(`/admin/users/${id}/status?status=${s}`),
  refreshAll: () => api.post('/admin/refresh-all'),
  hotItems: (n = 20) => api.get(`/admin/hot-items?limit=${n}`),
  trend: (w = 12) => api.get(`/admin/trend?weeks=${w}`),
  categoryTree: (t = 'chart') => api.get(`/admin/category-tree?type=${t}`),
  activity: (uid, n = 50) => api.get(`/admin/activity?userId=${uid}&limit=${n}`)
}
