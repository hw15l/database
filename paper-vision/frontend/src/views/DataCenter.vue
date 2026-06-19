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

    <!-- 数据预览弹窗 -->
    <el-dialog v-model="previewVisible" title="数据预览" width="80%">
      <el-table :data="previewData" border max-height="400">
        <el-table-column v-for="(h,i) in previewHeaders" :key="i" :label="h||'列'+(i+1)" width="120">
          <template #default="s">{{ s.row[i] }}</template>
        </el-table-column>
      </el-table>
    </el-dialog>

    <!-- 格式说明弹窗 -->
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
            <p><b>第一行必须是表头（列名）。</b>这些列名会成为图表的坐标轴标签、图例。</p>
            <p>第二行开始是数据行。第一列之后的列应当是数值。</p>
            <p style="color:#E6A23C"><b>第一个文本列 = 分类标签（柱状图/饼图的横轴）。</b></p>
            <p style="color:#409EFF"><b>数值列 = 图表数据（纵轴的值）。</b></p>
            <p style="color:#67C23A">系统会自动提取每一列的列名作为属性名展示，不只是显示数字。</p>

            <p style="margin-top:10px"><b>CSV 示例（含表头）：</b></p>
            <pre style="background:#f5f5f5;padding:10px;border-radius:4px;font-size:12px">商品类别,销售额,利润,数量
电子产品,45000,12000,340
服装,32000,8000,520
食品,28000,5000,680</pre>
            <p style="color:#909399;font-size:12px">上例中：横轴显示"商品类别"（电子产品/服装/食品），纵轴显示"销售额"，图例显示各列名。</p>
          </div>
        </el-tab-pane>

        <el-tab-pane label="各图表数据要求">
          <el-table :data="chartReqs" border size="small">
            <el-table-column prop="chart" label="图表类型" width="140" />
            <el-table-column prop="minCols" label="最少数值列" width="100" />
            <el-table-column prop="usesLabels" label="使用文本标签" width="110" />
            <el-table-column prop="note" label="说明" />
          </el-table>
        </el-tab-pane>

        <el-tab-pane label="安全校验">
          <div style="line-height:1.9;font-size:13px">
            <p><b>魔数校验（Magic Byte）：</b>系统会检查每个文件的前 4 个字节：</p>
            <el-table :data="magicTable" border size="small" style="margin:10px 0">
              <el-table-column prop="ext" label="扩展名" width="90" />
              <el-table-column prop="hex" label="期望字节" width="150" />
              <el-table-column prop="desc" label="含义" />
            </el-table>
            <p style="color:#E6A23C">若文件内容与扩展名不匹配，上传会被拒绝。</p>
            <p>无法伪造：把 <code>.exe</code> 改名成 <code>.csv</code> 会被识别并拒绝。</p>
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
        { ext:'.csv', name:'逗号分隔文件', verify:'首字节 < 0x80（ASCII 文本）', parser:'Pandas CSV 读取器' },
        { ext:'.xlsx', name:'Excel 2007+', verify:'前 2 字节 = 50 4B (PK/ZIP)', parser:'Apache POI / openpyxl' },
        { ext:'.xls', name:'Excel 97-2003', verify:'前 2 字节 = D0 CF (OLE2)', parser:'Apache POI' },
        { ext:'.txt', name:'制表符文本', verify:'首字节 < 0x80（ASCII 文本）', parser:'Pandas（制表符分隔）' },
      ],
      chartReqs: [
        { chart:'柱状图/饼图/环形图', minCols:'1', usesLabels:'是（第1列）', note:'第一个文本列作标签，第一个数值列作数据；标题/坐标轴自动用列名' },
        { chart:'折线图/散点图', minCols:'2', usesLabels:'是', note:'散点图需 2 个数值列（x,y），可选第 3 列作颜色；坐标轴用列名' },
        { chart:'气泡图', minCols:'3', usesLabels:'否', note:'三列：x、y、气泡大小，颜色条标注第 3 列名' },
        { chart:'热力图', minCols:'2', usesLabels:'否', note:'计算各数值列相关性矩阵，行列标签为列名' },
        { chart:'箱线图/小提琴图', minCols:'1', usesLabels:'否', note:'每个数值列对应一个箱体，x 轴标签为列名' },
        { chart:'K线图', minCols:'4', usesLabels:'否', note:'四列：开盘、最高、最低、收盘' },
        { chart:'甘特图', minCols:'2', usesLabels:'是', note:'第1列=任务名，第2列=起始，第3列=持续时间' },
        { chart:'矩形树图/帕累托', minCols:'1', usesLabels:'是', note:'第1列=标签，第2列=大小' },
        { chart:'雷达图/平行坐标', minCols:'3', usesLabels:'否', note:'每个数值列对应一个维度，维度名用列名' },
      ],
      magicTable: [
        { ext:'.csv / .txt', hex:'< 0x80', desc:'必须以 ASCII 文本开头（可打印字符，非二进制）' },
        { ext:'.xlsx', hex:'50 4B 03 04', desc:'ZIP 压缩包签名（PK = Phil Katz）' },
        { ext:'.xls', hex:'D0 CF 11 E0', desc:'OLE2 复合文档（微软 Office 旧格式）' },
      ],
    }
  },
  async mounted() { await this.loadFiles(); this.autoShowHelp() },
  methods: {
    autoShowHelp() { if (!localStorage.getItem('helpDismissed')) { this.helpVisible = true } },
    closeHelp() {
      this.helpVisible = false
      if (this.dontShowAgain) { localStorage.setItem('helpDismissed', '1') }
    },
    async loadFiles() { try { const r = await dataApi.files(); this.files = r.data } catch(e) {} },
    async doUpload(req) {
      try {
        const file = req.file
        const reader = new FileReader()
        const base64 = await new Promise((r, e) => { reader.onload=()=>r(reader.result.split(',')[1]); reader.onerror=e; reader.readAsDataURL(file) })
        await dataApi.upload(file.name, base64)
        this.$message.success('上传成功：'+file.name)
        await this.loadFiles()
      } catch(e) { this.$message.error('上传失败：'+e.message) }
    },
    showFormatHelp() { this.helpVisible = true },
    async preview(row) {
      const r = await dataApi.preview(row.id)
      if (r.data.length > 0) { this.previewHeaders = r.data[0]; this.previewData = r.data.slice(1).map((row,i)=>{ const o={}; row.forEach((v,j)=>o[j]=v); return o }) }
      this.previewVisible = true
    },
    async del(row) {
      try { await this.$confirm('确定删除 '+row.fileName+' ?', '确认', { type:'warning', confirmButtonText:'删除', cancelButtonText:'取消' }) } catch { return }
      await dataApi.del(row.id); this.$message.success('已删除'); await this.loadFiles()
    }
  }
}
</script>