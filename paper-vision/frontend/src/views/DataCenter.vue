<template>
  <div>
    <h3>数据中心</h3>
    <div style="margin-bottom:12px">
      <el-upload drag :http-request="doUpload" accept=".csv,.xlsx,.xls,.txt" :show-file-list="false">
        <el-icon size="48"><Upload /></el-icon>
        <div>点击或拖拽文件到此处上传（CSV / Excel / TXT）</div>
      </el-upload>
    </div>
    <el-table :data="files" style="margin-top:16px" stripe size="small">
      <el-table-column prop="fileName" label="文件名" min-width="150" />
      <el-table-column prop="fileType" label="类型" width="70" />
      <el-table-column label="大小" width="90"><template #default="s">{{ ((s.row.fileSize||0)/1024).toFixed(1) }} KB</template></el-table-column>
      <el-table-column prop="totalRows" label="行数" width="70" />
      <el-table-column prop="totalCols" label="列数" width="70" />
      <el-table-column label="操作" width="280">
        <template #default="s">
          <el-button size="small" @click="preview(s.row)">预览</el-button>
          <el-button size="small" type="danger" @click="del(s.row)">删除</el-button>
          <el-button size="small" type="info" @click="showFormatHelp">格式说明</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="previewVisible" title="数据预览" width="80%">
      <el-table :data="previewData" border max-height="400">
        <el-table-column v-for="(h,i) in previewHeaders" :key="i" :label="h||'列'+(i+1)" width="120">
          <template #default="s">{{ s.row[i] }}</template>
        </el-table-column>
      </el-table>
    </el-dialog>
    <el-dialog v-model="helpVisible" title="上传文件格式说明" width="720px" :close-on-click-modal="false">
      <el-tabs>
        <el-tab-pane label="支持的格式">
          <el-table :data="formatTable" border size="small">
            <el-table-column prop="ext" label="扩展名" width="90" />
            <el-table-column prop="name" label="类型" width="130" />
            <el-table-column prop="verify" label="识别方式" />
            <el-table-column prop="parser" label="解析引擎" width="150" />
          </el-table>
        </el-tab-pane>
        <el-tab-pane label="数据结构要求">
          <div style="line-height:1.9;font-size:13px">
            <p><b>第一行必须是表头（列名）。</b></p>
            <p>第二行开始是数据行。第一列之后的列应当是数值。</p>
            <p style="color:#E6A23C"><b>第一个文本列 = 分类标签。</b></p>
            <p style="color:#409EFF"><b>数值列 = 图表数据。</b></p>
            <p style="margin-top:10px"><b>CSV 示例：</b></p>
            <pre style="background:#f5f5f5;padding:10px;border-radius:4px;font-size:12px">商品类别,销售额,利润,数量
电子产品,45000,12000,340
服装,32000,8000,520
食品,28000,5000,680</pre>
          </div>
        </el-tab-pane>
        <el-tab-pane label="安全校验">
          <div style="line-height:1.9;font-size:13px">
            <p><b>魔数校验：</b>系统检查文件前4字节确认格式。</p>
            <el-table :data="magicTable" border size="small" style="margin:10px 0">
              <el-table-column prop="ext" label="扩展名" width="90" />
              <el-table-column prop="hex" label="期望字节" width="150" />
              <el-table-column prop="desc" label="含义" />
            </el-table>
            <p style="color:#E6A23C">文件内容与扩展名不匹配将被拒绝。</p>
          </div>
        </el-tab-pane>
      </el-tabs>
      <template #footer>
        <div style="display:flex;justify-content:space-between;align-items:center;width:100%">
          <el-checkbox v-model="dontShowAgain">不再提醒</el-checkbox>
          <el-button type="primary" @click="closeHelp">我知道了</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>
<script>
import { dataApi } from '../api'
export default {
  data() {
    return {
      files: [], previewVisible: false, previewData: [], previewHeaders: [], helpVisible: false, dontShowAgain: false,
      formatTable: [
        { ext:'.csv', name:'逗号分隔文件', verify:'首字节 < 0x80', parser:'Pandas CSV' },
        { ext:'.xlsx', name:'Excel 2007+', verify:'50 4B (PK/ZIP)', parser:'Apache POI' },
        { ext:'.xls', name:'Excel 97-2003', verify:'D0 CF (OLE2)', parser:'Apache POI' },
        { ext:'.txt', name:'制表符文本', verify:'首字节 < 0x80', parser:'Pandas TSV' },
      ],
      magicTable: [
        { ext:'.csv/.txt', hex:'< 0x80', desc:'ASCII 文本开头' },
        { ext:'.xlsx', hex:'50 4B 03 04', desc:'ZIP 签名' },
        { ext:'.xls', hex:'D0 CF 11 E0', desc:'OLE2 签名' },
      ],
    }
  },
  async mounted() { await this.loadFiles(); this.autoShowHelp() },
  methods: {
    autoShowHelp() { if (!localStorage.getItem('helpDismissed')) this.helpVisible = true },
    closeHelp() { this.helpVisible = false; if (this.dontShowAgain) localStorage.setItem('helpDismissed', '1') },
    async loadFiles() { try { this.files = await dataApi.files() } catch(e) {} },
    async doUpload(req) {
      try {
        const file = req.file
        const base64 = await new Promise((r, e) => { const reader = new FileReader(); reader.onload = () => r(reader.result.split(',')[1]); reader.onerror = e; reader.readAsDataURL(file) })
        await dataApi.upload(file.name, base64)
        this.$message.success('上传成功：' + file.name)
        await this.loadFiles()
      } catch(e) { this.$message.error('上传失败：' + e.message) }
    },
    showFormatHelp() { this.helpVisible = true },
    async preview(row) {
      const data = await dataApi.preview(row.id)
      if (data && data.length > 0) { this.previewHeaders = data[0]; this.previewData = data.slice(1).map(row => { const o = {}; row.forEach((v, j) => o[j] = v); return o }) }
      this.previewVisible = true
    },
    async del(row) {
      try { await this.$confirm('确定删除 ' + row.fileName + ' ?', '确认', { type: 'warning' }) } catch { return }
      await dataApi.del(row.id); this.$message.success('已删除'); await this.loadFiles()
    }
  }
}
</script>
