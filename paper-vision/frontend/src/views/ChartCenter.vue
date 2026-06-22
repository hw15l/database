<template>
  <div>
    <h3>📊 图表生成中心</h3>
    <el-row :gutter="20">
      <el-col :span="6">
        <el-card>
          <template #header>选择图表类型（可多选）<el-button size="small" text type="primary" @click="loadLists" style="float:right">🔄 刷新</el-button></template>
          <el-checkbox-group v-model="selectedCharts" style="display:flex;flex-direction:column">
            <el-checkbox v-for="c in charts" :key="c.id" :label="c.id" style="margin:4px 0">{{ c.chartName }}</el-checkbox>
          </el-checkbox-group>
        </el-card>
        <el-card header="选择数据源" style="margin-top:16px">
          <el-select v-model="selectedFile" placeholder="选择已上传的数据文件" style="width:100%">
            <el-option v-for="f in files" :key="f.id" :label="f.fileName" :value="f.id" />
          </el-select>
        </el-card>
        <el-card header="参数配置" style="margin-top:16px">
          <el-form label-width="70px" size="small">
            <el-form-item label="颜色方案"><el-select v-model="colorScheme" style="width:100%"><el-option v-for="c in colors" :key="c" :label="c" :value="c" /></el-select></el-form-item>
            <el-form-item label="DPI"><el-input-number v-model="dpi" :min="72" :max="600" /></el-form-item>
          </el-form>
        </el-card>
        <el-button type="primary" @click="generateBatch" style="width:100%;margin-top:16px" :loading="generating">
          🎨 生成 {{ selectedCharts.length }} 个图表
        </el-button>
        <el-card v-if="recommendations.length > 0" header="💡 智能推荐" style="margin-top:16px">
          <div v-for="r in recommendations" :key="r.item_id||r.itemId" style="display:flex;justify-content:space-between;align-items:center;padding:4px 0;font-size:13px">
            <span>{{ r.item_name||r.itemName }}</span>
            <el-tag size="small" type="info">{{ r.reason||'推荐' }}</el-tag>
          </div>
        </el-card>
      </el-col>
      <el-col :span="18">
        <el-card>
          <template #header>渲染结果 <span style="color:#999;font-size:12px">(点击图片放大)</span></template>
          <el-empty v-if="results.length === 0 && !generating" description="请勾选图表和数据源后点击生成" />
          <div v-loading="generating" style="display:flex;flex-wrap:wrap;gap:16px">
            <el-card v-for="r in results" :key="r.taskId" shadow="hover" style="width:calc(50% - 8px)">
              <template #header>
                <span style="font-size:13px;font-weight:bold">{{ r.name }}</span>
                <el-tag v-if="r.status==='SUCCESS'" type="success" size="small" style="float:right">成功</el-tag>
                <el-tag v-else type="danger" size="small" style="float:right">失败</el-tag>
              </template>
              <div v-if="r.isHtml" style="text-align:center;padding:20px">
                <el-icon size="40"><Link /></el-icon>
                <p style="font-size:12px;color:#909399">交互式图表</p>
                <el-button size="small" @click="openHtml(r)">在新窗口打开</el-button>
              </div>
              <div v-else-if="r.image" style="text-align:center">
                <el-image :src="r.image" fit="contain" style="max-height:280px;cursor:pointer" @click="zoom(r)" />
                <div style="margin-top:8px"><el-button size="small" @click="download(r)">下载</el-button></div>
              </div>
              <div v-else style="text-align:center;color:#F56C6C;padding:20px">{{ r.error || '渲染失败' }}</div>
            </el-card>
          </div>
        </el-card>
        <el-dialog v-model="showFull" fullscreen>
          <el-image :src="zoomImage" fit="contain" style="width:100%;height:100%" />
        </el-dialog>
      </el-col>
    </el-row>
  </div>
</template>
<script>
import { chartApi, dataApi, taskApi, user } from '../api'
export default {
  data() {
    return {
      charts: [], files: [], selectedCharts: [], selectedFile: null,
      colorScheme: 'Set2', dpi: 300, generating: false,
      results: [], showFull: false, zoomImage: '', recommendations: [],
      colors: ['Set2','Set3','Blues','viridis','plasma','coolwarm','tab10','tab20','Pastel1','Pastel2']
    }
  },
  async mounted() {
    await this.loadLists()
    try { this.recommendations = (await user.recommend(5)) || [] } catch (e) {}
  },
  methods: {
    async loadLists() {
      const [charts, files] = await Promise.all([chartApi.list(), dataApi.files()])
      this.charts = charts || []
      this.files = files || []
    },
    async generateBatch() {
      if (this.selectedCharts.length === 0) return this.$message.warning('请至少勾选一种图表')
      if (!this.selectedFile) return this.$message.warning('请选择数据源文件')
      this.generating = true; this.results = []
      try {
        const tasks = await chartApi.generateBatch({ chartIds: this.selectedCharts, fileId: this.selectedFile, params: { colorScheme: this.colorScheme, dpi: this.dpi } })
        for (const task of tasks) {
          const chart = this.charts.find(c => c.id === task.chartId)
          const item = { taskId: task.id, name: chart ? chart.chartName : '图表', status: task.status, image: '', isHtml: false, error: task.errorMsg }
          if (task.status === 'SUCCESS' && task.resultPath) {
            if (task.resultPath.endsWith('.html')) { item.isHtml = true; item.htmlTaskId = task.id }
            else { try { item.image = URL.createObjectURL(await taskApi.image(task.id)) } catch (e) {} }
          }
          this.results.push(item)
        }
        this.$message.success(`完成：${this.results.filter(x => x.status === 'SUCCESS').length}/${this.results.length} 个图表生成成功`)
        await this.loadLists()
      } catch (e) { /* 拦截器已统一提示 */ }
      this.generating = false
    },
    zoom(r) { this.zoomImage = r.image; this.showFull = true },
    download(r) { const a = document.createElement('a'); a.href = r.image; a.download = r.name + '.png'; a.click() },
    async openHtml(r) {
      const w = window.open('', '_blank')
      if (!w) { this.$message.error('请允许浏览器弹窗'); return }
      w.document.write('<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:sans-serif;color:#666"><p>加载交互式图表中...</p></body></html>')
      try {
        const blob = await taskApi.image(r.htmlTaskId)
        const html = await blob.text()
        w.document.open()
        w.document.write(html)
        w.document.close()
      } catch (e) {
        w.document.open()
        w.document.write('<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:sans-serif;color:red"><p>加载失败，请重试</p></body></html>')
        w.document.close()
      }
    }
  }
}
</script>
