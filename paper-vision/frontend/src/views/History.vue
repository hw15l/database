<template>
  <div>
    <h3>📋 历史记录</h3>
    <el-table :data="history" stripe>
      <el-table-column prop="taskType" label="类型" width="80">
        <template #default="s"><el-tag :type="s.row.taskType==='chart'?'primary':'success'">{{ s.row.taskType==='chart'?'图表':'公式' }}</el-tag></template>
      </el-table-column>
      <el-table-column label="名称">
        <template #default="s">{{ s.row.chartName || s.row.formulaName }}</template>
      </el-table-column>
      <el-table-column prop="createTime" label="时间" width="180" />
      <el-table-column label="预览" width="120">
        <template #default="s">
          <img v-if="images[s.row.taskId]" :src="images[s.row.taskId]" style="width:60px;height:40px;cursor:pointer" @click="preview(s.row)" />
        </template>
      </el-table-column>
      <el-table-column label="操作" width="200">
        <template #default="s">
          <el-button size="small" @click="download(s.row)">下载</el-button>
          <el-button size="small" type="danger" @click="del(s.row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="previewVisible"><img :src="previewImage" style="width:100%" /></el-dialog>
  </div>
</template>
<script>
import { taskApi } from '../api'
export default {
  data() { return { history: [], images: {}, previewVisible: false, previewImage: '' } },
  async mounted() {
    const r = await taskApi.history(); this.history = r.data
    for (const row of this.history) {
      if (row.taskId) {
        try { const img = await taskApi.image(row.taskId); this.images[row.taskId] = URL.createObjectURL(img.data) } catch (e) {}
      }
    }
  },
  methods: {
    preview(row) { this.previewImage = this.images[row.taskId]; this.previewVisible = true },
    async download(row) { const r = await taskApi.image(row.taskId); const a = document.createElement('a'); a.href = URL.createObjectURL(r.data); a.download = `${row.chartName||row.formulaName}.png`; a.click() },
    async del(row) { await taskApi.delHistory(row.id); this.$message.success('已删除'); const r2 = await taskApi.history(); this.history = r2.data }
  }
}
</script>
