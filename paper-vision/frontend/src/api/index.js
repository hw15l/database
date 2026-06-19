import axios from 'axios'

const api = axios.create({ baseURL: '/api', timeout: 30000 })

api.interceptors.request.use(config => {
  const token = localStorage.getItem('token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(res => res, err => {
  if (err.response?.status === 401 || err.response?.status === 403) {
    localStorage.clear(); window.location.href = '/login'
  }
  return Promise.reject(err)
})

export const auth = { login: d => api.post('/auth/login', d), register: d => api.post('/auth/register', d) }
export const user = { me: () => api.get('/user/me'), update: d => api.put('/user/profile', d), changePwd: d => api.put('/user/password', d) }
export const dataApi = {
  upload: (fileName, fileData) => api.post('/data/upload', { fileName, fileData }),
  files: () => api.get('/data/files'), preview: id => api.get(`/data/preview/${id}`), del: id => api.delete(`/data/${id}`)
}
export const chartApi = { list: () => api.get('/chart/list'), byCat: id => api.get(`/chart/category/${id}`), generate: d => api.post('/chart/generate', d), generateBatch: d => api.post('/chart/generate-batch', d) }
export const formulaApi = { list: () => api.get('/formula/list'), byCat: id => api.get(`/formula/category/${id}`), generate: d => api.post('/formula/generate', d) }
export const taskApi = { list: () => api.get('/task/list'), get: id => api.get(`/task/${id}`), image: id => api.get(`/task/${id}/image`, { responseType: 'blob' }), history: () => api.get('/task/history'), delHistory: id => api.delete(`/task/history/${id}`) }
export const adminApi = { stats: () => api.get('/admin/stats'), ranking: n => api.get(`/admin/ranking?topN=${n}`), users: () => api.get('/admin/users'), toggleUser: (id, s) => api.put(`/admin/users/${id}/status?status=${s}`) }
