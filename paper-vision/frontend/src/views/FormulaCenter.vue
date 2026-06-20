<template>
  <div>
    <h3>📐 公式渲染中心</h3>
    <el-row :gutter="20">
      <el-col :span="6">
        <el-card>
          <template #header>选择公式类型<el-button size="small" text type="primary" @click="loadFormulas" style="float:right">🔄 刷新</el-button></template>
          <el-radio-group v-model="selectedFormula" style="display:flex;flex-direction:column">
            <el-radio v-for="f in formulas" :key="f.id" :label="f.id" style="margin:5px 0" @change="resetParams">{{ f.formulaName }}</el-radio>
          </el-radio-group>
        </el-card>
        <el-card v-if="currentSchema.length > 0" header="参数配置" style="margin-top:12px">
          <el-form label-width="100px" size="small">
            <el-form-item v-for="field in currentSchema" :key="field.key" :label="field.label">
              <el-input-number v-if="field.type === 'number'"
                v-model="params[field.key]"
                :step="field.step || 1"
                :min="field.min"
                :max="field.max" />
              <el-input v-else
                v-model="params[field.key]"
                :placeholder="field.placeholder || ''" />
            </el-form-item>
          </el-form>
        </el-card>
        <el-button type="primary" @click="generate" style="width:100%;margin-top:12px" :loading="generating">🖊 渲染公式</el-button>
      </el-col>
      <el-col :span="18">
        <el-card v-if="resultImage">
          <template #header>渲染结果 <span style="color:#999;font-size:12px">(点击下载高清图)</span></template>
          <div style="text-align:center;background:#fff;padding:20px">
            <img :src="resultImage" style="max-width:100%" />
          </div>
          <div style="text-align:center;margin-top:8px"><el-button size="small" @click="downloadAll">下载图片</el-button></div>
        </el-card>
        <el-empty v-else description="选择公式类型和参数后，点击渲染" />
      </el-col>
    </el-row>
  </div>
</template>
<script>
import { formulaApi, taskApi } from '../api'
export default {
  data() { return { formulas: [], selectedFormula: null, params: {}, currentSchema: [], generating: false, resultImage: '' } },
  async mounted() { await this.loadFormulas() },
  methods: {
    async loadFormulas() {
      this.formulas = (await formulaApi.list()) || []
    },
    resetParams() {
      const formula = this.formulas.find(f => f.id === this.selectedFormula)
      this.currentSchema = (formula && formula.paramSchema) || []
      this.params = {}
      for (const field of this.currentSchema) {
        if (field.default !== undefined && field.default !== null) {
          this.params[field.key] = field.default
        }
      }
      this.resultImage = ''
    },
    async generate() {
      if (!this.selectedFormula) return this.$message.warning('请选择公式类型')
      this.generating = true
      try {
        const task = await formulaApi.generate({ formulaId: this.selectedFormula, params: this.params })
        if (task.status === 'SUCCESS' && task.resultPath) {
          this.resultImage = URL.createObjectURL(await taskApi.image(task.id))
        }
        this.$message.success('渲染完成')
      } catch (e) { /* 拦截器已统一提示 */ }
      this.generating = false
    },
    downloadAll() {
      if (this.resultImage) { const a = document.createElement('a'); a.href = this.resultImage; a.download = 'formula.png'; a.click() }
    }
  }
}
</script>
