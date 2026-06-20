<template>
  <div>
    <h3>📋 历史记录</h3>
    <el-table :data="history" stripe>
      <el-table-column prop="taskType" label="类型" width="80">
        <template #default="s"><el-tag :type="s.row.taskType==='chart'?'primary':'success'">{{ s.row.taskType==='chart'?'图表':'公式' }}</el-tag></template>
      </el-table-column>
      <el-table-column label="名称"><template #default="s">{{ s.row.chartName || s.row.formulaName }}</template></el-table-column>
      <el-table-column prop="createTime" label="时间" width="180" />
      <el-table-column label="预览" width="150">
        <template #default="s">
          <img v-if="images[s.row.taskId]" :src="images[s.row.taskId]" style="width:60px;height:40px;cursor:pointer;object-fit:cover;border-radius:4px" @click="preview(s.row)" />
          <el-button v-else-if="htmlTasks[s.row.taskId]" size="small" type="primary" text @click="openHtml(s.row)">📊 交互式图表</el-button>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="200">
        <template #default="s">
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
      w.document.write('<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:sans-serif;color:#666"><p>加载交互式图表中...</p></body></html>')
      try {
        const blob = await taskApi.image(row.taskId)
        const html = await blob.text()
        w.document.open()
        w.document.write(html)
        w.document.close()
      } catch (e) {
        w.document.open()
        w.document.write('<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:red"><p>加载失败，请重试</p></body></html>')
        w.document.close()
      }
    },
    async download(row) {
      const blob = await taskApi.image(row.taskId)
      const isHtml = blob.type && blob.type.includes('text/html')
      const a = document.createElement('a')
      a.href = URL.createObjectURL(blob)
      a.download = `${row.chartName || row.formulaName || 'result'}${isHtml ? '.html' : '.png'}`
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
