# 论文可视化助手 - Paper Vision

## 项目概述

用户上传数据（Excel/CSV/TXT），选择 22 种科研图表或 12 种数学公式类型，系统自动生成可嵌入论文的高分辨率（300 DPI）图片。

## 技术栈

| 层 | 技术 |
|---|---|
| 前端 | Vue3 + Element Plus + Axios |
| 后端 | Spring Boot 3 + MyBatis Plus + Spring Security + JWT |
| 渲染 | Python FastAPI + Matplotlib + Seaborn + SymPy |
| 数据库 | MySQL 8.0 (12张表、3个视图、3个存储过程、1个触发器) |
| 缓存 | Caffeine (内存缓存) |

## 项目结构

```
paper-vision/
├── sql/init.sql              # 数据库初始化 (12表+视图+触发器+存储过程+索引)
├── backend/                   # Spring Boot 3 后端
│   ├── pom.xml
│   └── src/main/java/com/papervision/
│       ├── PaperVisionApplication.java
│       ├── config/            # SecurityConfig, JwtUtils, AppConfig, CacheConfig
│       ├── controller/        # Auth, User, Data, Chart, Formula, Task, Admin
│       ├── service/           # 接口 (User, Chart, Formula, File, Task)
│       ├── service/impl/      # 实现类
│       ├── mapper/            # MyBatis Plus Mapper (9个)
│       ├── entity/            # 实体类 (9个)
│       └── dto/               # 数据传输对象 (6个)
├── frontend/                  # Vue3 前端
│   ├── index.html / vite.config.js / package.json
│   └── src/
│       ├── main.js / App.vue
│       ├── router/index.js
│       ├── api/index.js
│       └── views/
│           ├── Login.vue      # 登录
│           ├── Register.vue   # 注册
│           ├── DataCenter.vue # 数据上传/预览
│           ├── ChartCenter.vue# 图表生成(22种)
│           ├── FormulaCenter.vue # 公式渲染(12种)
│           ├── History.vue    # 历史记录
│           └── AdminDashboard.vue # 管理后台
└── python-service/            # Python 渲染服务
    ├── main.py                # FastAPI 入口
    ├── chart_service.py       # 22种图表渲染
    ├── formula_service.py     # 12种公式渲染
    └── requirements.txt
```

## API 接口文档

### 认证接口 (无需 token)

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | /api/auth/login | 登录 `{username, password}` |
| POST | /api/auth/register | 注册 `{username, password, email, nickname}` |

### 用户接口 (需 Bearer Token)

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/user/me | 获取当前用户信息 |
| PUT | /api/user/profile | 修改资料 `{email, nickname, avatar}` |
| PUT | /api/user/password | 修改密码 `{oldPassword, newPassword}` |

### 数据中心

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | /api/data/upload | 上传文件 (multipart/form-data, key=file) |
| GET | /api/data/files | 文件列表 |
| GET | /api/data/preview/{fileId}?limit=20 | 数据预览 |
| DELETE | /api/data/{fileId} | 删除文件 |

### 图表生成

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/chart/list | 图表类型列表 |
| GET | /api/chart/category/{catId} | 按分类获取图表 |
| POST | /api/chart/generate | 生成图表 `{chartId, fileId, params}` |

### 公式渲染

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/formula/list | 公式类型列表 |
| GET | /api/formula/category/{catId} | 按分类获取公式 |
| POST | /api/formula/generate | 渲染公式 `{formulaId, latex}` |

### 任务/历史

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/task/list | 我的任务列表 |
| GET | /api/task/{taskId} | 任务详情 |
| GET | /api/task/{taskId}/image | 下载结果图片 |
| GET | /api/task/history | 历史记录 |
| DELETE | /api/task/history/{historyId} | 删除历史 |

### 管理后台 (需 ROLE_ADMIN)

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/admin/stats | 系统统计 |
| GET | /api/admin/ranking?topN=10 | 用户排行 |
| GET | /api/admin/users | 用户列表 |
| PUT | /api/admin/users/{id}/status?status=1 | 启用/禁用用户 |

### Python 渲染服务

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | /render/chart | 渲染图表 `{chart_type, file_path, params}` |
| POST | /render/formula | 渲染公式 `{formula_type, latex}` |
| GET | /health | 健康检查 |

## 启动方式

```bash
# 1. 初始化数据库
mysql -u root -p123456 < sql/init.sql

# 2. 启动 Python 渲染服务
cd python-service
pip install -r requirements.txt
python main.py

# 3. 启动 Spring Boot 后端
cd backend
mvn spring-boot:run

# 4. 启动 Vue 前端
cd frontend
npm install
npm run dev
# 访问 http://localhost:5173
```

## 数据库设计

- **12张表**: t_user, t_role, t_permission, t_user_role, t_role_permission, t_file, t_data_item, t_category, t_category_closure, t_chart, t_formula, t_task, t_history
- **3个视图**: v_hot_charts, v_hot_formulas, v_user_task_stats
- **3个存储过程**: sp_daily_stats, sp_hot_chart_stats, sp_user_ranking
- **1个触发器**: trg_task_after_update (任务完成自动更新图表/公式使用次数)
- **约束**: 主键、外键、唯一约束、非空约束、闭包约束(分类树)
- **索引**: 用户名、任务类型、任务状态、创建时间、图表/公式热度
- **RBAC**: 角色-权限-用户三级权限控制

## 图表支持 (22种)

柱状图 | 分组柱状图 | 堆叠柱状图 | 折线图 | 多折线图 | 散点图 | 气泡图 | 饼图 | 环形图 | 热力图 | 箱线图 | 小提琴图 | 雷达图 | 甘特图 | 桑基图 | Treemap | 平行坐标图 | 词云 | 3D曲面图 | 帕累托图 | K线图 | 面积图

## 公式支持 (12种)

定积分 | 双重积分 | 求和 | 多重求和 | 矩阵 | 行列式 | 偏微分 | 梯度 | 正态分布 | 贝叶斯公式 | 傅里叶变换 | 矩阵乘法
