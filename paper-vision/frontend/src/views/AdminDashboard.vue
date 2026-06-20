<template>
  <div>
    <h3>🛡️ 管理后台</h3>
    <el-row :gutter="20">
      <el-col :span="6">
        <el-card>
          <template #header>
            <span>系统概览</span>
            <el-button size="small" type="primary" style="float:right" @click="refresh" :loading="refreshing">刷新统计</el-button>
          </template>
          <el-statistic title="总用户" :value="stats.totalUsers||0" />
          <el-statistic title="总任务" :value="stats.totalTasks||0" />
          <el-statistic title="成功任务" :value="stats.successTasks||0" />
          <el-statistic title="成功率" :value="(stats.successRate||0)+'%'" />
          <el-statistic title="今日任务" :value="stats.todayTasks||0" />
          <el-statistic title="人均任务" :value="stats.avgTasksPerUser||0" />
        </el-card>
      </el-col>
      <el-col :span="18">
        <el-tabs>
          <el-tab-pane label="用户管理">
            <el-table :data="users" stripe>
              <el-table-column prop="username" label="用户名" />
              <el-table-column prop="email" label="邮箱" />
              <el-table-column prop="nickname" label="昵称" />
              <el-table-column label="状态" width="100"><template #default="s"><el-tag :type="s.row.status===1?'success':'danger'">{{ s.row.status===1?'正常':'禁用' }}</el-tag></template></el-table-column>
              <el-table-column label="操作" width="120">
                <template #default="s"><el-button size="small" :type="s.row.status===1?'danger':'success'" @click="toggle(s.row)">{{ s.row.status===1?'禁用':'启用' }}</el-button></template>
              </el-table-column>
            </el-table>
          </el-tab-pane>
          <el-tab-pane label="统计排行">
            <el-table :data="ranking" stripe size="small">
              <el-table-column prop="taskCountRank" label="排名" width="70" />
              <el-table-column prop="username" label="用户名" />
              <el-table-column prop="nickname" label="昵称" />
              <el-table-column prop="totalTasks" label="总任务" width="90" />
              <el-table-column prop="successCount" label="成功" width="80" />
              <el-table-column prop="successRatePct" label="成功率%" width="90" />
              <el-table-column prop="userTier" label="等级" width="90">
                <template #default="s"><el-tag size="small">{{ s.row.userTier }}</el-tag></template>
              </el-table-column>
            </el-table>
          </el-tab-pane>
        </el-tabs>
      </el-col>
    </el-row>
  </div>
</template>
<script>
import { adminApi } from '../api'
export default {
  data() { return { stats: {}, users: [], ranking: [], refreshing: false } },
  async mounted() { await this.loadData() },
  methods: {
    async loadData() {
      const [stats, users, ranking] = await Promise.all([adminApi.stats(), adminApi.users(), adminApi.ranking(10)])
      this.stats = stats || {}
      this.users = users || []
      this.ranking = (ranking && ranking.top) || []
    },
    async toggle(row) {
      await adminApi.toggleUser(row.id, row.status === 1 ? 0 : 1)
      this.$message.success('状态已更新')
      await this.loadData()
    },
    async refresh() {
      this.refreshing = true
      try {
        await adminApi.refreshAll()
        await this.loadData()
        this.$message.success('统计数据已刷新')
      } catch (e) { /* 拦截器已统一提示 */ }
      this.refreshing = false
    }
  }
}
</script>
