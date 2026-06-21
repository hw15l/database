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
        <el-tabs v-model="activeTab">
          <!-- Tab 1: 用户管理 -->
          <el-tab-pane label="用户管理" name="users">
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

          <!-- Tab 2: 统计排行 -->
          <el-tab-pane label="统计排行" name="ranking">
            <el-table :data="ranking" stripe size="small">
              <el-table-column label="排名" width="70">
                <template #default="s">{{ s.row.taskCountRank || s.row.task_count_rank || '-' }}</template>
              </el-table-column>
              <el-table-column prop="username" label="用户名" />
              <el-table-column prop="nickname" label="昵称" />
              <el-table-column label="总任务" width="90">
                <template #default="s">{{ s.row.totalTasks ?? s.row.total_tasks ?? 0 }}</template>
              </el-table-column>
              <el-table-column label="成功" width="80">
                <template #default="s">{{ s.row.successCount ?? s.row.success_count ?? 0 }}</template>
              </el-table-column>
              <el-table-column label="成功率%" width="90">
                <template #default="s">{{ s.row.successRatePct ?? s.row.success_rate_pct ?? 0 }}</template>
              </el-table-column>
              <el-table-column label="等级" width="90">
                <template #default="s"><el-tag size="small">{{ s.row.userTier || s.row.user_tier || '-' }}</el-tag></template>
              </el-table-column>
            </el-table>
          </el-tab-pane>

          <!-- Tab 3: 热门内容 -->
          <el-tab-pane label="热门内容" name="hotItems">
            <el-table :data="hotItems" stripe size="small">
              <el-table-column label="#" width="50">
                <template #default="s">{{ s.row.globalRank || s.row.global_rank || s.$index + 1 }}</template>
              </el-table-column>
              <el-table-column label="类型" width="80">
                <template #default="s">
                  <el-tag :type="(s.row.itemType||s.row.item_type)==='chart'?'primary':'success'" size="small">
                    {{ (s.row.itemType||s.row.item_type)==='chart'?'图表':'公式' }}
                  </el-tag>
                </template>
              </el-table-column>
              <el-table-column label="名称">
                <template #default="s">
                  {{ s.row.itemName || s.row.item_name }}
                  <el-tag v-if="(s.row.isHot||s.row.is_hot)==1" type="danger" size="small" style="margin-left:6px">HOT</el-tag>
                </template>
              </el-table-column>
              <el-table-column label="使用次数" width="100">
                <template #default="s">{{ s.row.usageCount ?? s.row.usage_count ?? 0 }}</template>
              </el-table-column>
              <el-table-column label="分类" width="120">
                <template #default="s">{{ s.row.categoryName || s.row.category_name || '-' }}</template>
              </el-table-column>
              <el-table-column label="热度等级" width="100">
                <template #default="s">
                  <el-tag :type="hotLevelType(s.row.popularityRank||s.row.popularity_rank)" size="small">
                    {{ s.row.popularityRank || s.row.popularity_rank || '-' }}
                  </el-tag>
                </template>
              </el-table-column>
            </el-table>
          </el-tab-pane>

          <!-- Tab 4: 周趋势 -->
          <el-tab-pane label="周趋势" name="trend">
            <el-table :data="trend" stripe size="small">
              <el-table-column label="周次" width="100">
                <template #default="s">{{ s.row.year_week }}</template>
              </el-table-column>
              <el-table-column label="起始日期" width="110">
                <template #default="s">{{ formatDate(s.row.week_start_date) }}</template>
              </el-table-column>
              <el-table-column label="任务数" width="80">
                <template #default="s">{{ s.row.total_tasks }}</template>
              </el-table-column>
              <el-table-column label="环比增长" width="110">
                <template #default="s">
                  <span v-if="s.row.task_wow_growth_pct != null" :style="{color: s.row.task_wow_growth_pct >= 0 ? '#67C23A' : '#F56C6C'}">
                    {{ s.row.task_wow_growth_pct >= 0 ? '+' : '' }}{{ s.row.task_wow_growth_pct }}%
                  </span>
                  <span v-else style="color:#999">-</span>
                </template>
              </el-table-column>
              <el-table-column label="图表/公式" width="100">
                <template #default="s">{{ s.row.chart_tasks || 0 }} / {{ s.row.formula_tasks || 0 }}</template>
              </el-table-column>
              <el-table-column label="活跃用户" width="90">
                <template #default="s">{{ s.row.active_users }}</template>
              </el-table-column>
              <el-table-column label="成功率" width="80">
                <template #default="s">{{ s.row.success_rate_pct || 0 }}%</template>
              </el-table-column>
              <el-table-column label="累计" width="80">
                <template #default="s">{{ s.row.cumulative_tasks }}</template>
              </el-table-column>
            </el-table>
          </el-tab-pane>

          <!-- Tab 5: 分类概览 -->
          <el-tab-pane label="分类概览" name="category">
            <el-radio-group v-model="catType" size="small" style="margin-bottom:12px" @change="loadCategoryTree">
              <el-radio-button label="chart">图表分类</el-radio-button>
              <el-radio-button label="formula">公式分类</el-radio-button>
            </el-radio-group>
            <el-table :data="categoryTree" stripe size="small" row-key="cat_id" default-expand-all>
              <el-table-column label="分类名称">
                <template #default="s">
                  <span :style="{paddingLeft: (s.row.node_depth||0)*20+'px'}">
                    {{ s.row.node_depth > 0 ? '└ ' : '' }}{{ s.row.cat_name }}
                  </span>
                </template>
              </el-table-column>
              <el-table-column label="完整路径">
                <template #default="s">{{ s.row.full_path || s.row.cat_name }}</template>
              </el-table-column>
              <el-table-column label="图表数" width="80">
                <template #default="s">{{ s.row.chart_count || 0 }}</template>
              </el-table-column>
              <el-table-column label="公式数" width="80">
                <template #default="s">{{ s.row.formula_count || 0 }}</template>
              </el-table-column>
              <el-table-column label="子分类" width="80">
                <template #default="s">{{ s.row.descendant_count || 0 }}</template>
              </el-table-column>
              <el-table-column label="层级" width="70">
                <template #default="s">{{ s.row.node_depth || 0 }}</template>
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
  data() {
    return {
      stats: {}, users: [], ranking: [], hotItems: [], trend: [], categoryTree: [],
      activeTab: 'users', catType: 'chart', refreshing: false
    }
  },
  async mounted() { await this.loadData() },
  methods: {
    async loadData() {
      const [stats, users, ranking, hotItems, trend, catTree] = await Promise.all([
        adminApi.stats(), adminApi.users(), adminApi.ranking(10),
        adminApi.hotItems(20), adminApi.trend(12), adminApi.categoryTree('chart')
      ])
      this.stats = stats || {}
      this.users = users || []
      this.ranking = (ranking && ranking.top) || []
      this.hotItems = hotItems || []
      this.trend = (trend || []).reverse()
      this.categoryTree = catTree || []
    },
    async loadCategoryTree() {
      this.categoryTree = (await adminApi.categoryTree(this.catType)) || []
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
      } catch (e) { /* */ }
      this.refreshing = false
    },
    hotLevelType(rank) {
      if (rank === 'S') return 'danger'
      if (rank === 'A') return 'warning'
      if (rank === 'B') return 'primary'
      return 'info'
    },
    formatDate(d) {
      if (!d) return '-'
      return String(d).substring(0, 10)
    }
  }
}
</script>
