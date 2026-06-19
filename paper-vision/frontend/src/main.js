import { createApp } from 'vue'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import * as Icons from '@element-plus/icons-vue'
import App from './App.vue'
import router from './router'

const app = createApp(App)
app.use(ElementPlus, { locale: { el: { empty: { description: '暂无数据' } } } })
app.use(router)
for (const [key, component] of Object.entries(Icons)) { app.component(key, component) }
app.mount('#app')
