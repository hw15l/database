<template>
  <div>
    <h3>📋 历史记录</h3>
    <el-table :data="history" stripe>
      <el-table-column prop="taskType" label="类型" width="80">
        <template #default="s"><el-tag :type="s.row.taskType==='chart'?'primary':'success'" size="small">{{ s.row.taskType==='chart'?'图表':'公式' }}</el-tag></template>
      </el-table-column>
      <el-table-column label="名称"><template #default="s">{{ s.row.chartName || s.row.formulaName }}</template></el-table-column>
      <el-table-column prop="createTime" label="时间" width="170" />
      <el-table-column label="预览" width="150">
        <template #default="s">
          <img v-if="images[s.row.taskId]" :src="images[s.row.taskId]" style="width:60px;height:40px;cursor:pointer;object-fit:cover;border-radius:4px" @click="preview(s.row)" />
          <el-button v-else-if="htmlTasks[s.row.taskId]" size="small" type="primary" text @click="openHtml(s.row)">📊 交互式</el-button>
        </template>
      </el-table-column>
      <el-table-column label="评分" width="160">
        <template #default="s">
          <el-rate v-model="s.row.rating" :max="5" size="small" allow-half @change="rate(s.row)" />
        </template>
      </el-table-column>
      <el-table-column label="操作" width="220">
        <template #default="s">
          <el-button :icon="s.row.isFavorite===1?'StarFilled':'Star'" :type="s.row.isFavorite===1?'warning':''" size="small" circle @click="fav(s.row)" />
          <el-button v-if="images[s.row.taskId]" size="small" @click="preview(s.row)">查看</el-button>
          <el-button v-if="htmlTasks[s.row.taskId]" size="small" @click="openHtml(s.row)">打开</el-button>
          <el-button size="small" @click="download(s.row)">下载</el-button>
          <el-button size="small" type="danger" @click="del(s.row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="previewVisible" width="80%"><img :src="previewImage" style="width:100%" /></el-dialog>
  </div>
</template>
<script>
import { taskApi } from '../api'
export default {
  data() { return { history: [], images: {}, htmlTasks: {}, previewVisible: false, previewImage: '' } },
  async mounted() { await this.loadHistory() },
  methods: {
    async loadHistory() {
      this.history = (await taskApi.history()) || []
      const imgs = {}
      const htmls = {}
      for (const row of this.history) {
        if (!row.taskId) continue
        try {
          const blob = await taskApi.image(row.taskId)
          if (blob.type && blob.type.includes('text/html')) {
            htmls[row.taskId] = true
          } else {
            imgs[row.taskId] = URL.createObjectURL(blob)
          }
        } catch (e) {}
      }
      this.images = imgs
      this.htmlTasks = htmls
    },
    preview(row) { this.previewImage = this.images[row.taskId]; this.previewVisible = true },
    async openHtml(row) {
      const w = window.open('', '_blank')
      if (!w) { this.$message.error('请允许浏览器弹窗'); return }
      w.document.write('<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:sans-serif;color:#666"><p>加载中...</p></body></html>')
      try {
        const blob = await taskApi.image(row.taskId)
        const html = await blob.text()
        w.document.open(); w.document.write(html); w.document.close()
      } catch (e) {
        w.document.open()
        w.document.write('<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:red"><p>加载失败</p></body></html>')
        w.document.close()
      }
    },
    async rate(row) {
      try { await taskApi.rateHistory(row.id, row.rating); this.$message.success('评分已保存') } catch (e) {}
    },
    async fav(row) {
      try {
        await taskApi.toggleFavorite(row.id)
        row.isFavorite = row.isFavorite === 1 ? 0 : 1
        this.$message.success(row.isFavorite === 1 ? '已收藏' : '已取消收藏')
      } catch (e) {}
    },
    async download(row) {
      const blob = await taskApi.image(row.taskId)
      const isHtml = blob.type && blob.type.includes('text/html')
      const a = document.createElement('a')
      a.href = URL.createObjectURL(blob)
      a.download = (row.chartName || row.formulaName || 'result') + (isHtml ? '.html' : '.png')
      a.click()
    },
    async del(row) {
      await taskApi.delHistory(row.id)
      this.$message.success('已删除')
      await this.loadHistory()
    }
  }
}
</script>
