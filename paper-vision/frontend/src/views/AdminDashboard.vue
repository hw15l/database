<template>
  <div>
    <h3>🛡️ 管理后台</h3>
    <el-row :gutter="20">
      <el-col :span="6"><el-card><template #header>系统概览</template><el-statistic title="总用户" :value="stats.totalUsers||0" /><el-statistic title="总任务" :value="stats.totalTasks||0" /><el-statistic title="成功任务" :value="stats.successTasks||0" /></el-card></el-col>
      <el-col :span="18">
        <el-tabs>
          <el-tab-pane label="用户管理">
            <el-table :data="users" stripe>
              <el-table-column prop="username" label="用户名" />
              <el-table-column prop="email" label="邮箱" />
              <el-table-column prop="nickname" label="昵称" />
              <el-table-column label="状态" width="100"><template #default="s"><el-tag :type="s.row.status===1?'success':'danger'">{{ s.row.status===1?'正常':'禁用' }}</el-tag></template></el-table-column>
              <el-table-column label="操作" width="120">
                <template #default="s">
                  <el-button size="small" :type="s.row.status===1?'danger':'success'" @click="toggle(s.row)">{{ s.row.status===1?'禁用':'启用' }}</el-button>
                </template>
              </el-table-column>
            </el-table>
          </el-tab-pane>
          <el-tab-pane label="统计">
            <h4>用户任务排行</h4>
            <el-table :data="ranking" stripe size="small">
              <el-table-column prop="username" label="用户名" />
              <el-table-column prop="nickname" label="昵称" />
              <el-table-column prop="totalTasks" label="总任务" />
              <el-table-column prop="successCount" label="成功" />
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
  data() { return { stats: {}, users: [], ranking: [] } },
  async mounted() { await this.loadData() },
  methods: {
    async loadData() { const [s, u, r] = await Promise.all([adminApi.stats(), adminApi.users(), adminApi.ranking(10)]); this.stats = s.data; this.users = u.data; this.ranking = r.data.top || [] },
    async toggle(row) { await adminApi.toggleUser(row.id, row.status === 1 ? 0 : 1); this.$message.success('状态已更新'); this.loadData() }
  }
}
</script>
