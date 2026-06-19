<template>
  <div style="max-width:400px;margin:100px auto">
    <h2 style="text-align:center;margin-bottom:30px">论文可视化助手 - 登录</h2>
    <el-form :model="form" :rules="rules" ref="formRef">
      <el-form-item prop="username"><el-input v-model="form.username" placeholder="用户名" prefix-icon="User" /></el-form-item>
      <el-form-item prop="password"><el-input v-model="form.password" type="password" placeholder="密码" prefix-icon="Lock" show-password /></el-form-item>
      <el-form-item>
        <el-button type="primary" @click="login" style="width:100%" :loading="loading">登录</el-button>
      </el-form-item>
    </el-form>
    <div style="text-align:center"><el-button link @click="$router.push('/register')">没有账号？立即注册</el-button></div>
  </div>
</template>
<script>
import { auth } from '../api'
export default {
  data() { return { form: { username: '', password: '' }, loading: false, rules: { username: [{ required: true, message: '请输入用户名' }], password: [{ required: true, message: '请输入密码' }] } } },
  methods: {
    async login() {
      await this.$refs.formRef.validate()
      this.loading = true
      try {
        const res = await auth.login(this.form)
        localStorage.setItem('token', res.token)
        localStorage.setItem('username', res.user.username)
        this.$router.push('/data')
        this.$message.success('登录成功')
      } catch (e) { this.$message.error('登录失败: ' + e.message); }
      this.loading = false
    }
  }
}
</script>
