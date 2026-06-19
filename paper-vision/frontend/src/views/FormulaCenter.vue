<template>
  <div>
    <h3>📐 公式渲染中心</h3>
    <el-row :gutter="20">
      <el-col :span="6">
        <el-card>
          <template #header>选择公式类型</template>
          <el-radio-group v-model="selectedFormula" style="display:flex;flex-direction:column">
            <el-radio v-for="f in formulas" :key="f.id" :label="f.id" style="margin:5px 0" @change="resetParams">{{ f.formulaName }}</el-radio>
          </el-radio-group>
        </el-card>
        <el-card v-if="selectedFormula" header="参数配置" style="margin-top:12px">
          <el-form label-width="90px" size="small">
            <template v-if="selectedFormula === 1">
              <el-form-item label="下限 a"><el-input-number v-model="params.a" :step="0.5" /></el-form-item>
              <el-form-item label="上限 b"><el-input-number v-model="params.b" :step="0.5" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 2">
              <el-form-item label="ax"><el-input-number v-model="params.ax" /></el-form-item>
              <el-form-item label="bx"><el-input-number v-model="params.bx" :min="0" /></el-form-item>
              <el-form-item label="ay"><el-input-number v-model="params.ay" /></el-form-item>
              <el-form-item label="by"><el-input-number v-model="params.by" :min="0" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 3">
              <el-form-item label="上限 n"><el-input-number v-model="params.n" :min="1" :max="1000" /></el-form-item>
              <el-form-item label="表达式"><el-input v-model="params.expr" placeholder="i^2" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 4">
              <el-form-item label="n"><el-input-number v-model="params.n" :min="1" :max="100" /></el-form-item>
              <el-form-item label="m"><el-input-number v-model="params.m" :min="1" :max="100" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 5">
              <el-form-item label="第一行"><el-input v-model="params.row1" placeholder="1 2 3" /></el-form-item>
              <el-form-item label="第二行"><el-input v-model="params.row2" placeholder="4 5 6" /></el-form-item>
              <el-form-item label="第三行"><el-input v-model="params.row3" placeholder="7 8 9" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 6">
              <el-form-item label="a"><el-input-number v-model="params.a" /></el-form-item>
              <el-form-item label="b"><el-input-number v-model="params.b" /></el-form-item>
              <el-form-item label="c"><el-input-number v-model="params.c" /></el-form-item>
              <el-form-item label="d"><el-input-number v-model="params.d" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 9">
              <el-form-item label="均值 μ"><el-input-number v-model="params.mu" /></el-form-item>
              <el-form-item label="标准差 σ"><el-input-number v-model="params.sigma" :min="0.1" :step="0.1" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 10">
              <el-form-item label="P(A)"><el-input-number v-model="params.PA" :min="0" :max="1" :step="0.01" /></el-form-item>
              <el-form-item label="P(B|A)"><el-input-number v-model="params.PBA" :min="0" :max="1" :step="0.01" /></el-form-item>
              <el-form-item label="P(B)"><el-input-number v-model="params.PB" :min="0" :max="1" :step="0.01" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 13">
              <el-form-item label="二次系数 a"><el-input-number v-model="params.a" :step="0.5" /></el-form-item>
              <el-form-item label="一次系数 b"><el-input-number v-model="params.b" :step="0.5" /></el-form-item>
              <el-form-item label="常数项 c"><el-input-number v-model="params.c" :step="0.5" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 14">
              <el-form-item label="指数系数"><el-input-number v-model="params.exp" :step="0.5" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 15">
              <el-form-item label="底数"><el-input v-model="params.base" placeholder="e 或数字" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 16">
              <el-form-item label="振幅 A"><el-input-number v-model="params.amplitude" :min="0" :step="0.5" /></el-form-item>
              <el-form-item label="频率 ω"><el-input-number v-model="params.frequency" :min="0" :step="0.5" /></el-form-item>
              <el-form-item label="相位 φ"><el-input-number v-model="params.phase" :step="0.1" /></el-form-item>
            </template>
            <template v-if="selectedFormula === 11">
              <el-form-item label="傅里叶项数"><el-input-number v-model="params.n_terms" :min="1" :max="100" /></el-form-item>
            </template>
          </el-form>
        </el-card>
        <el-button type="primary" @click="generate" style="width:100%;margin-top:12px" :loading="generating">
          🖊 渲染公式
        </el-button>
      </el-col>
      <el-col :span="18">
        <el-card v-if="resultImage">
          <template #header>渲染结果 <span style="color:#999;font-size:12px">(点击下载高清图)</span></template>
          <div style="text-align:center;background:#fff;padding:20px">
            <img :src="resultImage" style="max-width:100%" />
          </div>
          <div style="text-align:center;margin-top:8px">
            <el-button size="small" @click="downloadAll">下载图片</el-button>
          </div>
        </el-card>
        <el-empty v-else description="选择公式类型和参数后，点击渲染" />
      </el-col>
    </el-row>
  </div>
</template>
<script>
import { formulaApi, taskApi } from '../api'
export default {
  data() { return { formulas:[], selectedFormula:null, params:{}, generating:false, resultImage:'' } },
  async mounted() { const r = await formulaApi.list(); this.formulas = r.data },
  methods: {
    resetParams() { this.params = {}; this.resultImage = '' },
    async generate() {
      if (!this.selectedFormula) return this.$message.warning('请选择公式类型')
      this.generating = true
      try {
        const r = await formulaApi.generate({ formulaId: this.selectedFormula, params: this.params })
        const task = r.data
        if (task.status === 'SUCCESS' && task.resultPath) {
          const img = await taskApi.image(task.id)
          this.resultImage = URL.createObjectURL(img.data)
        }
        this.$message.success('渲染完成')
      } catch (e) { this.$message.error('渲染失败: ' + e.message) }
      this.generating = false
    },
    downloadAll() {
      if (this.resultImage) { const a=document.createElement('a'); a.href=this.resultImage; a.download='formula.png'; a.click() }
    }
  }
}
</script>
