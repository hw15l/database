# Paper Vision 数据库对象说明文档

> 最后更新: 2026-06-19 | MySQL 8.0+ | 数据库: `paper_vision`

---

## 一、总览

| 类别 | 数量 | 说明 |
|------|------|------|
| 基表 | 13 | 原始设计,未新增 |
| 视图 | 9 | 多表联动/窗口函数/递归CTE/JSON聚合 |
| 存储过程 | 9 | 含 sp_write_alert |
| 触发器 | 7 | 状态机/闭包维护/审计/守护 |
| 事件 | 4 | 定时巡检/热点刷新/用户状态/数据清理 |
| 生成列 | 8 | STORED,自动计算 |
| 索引 | 68 | 含覆盖索引/复合索引 |

---

## 二、表结构增强字段

### t_task (新增6列)

| 列名 | 类型 | 说明 | 维护方式 |
|------|------|------|---------|
| `priority` | TINYINT | 优先级 1-10 | Java层写入 |
| `retry_count` | INT | 重试次数 | `sp_task_state_transition` 自动+1 |
| `render_engine` | VARCHAR(30) | 渲染引擎 | `trg_task_before_insert` 自动推断 |
| `execution_log` | JSON | 执行日志 | `sp_task_state_transition` 自动追加 |
| `client_ip` | VARCHAR(45) | 客户端IP | Java层写入 |
| `duration_seconds` | INT | **生成列**: 耗时(秒) | 自动 = finish_time - start_time |

### t_user (新增5列)

| 列名 | 类型 | 说明 | 维护方式 |
|------|------|------|---------|
| `profile` | JSON | 用户画像扩展 | Java层/Event写入 |
| `login_count` | INT | 登录次数 | Java层递增 |
| `last_login_ip` | VARCHAR(45) | 最近登录IP | Java层写入 |
| `account_age_days` | INT | 账号天数 | `evt_daily_user_stats_refresh` |
| `is_active` | TINYINT | 30天活跃标记 | `evt_daily_user_stats_refresh` |

### t_file (新增6列)

| 列名 | 类型 | 说明 | 维护方式 |
|------|------|------|---------|
| `file_hash` | VARCHAR(64) | SHA256去重 | Java层写入 |
| `metadata` | JSON | 文件元数据 | Java层写入 |
| `data_profile` | JSON | 数据画像 | `sp_data_quality_audit` 回写 |
| `upload_ip` | VARCHAR(45) | 上传IP | Java层写入 |
| `file_size_mb` | DECIMAL | **生成列**: MB | 自动 = file_size / 1048576 |
| `cell_count` | INT | **生成列**: 单元格数 | 自动 = total_rows × total_cols |

### t_chart / t_formula (各新增5列)

| 列名 | 类型 | 说明 | 维护方式 |
|------|------|------|---------|
| `complexity_level` | TINYINT | 复杂度 1/2/3 | 管理员设置 |
| `tags` | JSON | 标签数组 | 管理员设置 |
| `version` | VARCHAR(10) | 模板版本 | 管理员设置 |
| `preview_image` | VARCHAR(500) | 预览图 | 管理员设置 |
| `popularity_rank` | VARCHAR(10) | **生成列**: S/A/B/C/D | 由 usage_count 自动推算 |

### t_history (新增6列)

| 列名 | 类型 | 说明 | 维护方式 |
|------|------|------|---------|
| `rating` | TINYINT | 评分 1-5 | 用户操作,触发器守护范围 |
| `tags` | JSON | 用户标签 | 用户操作 |
| `snapshot` | JSON | 任务快照 | `trg_task_after_update` 自动生成 |
| `is_favorite` | TINYINT | 收藏标记 | 用户操作 |
| `deleted_at` | DATETIME | 软删除时间 | `trg_history_soft_delete_guard` 自动填充 |
| `view_count` | INT | 查看次数 | Java层递增 |

---

## 三、视图 (9个)

### 3.1 v_user_profile_360 — 用户360度画像

**用途**: 一次查询获取用户全维度画像,含角色、任务统计、文件统计、历史统计、全站排名、用户分层。

**高级特性**: 6表JOIN · `RANK()`/`PERCENT_RANK()` 窗口函数 · JSON子查询聚合 · 条件聚合

