<template>
  <el-container style="min-height:100vh">
    <el-header v-if="loggedIn" style="background:#409EFF;display:flex;align-items:center;justify-content:space-between;padding:0 20px">
      <span style="color:#fff;font-size:20px;font-weight:bold">📄 论文可视化助手</span>
      <div>
        <el-button type="info" size="small" @click="$router.push('/data')">数据中心</el-button>
        <el-button type="info" size="small" @click="$router.push('/chart')">图表生成</el-button>
        <el-button type="info" size="small" @click="$router.push('/formula')">公式渲染</el-button>
        <el-button type="info" size="small" @click="$router.push('/history')">历史记录</el-button>
        <el-button v-if="adminFlag" type="warning" size="small" @click="$router.push('/admin')">管理后台</el-button>
        <el-dropdown style="margin-left:10px">
          <span style="color:#fff;cursor:pointer">{{ currentUsername }} <el-icon><ArrowDown /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="logout">退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </el-header>
    <el-main>
      <div v-if="verifying" style="text-align:center;padding:120px 0;color:#909399">
        <el-icon class="is-loading" :size="32"><Loading /></el-icon>
        <p style="margin-top:12px">验证登录状态...</p>
      </div>
      <router-view v-else />
    </el-main>
  </el-container>
</template>

<script>
import { user } from './api'
export default {
  data() {
    return { loggedIn: false, currentUsername: '', adminFlag: false, verifying: true }
  },
  async created() {
    await this.verifyAuth()
  },
  watch: {
    '$route'() { this.syncLocal() }
  },
  methods: {
    async verifyAuth() {
      const token = localStorage.getItem('token')
      if (!token) {
        this.clearAuth()
        this.verifying = false
        return
      }
      try {
        const payload = JSON.parse(atob(token.split('.')[1]))
        if (payload.exp && payload.exp * 1000 < Date.now()) {
          this.clearAuth()
          this.verifying = false
          return
        }
      } catch (e) {
        this.clearAuth()
        this.verifying = false
        return
      }
      try {
        const me = await user.me()
        if (me && me.username) {
          this.loggedIn = true
          this.currentUsername = me.nickname || me.username
          localStorage.setItem('username', me.username)
          const payload = JSON.parse(atob(token.split('.')[1]))
          this.adminFlag = !!(payload.roles && payload.roles.includes('ROLE_ADMIN'))
        } else {
          this.clearAuth()
          if (this.$route.path !== '/login' && this.$route.path !== '/register') {
            this.$router.replace('/login')
          }
        }
      } catch (e) {
        this.clearAuth()
        if (this.$route.path !== '/login' && this.$route.path !== '/register') {
          this.$router.replace('/login')
        }
      }
      this.verifying = false
    },
    syncLocal() {
      const token = localStorage.getItem('token')
      if (!token) {
        this.loggedIn = false
        this.currentUsername = ''
        this.adminFlag = false
        return
      }
      try {
        const payload = JSON.parse(atob(token.split('.')[1]))
        if (payload.exp && payload.exp * 1000 < Date.now()) {
          this.clearAuth()
          return
        }
        this.loggedIn = true
        this.currentUsername = localStorage.getItem('username') || payload.sub || '用户'
        this.adminFlag = !!(payload.roles && payload.roles.includes('ROLE_ADMIN'))
      } catch (e) {
        this.clearAuth()
      }
    },
    clearAuth() {
      localStorage.clear()
      this.loggedIn = false
      this.currentUsername = ''
      this.adminFlag = false
    },
    logout() {
      this.clearAuth()
      this.$router.push('/login')
    }
  }
}
</script>
