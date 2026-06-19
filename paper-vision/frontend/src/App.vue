<template>
  <el-container style="min-height:100vh">
    <el-header v-if="isLogin" style="background:#409EFF;display:flex;align-items:center;justify-content:space-between;padding:0 20px">
      <span style="color:#fff;font-size:20px;font-weight:bold">📄 论文可视化助手</span>
      <div>
        <el-button type="info" size="small" @click="$router.push('/data')">数据中心</el-button>
        <el-button type="info" size="small" @click="$router.push('/chart')">图表生成</el-button>
        <el-button type="info" size="small" @click="$router.push('/formula')">公式渲染</el-button>
        <el-button type="info" size="small" @click="$router.push('/history')">历史记录</el-button>
        <el-button v-if="isAdmin" type="warning" size="small" @click="$router.push('/admin')">管理后台</el-button>
        <el-dropdown style="margin-left:10px">
          <span style="color:#fff;cursor:pointer">{{ username }} <el-icon><ArrowDown /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item @click="logout">退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>
    </el-header>
    <el-main><router-view /></el-main>
  </el-container>
</template>

<script>
export default {
  computed: {
    isLogin() { return !!localStorage.getItem('token') },
    username() { return localStorage.getItem('username') || '用户' },
    isAdmin() {
      try {
        const token = localStorage.getItem('token')
        if (!token) return false
        const payload = JSON.parse(atob(token.split('.')[1]))
        return payload.roles && payload.roles.includes('ROLE_ADMIN')
      } catch (e) { return false }
    }
  },
  methods: {
    logout() { localStorage.clear(); this.$router.push('/login') }
  }
}
</script>