**关键字段**:
- `roles_json` — JSON数组,包含用户所有角色
- `success_rate_pct` — 任务成功率
- `task_count_rank` — 全站排名
- `user_tier` — VIP/高级/普通/新手/未激活

**Java调用**:
```java
databaseService.getUserProfile360(userId);
```

---

### 3.2 v_task_detail_enhanced — 任务详情增强

**用途**: 前端任务详情页一站式查询,含图表/公式/文件信息、分类路径、用户分层、同类排名。

**高级特性**: 6表JOIN · `ROW_NUMBER()`/`LAG()`/`RANK()` 窗口函数 · 闭包表路径拼接 · `COALESCE` 链

**关键字段**:
- `category_path` — 分类面包屑路径(如"统计图表 > 柱状图")
- `user_task_seq` — 该用户的第N个任务
- `minutes_since_last_task` — 距上一任务间隔(分钟)
- `duration_rank_in_type` — 同类型任务耗时排名

**Java调用**:
```java
databaseService.getTaskDetailEnhanced(taskId);
```

---

### 3.3 v_category_tree_full — 分类完整树

**用途**: 展示分类层级关系,含后代数量、完整路径、子分类JSON、图表/公式计数、叶子节点标记。

**高级特性**: 闭包表多维JOIN · `GROUP_CONCAT`路径 · `JSON_ARRAYAGG` 子分类 · `EXISTS`叶子判定

**关键字段**:
- `full_path` — 完整路径(如"分布图表 / 3D图表")
- `descendant_count` — 后代总数
- `children_json` — 直接子分类JSON
- `is_leaf` — 是否叶子节点

**Java调用**:
```java
databaseService.getCategoryTree("chart"); // 或 "formula"
```

---

### 3.4 v_data_quality_dashboard — 数据质量仪表盘

**用途**: 每个上传文件的数据质量评分,含空值率、类型分布、值长度统计、质量等级。

**高级特性**: 生成列引用 · `NTILE(4)` 四分位分桶 · `JSON_OBJECT` 类型分布 · 多层聚合

**关键字段**:
- `null_rate_pct` — 空值率
- `quality_grade` — A/B/C/D/F
- `type_distribution_json` — `{"text":10,"number":7,"date":0,"empty":3}`
- `quality_quartile` — 质量四分位(1最好,4最差)

---

### 3.5 v_trend_analysis_weekly — 周度趋势分析

**用途**: 按周聚合任务量,自动计算环比增长率,用于管理报表和趋势图。

**高级特性**: `YEARWEEK()` 聚合 · `LAG()` 环比 · `SUM() OVER` 累计值 · 嵌套窗口

**关键字段**:
- `task_wow_growth_pct` — 周环比增长率(%)
- `cumulative_tasks` — 累计任务数
- `success_rate_pct` — 当周成功率

**Java调用**:
```java
databaseService.getWeeklyTrend(12); // 最近12周
```

---

### 3.6 v_system_activity_audit — 系统活动审计

**用途**: 将文件上传、任务创建、历史记录等多类活动统一到时间线,用于管理员审计。

**高级特性**: `UNION ALL` 多源汇聚 · `JSON_OBJECT` 封装详情 · 统一schema

**活动类型**: `FILE_UPLOAD` · `TASK_PENDING/PROCESSING/SUCCESS/FAILED` · `HISTORY_CREATE/DELETE`

---

### 3.7 v_hot_items_unified_ranking — 图表/公式统一排行

**用途**: 图表和公式合并排行,统一评分体系,用于首页热门推荐。

**高级特性**: `UNION ALL` 异构合并 · `DENSE_RANK()` 全局+分类双排名

---

### 3.8 v_user_preference_matrix — 用户偏好矩阵

**用途**: 分析用户对图表/公式的使用偏好,用于智能推荐。

**关键字段**: `preferred_type` · `favorite_engine` · `most_used_chart` · `most_used_formula` · `category_distribution`

---

### 3.9 v_category_recursive_tree — 递归CTE分类树

**用途**: 用递归CTE独立于闭包表构建分类树,可用于交叉验证闭包完整性。

**高级特性**: `WITH RECURSIVE` CTE · 闭包表交叉验证 · `CONCAT` 路径拼接

---

## 四、存储过程 (9个)

### 4.1 sp_task_state_transition — 任务状态机

```sql
CALL sp_task_state_transition(p_task_id, p_new_status, p_error_msg);
```

