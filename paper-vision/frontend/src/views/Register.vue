<template>
  <div style="max-width:400px;margin:100px auto">
    <h2 style="text-align:center;margin-bottom:30px">注册新账号</h2>
    <el-form :model="form" :rules="rules" ref="formRef">
      <el-form-item prop="username"><el-input v-model="form.username" placeholder="用户名" /></el-form-item>
      <el-form-item prop="password"><el-input v-model="form.password" type="password" placeholder="密码" show-password /></el-form-item>
      <el-form-item prop="email"><el-input v-model="form.email" placeholder="邮箱" /></el-form-item>
      <el-form-item prop="nickname"><el-input v-model="form.nickname" placeholder="昵称(可选)" /></el-form-item>
      <el-form-item>
        <el-button type="primary" @click="register" style="width:100%" :loading="loading">注册</el-button>
      </el-form-item>
    </el-form>
    <div style="text-align:center"><el-button link @click="$router.push('/login')">已有账号？立即登录</el-button></div>
  </div>
</template>
<script>
import { auth } from '../api'
export default {
  data() { return { form: { username: '', password: '', email: '', nickname: '' }, loading: false, rules: { username: [{ required: true }], password: [{ required: true, min: 6 }], email: [{ required: true, type: 'email' }] } } },
  methods: {
    async register() {
      await this.$refs.formRef.validate()
      this.loading = true
      try {
        const res = await auth.register(this.form)
        localStorage.setItem('token', res.token)
        localStorage.setItem('username', res.user.username)
        this.$router.push('/data')
        this.$message.success('注册成功')
      } catch (e) { /* 拦截器已统一提示 */ }
      this.loading = false
    }
  }
}
</script>