| 参数 | 类型 | 说明 |
|------|------|------|
| p_task_id | BIGINT | 任务ID |
| p_new_status | VARCHAR(20) | 目标状态: PROCESSING/SUCCESS/FAILED/PENDING |
| p_error_msg | TEXT | 失败原因(仅FAILED时有效),可为NULL |

**行为**:
1. `SELECT ... FOR UPDATE` 加行锁(并发安全)
2. 验证状态流转合法性(非法抛出 SQLSTATE 45000)
3. 自动填充 start_time/finish_time
4. FAILED→PENDING时 retry_count + 1
5. 追加执行日志到 execution_log JSON
6. 返回更新后的任务信息

**合法流转**: `PENDING→PROCESSING` · `PROCESSING→SUCCESS` · `PROCESSING→FAILED` · `FAILED→PENDING`

**Java调用**:
```java
databaseService.transitionTaskState(taskId, "PROCESSING", null);
```

---

### 4.2 sp_smart_recommend — 智能推荐

```sql
CALL sp_smart_recommend(p_user_id, p_limit);
```

**行为**: 基于协同过滤思想,找到相似用户(用过相同图表/公式的人),推荐他们用过但当前用户没用过的项目。兜底推荐热门但未使用的图表。

**返回**: 3个结果集(图表推荐、公式推荐、热门兜底)

---

### 4.3 sp_quota_check_and_enforce — 配额管理

```sql
CALL sp_quota_check_and_enforce(p_user_id, 'CHECK');   -- 仅检查
CALL sp_quota_check_and_enforce(p_user_id, 'ENFORCE');  -- 超额抛异常
```

**行为**: 从角色元数据JSON中提取 `max_tasks_per_day`,统计今日任务数,返回配额使用情况。

**返回字段**: `daily_quota` · `today_used` · `today_remaining` · `usage_pct` · `quota_status`(NORMAL/WARNING/EXHAUSTED)

---

### 4.4 sp_data_quality_audit — 数据质量审计

```sql
CALL sp_data_quality_audit(p_file_id);
```

**行为**: 对指定文件进行全面质量审计,输出文件概览+逐列分析+质量评分,并回写 `data_profile` JSON字段。

---

### 4.5 sp_user_profile_analysis — 用户深度画像

```sql
CALL sp_user_profile_analysis(p_user_id);
```

**返回**: 4个结果集(基本画像+月度趋势+TOP5使用项+全站对比)

---

### 4.6 sp_generate_system_report — 系统运营报告

```sql
CALL sp_generate_system_report('2025-01-01', '2025-12-31');
```

**返回**: 6个结果集(KPI概览 · 状态分布 · 每日趋势含7日移动平均 · 引擎分布 · TOP10用户 · TOP10热门项)

---

### 4.7 sp_hot_items_refresh — 热点数据刷新

```sql
CALL sp_hot_items_refresh(10, 7);  -- 阈值10, 近7天
```

**行为**: 重新计算图表/公式的 `is_hot` 标记。双维度: 绝对使用量超阈值 OR 近N天使用≥3次。

---

### 4.8 sp_category_integrity_check — 闭包表完整性检查

```sql
CALL sp_category_integrity_check(0);  -- 仅检查
CALL sp_category_integrity_check(1);  -- 自动修复
```

**行为**: 检查缺失自引用、孤儿闭包、深度不一致等问题。修复模式下自动补全。

---

### 4.9 sp_write_alert — 系统告警写入

```sql
CALL sp_write_alert('source', 'WARN', '告警消息');
```

**行为**: 将告警追加到 admin 用户的 `profile.system_alerts` JSON数组中。被Event Scheduler调用。

---

## 五、触发器 (7个)

### 5.1 trg_task_before_insert — 任务创建前验证

| 属性 | 值 |
|------|-----|
| **表** | t_task |
| **时机** | BEFORE INSERT |
| **规则** | ① 强制初始状态为PENDING ② chart类型必须有chart_id ③ formula类型必须有formula_id ④ 自动推断render_engine(plotly/bokeh/altair/matplotlib) |
| **注意** | 现有Java代码中 `task.setStatus("PROCESSING")` 不会被覆盖(仅覆盖NULL/空),建议逐步改为不设status让触发器接管 |

### 5.2 trg_task_before_insert_seq — 任务计数填充

| 属性 | 值 |
|------|-----|
| **表** | t_task |
| **时机** | BEFORE INSERT (FOLLOWS trg_task_before_insert) |
| **规则** | 自动设置 total_tasks = 当前用户任务数 + 1 |

### 5.3 trg_task_status_guard — 状态机守护

| 属性 | 值 |
|------|-----|
| **表** | t_task |
| **时机** | BEFORE UPDATE |
| **规则** | 仅允许合法状态流转,非法流转抛出SQLSTATE 45000。自动填充start_time(→PROCESSING)和finish_time(→SUCCESS/FAILED) |
| **白名单** | PENDING→PROCESSING · PROCESSING→SUCCESS · PROCESSING→FAILED · FAILED→PENDING |

### 5.4 trg_task_after_update — 任务完成后自动化

| 属性 | 值 |
|------|-----|
| **表** | t_task |
| **时机** | AFTER UPDATE |
| **规则** | 当状态变为SUCCESS时: ① chart/formula的usage_count+1 ② 超阈值自动标记is_hot ③ **自动创建t_history记录(含snapshot JSON)** |
| **注意** | Java层不再需要手动创建History记录,触发器会自动完成 |

### 5.5 trg_history_soft_delete_guard — 历史记录守护

| 属性 | 值 |
|------|-----|
| **表** | t_history |
| **时机** | BEFORE UPDATE |
| **规则** | ① is_deleted 0→1 时自动填充 deleted_at ② rating 范围守护(1-5,超出抛异常) |

### 5.6 trg_category_after_insert — 闭包表自维护(插入)

| 属性 | 值 |
|------|-----|
| **表** | t_category |
| **时机** | AFTER INSERT |
| **规则** | ① 自动插入自引用(depth=0) ② 有parent时自动插入所有祖先关系(通过闭包传递性) |

### 5.7 trg_category_before_update — 闭包表自维护(移动)

| 属性 | 值 |
|------|-----|
| **表** | t_category |
| **时机** | BEFORE UPDATE |
| **规则** | parent_id变更时: ① 断开子树与旧祖先的闭包 ② 与新父的所有祖先建立新闭包(含传递性) |
| **算法** | Bill Karwin 闭包表标准子树移动算法 |
| **测试** | 39项压力测试全部通过(5层深树/跨分支/根互换/连续移动/CTE交叉验证) |

---

## 六、事件调度 (4个)

| 事件名 | 频率 | 时间 | 功能 | 告警 |
|--------|------|------|------|------|
| `evt_daily_user_stats_refresh` | 每天 | 01:00 | 更新账龄/活跃状态 | 活跃率<20%时WARN |
| `evt_daily_hot_refresh` | 每天 | 02:00 | 刷新热门标记 | 异常时ERROR |
| `evt_weekly_integrity_check` | 每周日 | 03:00 | 闭包表完整性检查+修复 | 发现问题时WARN |
| `evt_monthly_history_cleanup` | 每月1号 | 04:00 | 清理>180天软删除记录 | — |

**告警查看**: `SELECT JSON_EXTRACT(profile, '$.system_alerts') FROM t_user WHERE username='admin';`

---

## 七、Java 集成指南

### 7.1 新增文件

| 文件 | 说明 |
|------|------|
| `entity/*.java` × 6 | 所有实体增加了优化列映射 |
| `mapper/DatabaseMapper.java` | 存储过程调用 + 视图查询的统一Mapper |
| `service/DatabaseService.java` | 数据库增强能力Service接口 |
| `service/impl/DatabaseServiceImpl.java` | Service实现,含事务/缓存/日志 |

### 7.2 核心用法

```java
@RequiredArgsConstructor
@RestController
@RequestMapping("/api/enhanced")
public class EnhancedController {
    private final DatabaseService databaseService;

    // 任务状态流转(替代手动UPDATE)
    @PostMapping("/task/{id}/transition")
    public ResponseEntity<?> transitionTask(
            @PathVariable Long id,
            @RequestParam String status,
            @RequestParam(required = false) String errorMsg) {
        return ResponseEntity.ok(
            databaseService.transitionTaskState(id, status, errorMsg));
    }

    // 创建任务前检查配额
    @GetMapping("/quota")
    public ResponseEntity<?> checkQuota(@RequestParam Long userId) {
        return ResponseEntity.ok(databaseService.checkQuota(userId));
    }

    // 智能推荐
    @GetMapping("/recommend")
    public ResponseEntity<?> recommend(@RequestParam Long userId) {
        return ResponseEntity.ok(
            databaseService.getSmartRecommendations(userId, 5));
    }

    // 用户360画像
    @GetMapping("/user/{id}/profile360")
    public ResponseEntity<?> profile360(@PathVariable Long id) {
        return ResponseEntity.ok(databaseService.getUserProfile360(id));
    }
}
```

### 7.3 与现有代码的关系

| 场景 | 原方式 | 新方式(推荐) |
|------|--------|-------------|
| 任务状态变更 | `task.setStatus("SUCCESS"); taskMapper.updateById(task)` + 手动创建History | `databaseService.transitionTaskState(id, "SUCCESS", null)` — 触发器自动创建History |
| 配额检查 | 无 | `databaseService.enforceQuota(userId)` — 超额抛异常 |
| 数据质量 | 无 | `databaseService.runDataQualityAudit(fileId)` — 自动回写data_profile |
| 热门推荐 | 简单按usage_count排序 | `databaseService.getSmartRecommendations(userId, 5)` — 协同过滤 |
| 用户统计 | 多次查询+Java聚合 | `databaseService.getUserProfile360(userId)` — 一次查询全画像 |
| 趋势分析 | 无 | `databaseService.getWeeklyTrend(12)` — 含环比/累计 |

### 7.4 迁移建议

1. **第一阶段**: 引入 `DatabaseService`,新功能(配额/推荐/画像)直接使用
2. **第二阶段**: 将 `ChartServiceImpl.createChartTask()` 中的状态管理改为调用 `sp_task_state_transition`,删除手动创建History的代码(触发器已自动处理)
3. **第三阶段**: 用 `v_task_detail_enhanced` 替代 `TaskController` 中的多次查询拼装

---

## 八、生成列参考

| 表 | 列 | 表达式 | 用途 |
|----|----|--------|------|
| t_task | `duration_seconds` | `TIMESTAMPDIFF(SECOND, start_time, finish_time)` | 任务耗时 |
| t_chart | `popularity_rank` | `CASE usage_count ≥100→S, ≥50→A, ≥20→B, ≥5→C, ELSE→D` | 热度等级 |
| t_formula | `popularity_rank` | 同上 | 热度等级 |
| t_formula | `latex_length` | `CHAR_LENGTH(latex_template)` | 公式复杂度 |
| t_file | `file_size_mb` | `file_size / 1048576` | 文件大小MB |
| t_file | `cell_count` | `total_rows × total_cols` | 数据量 |
| t_data_item | `value_length` | `CHAR_LENGTH(col_value)` | 值长度 |
| t_data_item | `is_null_val` | `col_value IS NULL OR TRIM='')` | 空值标记 |
| t_permission | `perm_level` | 冒号分隔层级数 | 权限深度 |

> 生成列为 `STORED` 类型,Java实体中标记 `@TableField(insertStrategy = NEVER, updateStrategy = NEVER)` 防止写入。

---

## 九、测试覆盖

| 测试文件 | 测试项 | 通过率 |
|---------|--------|--------|
| `test_verification.sql` | 46项(状态机13+前置验证4+自动历史3+历史守护4+闭包5+生成列7+存储过程10) | **46/46** |
| `test_closure_stress.sql` | 39项(5层深树+跨分支+根互换+连续移动+全量完整性+CTE交叉验证) | **39/39** |
| **合计** | **85项** | **85/85 (100%)** |

---

## 十、文件清单

| 文件 | 用途 |
|------|------|
| `sql/init.sql` | 原始建表脚本(不修改) |
| `sql/optimization.sql` | 主优化脚本(含所有增强) |
| `sql/patch_e5_closure_move.sql` | 闭包移动触发器补丁(已合并入optimization.sql) |
| `sql/patch_event_alerting.sql` | 事件告警增强补丁 |
| `sql/test_verification.sql` | 46项自动化验证测试 |
| `sql/test_closure_stress.sql` | 39项闭包压力测试 |
| `backend/.../mapper/DatabaseMapper.java` | 存储过程+视图统一Mapper |
| `backend/.../service/DatabaseService.java` | 数据库增强Service接口 |
| `backend/.../service/impl/DatabaseServiceImpl.java` | Service实现 |
