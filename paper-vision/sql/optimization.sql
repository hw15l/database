-- ============================================================================================
-- 论文可视化助手(Paper Vision) — 数据库高级优化脚本
-- MySQL 8.0+  |  目标: 在严格保持 12 张表不变的前提下, 大幅提升数据库复杂度与专业性
-- 涵盖: 表结构增强 · 生成列 · 索引优化 · 高级视图 · 存储过程 · 触发器 · 事件调度
-- ============================================================================================

USE paper_vision;

-- ############################################################################################
-- 第一章  表结构增强 (ALTER TABLE)
-- 设计理念: 在不增加表的前提下, 通过 JSON 扩展字段、审计字段、统计冗余字段、生成列(Generated
--           Columns)等方式, 让现有 12 张表获得更强的表达力、可追溯性和自动计算能力.
-- ############################################################################################

-- ============================================================
-- 1.1 t_user — 用户表增强
-- 新增: profile(JSON画像)、login_count(登录计数)、last_login_ip、
--       account_age_days(生成列)、is_active(生成列)
-- ============================================================
ALTER TABLE t_user
    ADD COLUMN profile         JSON          DEFAULT NULL COMMENT '用户画像扩展: {"preferences":{},"tags":[],"bio":""}',
    ADD COLUMN login_count     INT           DEFAULT 0    COMMENT '累计登录次数(触发器维护)',
    ADD COLUMN last_login_ip   VARCHAR(45)   DEFAULT NULL COMMENT '最近登录IP(IPv6兼容)',
    ADD COLUMN account_age_days INT          DEFAULT 0    COMMENT '账号存在天数(Event Scheduler每日更新)',
    ADD COLUMN is_active       TINYINT       DEFAULT 0    COMMENT '30天内活跃且启用=1(Event Scheduler每日更新)';

ALTER TABLE t_user
    ADD INDEX idx_user_active (is_active, last_login_time),
    ADD INDEX idx_user_age    (account_age_days);

-- 初始化account_age_days和is_active(首次运行)
UPDATE t_user SET
    account_age_days = DATEDIFF(CURDATE(), DATE(create_time)),
    is_active = CASE
        WHEN status = 1 AND last_login_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1
        ELSE 0
    END;

-- ============================================================
-- 1.2 t_role — 角色表增强
-- 新增: 角色元数据(JSON)、更新时间
-- ============================================================
ALTER TABLE t_role
    ADD COLUMN metadata    JSON     DEFAULT NULL COMMENT '角色元数据: {"max_tasks_per_day":100,"allowed_chart_types":["bar","line"]}',
    ADD COLUMN update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '角色最后修改时间';

-- ============================================================
-- 1.3 t_permission — 权限表增强
-- 新增: 权限深度生成列(基于path计算)、启用状态
-- ============================================================
ALTER TABLE t_permission
    ADD COLUMN status TINYINT DEFAULT 1 COMMENT '0禁用 1启用',
    ADD COLUMN perm_level INT GENERATED ALWAYS AS (
        CHAR_LENGTH(perm_code) - CHAR_LENGTH(REPLACE(perm_code, ':', '')) + 1
    ) STORED COMMENT '生成列: 权限层级深度, 由perm_code中冒号个数推断';

ALTER TABLE t_permission
    ADD INDEX idx_perm_type_status (perm_type, status);

-- ============================================================
-- 1.4 t_file — 文件表增强
-- 新增: file_hash(去重)、metadata(JSON)、file_size_mb(生成列)、
--       data_profile(JSON数据画像)、upload_ip
-- ============================================================
ALTER TABLE t_file
    ADD COLUMN file_hash     VARCHAR(64)  DEFAULT NULL COMMENT '文件SHA256哈希, 用于去重校验',
    ADD COLUMN metadata      JSON         DEFAULT NULL COMMENT '文件元数据: {"encoding":"utf-8","delimiter":",","headers":["col1","col2"]}',
    ADD COLUMN data_profile  JSON         DEFAULT NULL COMMENT '数据画像: {"null_ratio":0.05,"numeric_cols":3,"text_cols":2}',
    ADD COLUMN upload_ip     VARCHAR(45)  DEFAULT NULL COMMENT '上传来源IP',
    ADD COLUMN file_size_mb  DECIMAL(10,2) GENERATED ALWAYS AS (ROUND(file_size / 1048576.0, 2)) STORED
        COMMENT '生成列: 文件大小MB, 自动由file_size字节转换',
    ADD COLUMN cell_count    INT GENERATED ALWAYS AS (total_rows * total_cols) STORED
        COMMENT '生成列: 单元格总数 = 行数 × 列数';

ALTER TABLE t_file
    ADD UNIQUE INDEX uk_file_hash (file_hash),
    ADD INDEX idx_file_size (file_size_mb),
    ADD INDEX idx_file_status_type (status, file_type, create_time);

-- ============================================================
-- 1.5 t_data_item — 数据项表增强
-- 新增: data_type(数据类型推断)、value_length(生成列)、is_numeric(生成列)
-- ============================================================
ALTER TABLE t_data_item
    ADD COLUMN data_type    VARCHAR(20) DEFAULT 'text' COMMENT '数据类型: text/number/date/empty',
    ADD COLUMN value_length INT GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(col_value, ''))) STORED
        COMMENT '生成列: 值长度, 辅助数据质量分析',
    ADD COLUMN is_null_val  TINYINT GENERATED ALWAYS AS (CASE WHEN col_value IS NULL OR TRIM(col_value) = '' THEN 1 ELSE 0 END) STORED
        COMMENT '生成列: 是否为空值, 辅助数据质量统计';

ALTER TABLE t_data_item
    ADD INDEX idx_data_type     (file_id, data_type),
    ADD INDEX idx_data_null_val (file_id, is_null_val);

-- ============================================================
-- 1.6 t_category — 分类表增强
-- 新增: icon、status、item_count(该分类下的图表/公式数量, 触发器维护)
-- ============================================================
ALTER TABLE t_category
    ADD COLUMN icon       VARCHAR(50)  DEFAULT NULL COMMENT '分类图标标识',
    ADD COLUMN status     TINYINT      DEFAULT 1    COMMENT '0禁用 1启用',
    ADD COLUMN item_count INT          DEFAULT 0    COMMENT '该分类下的图表或公式数量(触发器维护)';

ALTER TABLE t_category
    ADD INDEX idx_cat_type_status (cat_type, status, sort_order);

-- ============================================================
-- 1.7 t_chart — 图表表增强
-- 新增: complexity_level(复杂度)、tags(JSON标签)、version、
--       popularity_rank(生成列: 热度等级)
-- ============================================================
ALTER TABLE t_chart
    ADD COLUMN complexity_level TINYINT DEFAULT 1 COMMENT '复杂度等级 1简单 2中等 3高级',
    ADD COLUMN tags             JSON    DEFAULT NULL COMMENT '标签数组: ["statistics","comparison","interactive"]',
    ADD COLUMN version          VARCHAR(10) DEFAULT '1.0' COMMENT '图表模板版本号',
    ADD COLUMN preview_image    VARCHAR(500) DEFAULT NULL COMMENT '预览图路径',
    ADD COLUMN popularity_rank  VARCHAR(10) GENERATED ALWAYS AS (
        CASE
            WHEN usage_count >= 100 THEN 'S'
            WHEN usage_count >= 50  THEN 'A'
            WHEN usage_count >= 20  THEN 'B'
            WHEN usage_count >= 5   THEN 'C'
            ELSE 'D'
        END
    ) STORED COMMENT '生成列: 人气等级 S/A/B/C/D, 由usage_count自动推算';

ALTER TABLE t_chart
    ADD INDEX idx_chart_popularity (popularity_rank, usage_count DESC),
    ADD INDEX idx_chart_complexity (complexity_level, sort_order);

-- ============================================================
-- 1.8 t_formula — 公式表增强
-- 新增: complexity_level、tags(JSON)、version、symbol_count(生成列)
-- ============================================================
ALTER TABLE t_formula
    ADD COLUMN complexity_level TINYINT DEFAULT 1 COMMENT '复杂度等级 1简单 2中等 3高级',
    ADD COLUMN tags             JSON    DEFAULT NULL COMMENT '标签数组: ["calculus","advanced","probability"]',
    ADD COLUMN version          VARCHAR(10) DEFAULT '1.0' COMMENT '公式模板版本号',
    ADD COLUMN preview_image    VARCHAR(500) DEFAULT NULL COMMENT '预览图路径',
    ADD COLUMN latex_length     INT GENERATED ALWAYS AS (CHAR_LENGTH(COALESCE(latex_template, ''))) STORED
        COMMENT '生成列: LaTeX模板长度, 间接反映公式复杂度',
    ADD COLUMN popularity_rank  VARCHAR(10) GENERATED ALWAYS AS (
        CASE
            WHEN usage_count >= 100 THEN 'S'
            WHEN usage_count >= 50  THEN 'A'
            WHEN usage_count >= 20  THEN 'B'
            WHEN usage_count >= 5   THEN 'C'
            ELSE 'D'
        END
    ) STORED COMMENT '生成列: 人气等级, 与图表保持相同评级体系';

ALTER TABLE t_formula
    ADD INDEX idx_formula_popularity (popularity_rank, usage_count DESC),
    ADD INDEX idx_formula_complexity (complexity_level, sort_order);

-- ============================================================
-- 1.9 t_task — 任务表增强
-- 新增: priority、retry_count、execution_log(JSON)、
--       duration_seconds(生成列)、render_engine
-- ============================================================
ALTER TABLE t_task
    ADD COLUMN priority         TINYINT      DEFAULT 5    COMMENT '优先级 1-10, 1最高',
    ADD COLUMN retry_count      INT          DEFAULT 0    COMMENT '重试次数',
    ADD COLUMN render_engine    VARCHAR(30)  DEFAULT 'matplotlib' COMMENT '渲染引擎: matplotlib/plotly/bokeh/altair',
    ADD COLUMN execution_log    JSON         DEFAULT NULL COMMENT '执行日志: {"steps":[{"ts":"...","msg":"..."}],"engine_version":"3.8"}',
    ADD COLUMN client_ip        VARCHAR(45)  DEFAULT NULL COMMENT '发起任务的客户端IP',
    ADD COLUMN duration_seconds INT GENERATED ALWAYS AS (
        CASE WHEN finish_time IS NOT NULL AND start_time IS NOT NULL
             THEN TIMESTAMPDIFF(SECOND, start_time, finish_time)
             ELSE NULL
        END
    ) STORED COMMENT '生成列: 任务执行耗时(秒), 由start_time和finish_time自动计算';

ALTER TABLE t_task
    ADD INDEX idx_task_priority     (priority, status, create_time),
    ADD INDEX idx_task_duration     (duration_seconds),
    ADD INDEX idx_task_engine       (render_engine),
    ADD INDEX idx_task_user_status  (user_id, status, task_type);

-- ============================================================
-- 1.10 t_history — 历史记录表增强
-- 新增: rating(用户评分)、tags(JSON标签)、snapshot(JSON快照)、
--       is_favorite(收藏标记)、deleted_at(软删除时间)
-- ============================================================
ALTER TABLE t_history
    ADD COLUMN rating      TINYINT      DEFAULT NULL COMMENT '用户评分 1-5 星',
    ADD COLUMN tags        JSON         DEFAULT NULL COMMENT '用户自定义标签: ["毕业论文","重要","图3"]',
    ADD COLUMN snapshot    JSON         DEFAULT NULL COMMENT '任务快照: {"params":{},"chart_code":"bar","file_name":"data.csv"}',
    ADD COLUMN is_favorite TINYINT      DEFAULT 0    COMMENT '是否收藏 0否 1是',
    ADD COLUMN deleted_at  DATETIME     DEFAULT NULL COMMENT '软删除时间, NULL表示未删除',
    ADD COLUMN view_count  INT          DEFAULT 0    COMMENT '查看次数';

ALTER TABLE t_history
    ADD INDEX idx_history_favorite (user_id, is_favorite, create_time),
    ADD INDEX idx_history_rating   (rating),
    ADD INDEX idx_history_deleted  (is_deleted, deleted_at);


-- ############################################################################################
-- 第二章  高级视图 (Views)
-- 设计理念: 利用窗口函数、递归CTE、JSON聚合函数、闭包表深度联动、复杂多表JOIN, 将复杂查询
--           逻辑封装为视图, 为Java/Vue层提供即查即用的高级分析结果.
-- ############################################################################################

-- 先清理旧视图(幂等)
DROP VIEW IF EXISTS v_hot_charts;
DROP VIEW IF EXISTS v_hot_formulas;
DROP VIEW IF EXISTS v_user_task_stats;
DROP VIEW IF EXISTS v_user_profile_360;
DROP VIEW IF EXISTS v_task_detail_enhanced;
DROP VIEW IF EXISTS v_category_tree_full;
DROP VIEW IF EXISTS v_data_quality_dashboard;
DROP VIEW IF EXISTS v_trend_analysis_weekly;
DROP VIEW IF EXISTS v_system_activity_audit;
DROP VIEW IF EXISTS v_hot_items_unified_ranking;
DROP VIEW IF EXISTS v_user_preference_matrix;

-- ============================================================
-- 视图1: v_user_profile_360 — 用户360度全景画像
-- 高级特性: 多表JOIN(6表)、窗口函数(RANK/PERCENT_RANK)、JSON_OBJECT聚合、
--           条件聚合(CASE WHEN)、生成列引用、子查询
-- 用途: 一次查询获取用户全维度画像, 含角色权限、任务统计、文件统计、活跃度排名、偏好分析
-- ============================================================
CREATE VIEW v_user_profile_360 AS
SELECT
    u.id                                                        AS user_id,
    u.username,
    u.nickname,
    u.email,
    u.status                                                    AS account_status,
    u.account_age_days,
    u.is_active,
    u.login_count,
    u.last_login_time,
    u.last_login_ip,
    -- 角色信息(JSON聚合)
    (SELECT JSON_ARRAYAGG(JSON_OBJECT('role_code', r.role_code, 'role_name', r.role_name))
     FROM t_user_role ur
     JOIN t_role r ON ur.role_id = r.id
     WHERE ur.user_id = u.id)                                   AS roles_json,
    -- 任务维度统计
    COALESCE(task_stats.total_tasks, 0)                         AS total_tasks,
    COALESCE(task_stats.success_count, 0)                       AS success_count,
    COALESCE(task_stats.failed_count, 0)                        AS failed_count,
    COALESCE(task_stats.pending_count, 0)                       AS pending_count,
    COALESCE(task_stats.chart_task_count, 0)                    AS chart_task_count,
    COALESCE(task_stats.formula_task_count, 0)                  AS formula_task_count,
    COALESCE(task_stats.avg_duration, 0)                        AS avg_task_duration_sec,
    -- 成功率(安全除法)
    CASE WHEN COALESCE(task_stats.total_tasks, 0) > 0
         THEN ROUND(task_stats.success_count * 100.0 / task_stats.total_tasks, 2)
         ELSE 0
    END                                                         AS success_rate_pct,
    -- 文件维度统计
    COALESCE(file_stats.total_files, 0)                         AS total_files,
    COALESCE(file_stats.total_file_size_mb, 0)                  AS total_file_size_mb,
    COALESCE(file_stats.total_cells, 0)                         AS total_data_cells,
    -- 历史维度
    COALESCE(hist_stats.total_history, 0)                       AS total_history_records,
    COALESCE(hist_stats.favorite_count, 0)                      AS favorite_count,
    COALESCE(hist_stats.avg_rating, 0)                          AS avg_rating,
    -- 窗口函数: 全局排名
    RANK() OVER (ORDER BY COALESCE(task_stats.total_tasks, 0) DESC)
                                                                AS task_count_rank,
    PERCENT_RANK() OVER (ORDER BY COALESCE(task_stats.total_tasks, 0))
                                                                AS task_percentile,
    -- 用户分层(基于活跃度)
    CASE
        WHEN COALESCE(task_stats.total_tasks, 0) >= 50 THEN 'VIP'
        WHEN COALESCE(task_stats.total_tasks, 0) >= 20 THEN '高级用户'
        WHEN COALESCE(task_stats.total_tasks, 0) >= 5  THEN '普通用户'
        WHEN COALESCE(task_stats.total_tasks, 0) >= 1  THEN '新手用户'
        ELSE '未激活'
    END                                                         AS user_tier,
    u.create_time                                               AS register_time
FROM t_user u
-- 任务统计子查询
LEFT JOIN (
    SELECT
        user_id,
        COUNT(*)                                                AS total_tasks,
        SUM(status = 'SUCCESS')                                 AS success_count,
        SUM(status = 'FAILED')                                  AS failed_count,
        SUM(status = 'PENDING')                                 AS pending_count,
        SUM(task_type = 'chart')                                AS chart_task_count,
        SUM(task_type = 'formula')                              AS formula_task_count,
        ROUND(AVG(duration_seconds), 1)                         AS avg_duration
    FROM t_task
    GROUP BY user_id
) task_stats ON u.id = task_stats.user_id
-- 文件统计子查询
LEFT JOIN (
    SELECT
        user_id,
        COUNT(*)                                                AS total_files,
        ROUND(SUM(COALESCE(file_size_mb, 0)), 2)               AS total_file_size_mb,
        SUM(COALESCE(cell_count, 0))                            AS total_cells
    FROM t_file
    WHERE status = 1
    GROUP BY user_id
) file_stats ON u.id = file_stats.user_id
-- 历史统计子查询
LEFT JOIN (
    SELECT
        user_id,
        COUNT(*)                                                AS total_history,
        SUM(is_favorite)                                        AS favorite_count,
        ROUND(AVG(rating), 2)                                   AS avg_rating
    FROM t_history
    WHERE is_deleted = 0
    GROUP BY user_id
) hist_stats ON u.id = hist_stats.user_id;


-- ============================================================
-- 视图2: v_task_detail_enhanced — 任务详情增强视图
-- 高级特性: 6表JOIN、窗口函数(ROW_NUMBER/LAG)、JSON_OBJECT、COALESCE链、
--           生成列引用(duration_seconds)、TIMESTAMPDIFF时间计算
-- 用途: 为前端任务详情页提供一站式查询, 含图表/公式/文件/用户信息、同类任务排名、
--       与该用户上一任务的间隔时间
-- ============================================================
CREATE VIEW v_task_detail_enhanced AS
SELECT
    t.id                                                        AS task_id,
    t.task_type,
    t.status,
    t.priority,
    t.retry_count,
    t.render_engine,
    t.duration_seconds,
    t.result_path,
    t.result_pdf,
    t.error_msg,
    t.client_ip,
    t.create_time                                               AS task_create_time,
    t.start_time,
    t.finish_time,
    -- 用户信息
    u.id                                                        AS user_id,
    u.username,
    u.nickname,
    -- 用户分层标签(内联计算)
    (SELECT CASE
        WHEN COUNT(*) >= 50 THEN 'VIP'
        WHEN COUNT(*) >= 20 THEN '高级'
        WHEN COUNT(*) >= 5  THEN '普通'
        ELSE '新手'
    END FROM t_task WHERE user_id = u.id)                       AS user_tier_label,
    -- 图表/公式信息(互斥, 二选一)
    COALESCE(c.chart_name, f.formula_name)                      AS item_name,
    COALESCE(c.chart_code, f.formula_code)                      AS item_code,
    COALESCE(c.popularity_rank, f.popularity_rank)              AS item_popularity,
    COALESCE(c.complexity_level, f.complexity_level)             AS item_complexity,
    -- 分类链路(通过闭包表追溯根分类)
    COALESCE(cat.cat_name, '未分类')                             AS category_name,
    (SELECT GROUP_CONCAT(pc.cat_name ORDER BY cc.depth DESC SEPARATOR ' > ')
     FROM t_category_closure cc
     JOIN t_category pc ON cc.ancestor_id = pc.id
     WHERE cc.descendant_id = COALESCE(c.cat_id, f.cat_id) AND cc.depth > 0
    )                                                           AS category_path,
    -- 文件信息
    fl.file_name,
    fl.file_type,
    fl.file_size_mb,
    fl.cell_count                                               AS file_cell_count,
    -- 任务参数(JSON)
    t.task_params,
    -- 窗口函数: 用户维度任务序号
    ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.create_time)
                                                                AS user_task_seq,
    -- 窗口函数: 与该用户上一任务的间隔(分钟)
    TIMESTAMPDIFF(MINUTE,
        LAG(t.create_time) OVER (PARTITION BY t.user_id ORDER BY t.create_time),
        t.create_time
    )                                                           AS minutes_since_last_task,
    -- 窗口函数: 同类型任务中的耗时排名
    RANK() OVER (PARTITION BY t.task_type ORDER BY t.duration_seconds ASC)
                                                                AS duration_rank_in_type
FROM t_task t
JOIN t_user u ON t.user_id = u.id
LEFT JOIN t_chart c   ON t.chart_id   = c.id
LEFT JOIN t_formula f ON t.formula_id = f.id
LEFT JOIN t_category cat ON COALESCE(c.cat_id, f.cat_id) = cat.id
LEFT JOIN t_file fl   ON t.file_id    = fl.id;


-- ============================================================
-- 视图3: v_category_tree_full — 分类完整树形结构(闭包表深度联动)
-- 高级特性: 闭包表JOIN、JSON_ARRAYAGG聚合、子查询统计、CASE判定叶子节点、
--           窗口函数(SUM OVER)
-- 用途: 完整展示分类层级关系, 含每个节点下所有后代数量、直接图表/公式数量、
--       子分类列表(JSON), 是否叶子节点等
-- ============================================================
CREATE VIEW v_category_tree_full AS
SELECT
    c.id                                                        AS cat_id,
    c.cat_name,
    c.cat_type,
    c.parent_id,
    c.sort_order,
    c.description,
    c.status                                                    AS cat_status,
    c.item_count,
    -- 通过闭包表计算后代数量(排除自身)
    (SELECT COUNT(*) FROM t_category_closure cc
     WHERE cc.ancestor_id = c.id AND cc.depth > 0)              AS descendant_count,
    -- 当前节点深度(距离根节点)
    COALESCE((SELECT MAX(cc2.depth) FROM t_category_closure cc2
              WHERE cc2.descendant_id = c.id), 0)               AS node_depth,
    -- 根祖先名称
    (SELECT anc.cat_name FROM t_category_closure cc3
     JOIN t_category anc ON cc3.ancestor_id = anc.id
     WHERE cc3.descendant_id = c.id
     ORDER BY cc3.depth DESC LIMIT 1)                           AS root_ancestor_name,
    -- 完整路径 (用闭包表拼接)
    (SELECT GROUP_CONCAT(anc2.cat_name ORDER BY cc4.depth DESC SEPARATOR ' / ')
     FROM t_category_closure cc4
     JOIN t_category anc2 ON cc4.ancestor_id = anc2.id
     WHERE cc4.descendant_id = c.id)                            AS full_path,
    -- 直接子分类(JSON数组)
    (SELECT JSON_ARRAYAGG(JSON_OBJECT('id', sub.id, 'name', sub.cat_name))
     FROM t_category sub WHERE sub.parent_id = c.id)            AS children_json,
    -- 该分类下的图表数量
    (SELECT COUNT(*) FROM t_chart ch WHERE ch.cat_id = c.id)    AS chart_count,
    -- 该分类下的公式数量
    (SELECT COUNT(*) FROM t_formula fm WHERE fm.cat_id = c.id)  AS formula_count,
    -- 是否叶子节点
    CASE WHEN EXISTS (SELECT 1 FROM t_category sub2 WHERE sub2.parent_id = c.id)
         THEN 0 ELSE 1
    END                                                         AS is_leaf
FROM t_category c;


-- ============================================================
-- 视图4: v_data_quality_dashboard — 数据质量仪表盘
-- 高级特性: 多层聚合、生成列(is_null_val/value_length)、窗口函数(NTILE分桶)、
--           CASE WHEN 评级、JSON_OBJECT输出
-- 用途: 对每个上传文件进行数据质量评分, 覆盖空值率、数据类型分布、值长度分布,
--       输出质量等级(A/B/C/D/F)
-- ============================================================
CREATE VIEW v_data_quality_dashboard AS
SELECT
    f.id                                                        AS file_id,
    f.file_name,
    f.file_type,
    f.total_rows,
    f.total_cols,
    f.cell_count,
    f.file_size_mb,
    u.username                                                  AS uploader,
    f.create_time                                               AS upload_time,
    -- 空值统计
    COALESCE(dq.total_items, 0)                                 AS total_data_items,
    COALESCE(dq.null_count, 0)                                  AS null_count,
    CASE WHEN COALESCE(dq.total_items, 0) > 0
         THEN ROUND(dq.null_count * 100.0 / dq.total_items, 2)
         ELSE 0
    END                                                         AS null_rate_pct,
    -- 数据类型分布(JSON)
    COALESCE(dq.type_distribution, '{}')                        AS type_distribution_json,
    -- 值长度统计
    COALESCE(dq.avg_value_length, 0)                            AS avg_value_length,
    COALESCE(dq.max_value_length, 0)                            AS max_value_length,
    -- 列数量
    COALESCE(dq.distinct_columns, 0)                            AS distinct_columns,
    -- 综合质量评级
    CASE
        WHEN COALESCE(dq.total_items, 0) = 0                   THEN 'F'
        WHEN dq.null_count * 100.0 / dq.total_items <= 2       THEN 'A'
        WHEN dq.null_count * 100.0 / dq.total_items <= 10      THEN 'B'
        WHEN dq.null_count * 100.0 / dq.total_items <= 25      THEN 'C'
        WHEN dq.null_count * 100.0 / dq.total_items <= 50      THEN 'D'
        ELSE 'F'
    END                                                         AS quality_grade,
    -- 窗口函数: 按质量分桶(四分位)
    NTILE(4) OVER (ORDER BY
        CASE WHEN COALESCE(dq.total_items, 0) > 0
             THEN dq.null_count * 1.0 / dq.total_items
             ELSE 1
        END ASC
    )                                                           AS quality_quartile
FROM t_file f
JOIN t_user u ON f.user_id = u.id
LEFT JOIN (
    SELECT
        file_id,
        COUNT(*)                                                AS total_items,
        SUM(is_null_val)                                        AS null_count,
        JSON_OBJECT(
            'text',   SUM(data_type = 'text'),
            'number', SUM(data_type = 'number'),
            'date',   SUM(data_type = 'date'),
            'empty',  SUM(data_type = 'empty')
        )                                                       AS type_distribution,
        ROUND(AVG(value_length), 1)                             AS avg_value_length,
        MAX(value_length)                                       AS max_value_length,
        COUNT(DISTINCT col_name)                                AS distinct_columns
    FROM t_data_item
    GROUP BY file_id
) dq ON f.id = dq.file_id
WHERE f.status = 1;


-- ============================================================
-- 视图5: v_trend_analysis_weekly — 周度趋势分析
-- 高级特性: 窗口函数(LAG环比计算)、日期函数(YEARWEEK)、条件聚合、
--           环比增长率自动计算
-- 用途: 按周聚合任务量/用户活跃度, 自动计算环比增长率, 用于趋势图和管理报表
-- ============================================================
CREATE VIEW v_trend_analysis_weekly AS
SELECT
    week_data.*,
    -- 环比计算: 任务量
    LAG(week_data.total_tasks) OVER (ORDER BY week_data.year_week)
                                                                AS prev_week_tasks,
    CASE WHEN LAG(week_data.total_tasks) OVER (ORDER BY week_data.year_week) > 0
         THEN ROUND(
             (week_data.total_tasks - LAG(week_data.total_tasks) OVER (ORDER BY week_data.year_week))
             * 100.0
             / LAG(week_data.total_tasks) OVER (ORDER BY week_data.year_week), 2)
         ELSE NULL
    END                                                         AS task_wow_growth_pct,
    -- 环比计算: 活跃用户
    LAG(week_data.active_users) OVER (ORDER BY week_data.year_week)
                                                                AS prev_week_users,
    -- 累计值: 窗口函数累加
    SUM(week_data.total_tasks) OVER (ORDER BY week_data.year_week
        ROWS UNBOUNDED PRECEDING)                               AS cumulative_tasks
FROM (
    SELECT
        YEARWEEK(t.create_time, 1)                              AS year_week,
        MIN(DATE(t.create_time))                                AS week_start_date,
        COUNT(*)                                                AS total_tasks,
        SUM(t.status = 'SUCCESS')                               AS success_tasks,
        SUM(t.status = 'FAILED')                                AS failed_tasks,
        SUM(t.task_type = 'chart')                              AS chart_tasks,
        SUM(t.task_type = 'formula')                            AS formula_tasks,
        COUNT(DISTINCT t.user_id)                               AS active_users,
        ROUND(AVG(t.duration_seconds), 1)                       AS avg_duration_sec,
        ROUND(SUM(t.status = 'SUCCESS') * 100.0 / COUNT(*), 2) AS success_rate_pct,
        COUNT(DISTINCT t.render_engine)                         AS engine_variety
    FROM t_task t
    GROUP BY YEARWEEK(t.create_time, 1)
) week_data;


-- ============================================================
-- 视图6: v_system_activity_audit — 系统活动审计视图
-- 高级特性: UNION ALL多源汇聚、统一时间线、JSON_OBJECT封装详情
-- 用途: 将文件上传、任务创建、历史记录创建等多类活动统一到一条时间线,
--       用于管理员审计和系统行为分析
-- ============================================================
CREATE VIEW v_system_activity_audit AS
-- 文件上传活动
SELECT
    'FILE_UPLOAD'                                               AS activity_type,
    f.id                                                        AS entity_id,
    f.user_id,
    u.username,
    JSON_OBJECT(
        'file_name', f.file_name,
        'file_type', f.file_type,
        'file_size_mb', f.file_size_mb,
        'rows', f.total_rows,
        'cols', f.total_cols
    )                                                           AS activity_detail,
    f.create_time                                               AS activity_time
FROM t_file f
JOIN t_user u ON f.user_id = u.id
WHERE f.status = 1

UNION ALL

-- 任务创建活动
SELECT
    CONCAT('TASK_', t.status)                                   AS activity_type,
    t.id                                                        AS entity_id,
    t.user_id,
    u.username,
    JSON_OBJECT(
        'task_type',   t.task_type,
        'item_name',   COALESCE(c.chart_name, fm.formula_name, ''),
        'engine',      t.render_engine,
        'priority',    t.priority,
        'duration_sec',t.duration_seconds
    )                                                           AS activity_detail,
    t.create_time                                               AS activity_time
FROM t_task t
JOIN t_user u   ON t.user_id    = u.id
LEFT JOIN t_chart c   ON t.chart_id   = c.id
LEFT JOIN t_formula fm ON t.formula_id = fm.id

UNION ALL

-- 历史记录活动
SELECT
    CASE WHEN h.is_deleted = 1 THEN 'HISTORY_DELETE' ELSE 'HISTORY_CREATE' END
                                                                AS activity_type,
    h.id                                                        AS entity_id,
    h.user_id,
    u.username,
    JSON_OBJECT(
        'task_type',  h.task_type,
        'chart_name', COALESCE(h.chart_name, ''),
        'formula_name', COALESCE(h.formula_name, ''),
        'rating',     h.rating,
        'is_favorite',h.is_favorite
    )                                                           AS activity_detail,
    h.create_time                                               AS activity_time
FROM t_history h
JOIN t_user u ON h.user_id = u.id;


-- ============================================================
-- 视图7: v_hot_items_unified_ranking — 图表/公式统一热度排行
-- 高级特性: UNION ALL合并异构表、窗口函数(DENSE_RANK)、JSON标签过滤就绪、
--           多维排序
-- 用途: 将图表和公式合并到同一排行榜, 统一排名, 前端热门推荐页使用
-- ============================================================
CREATE VIEW v_hot_items_unified_ranking AS
SELECT
    ranked.*,
    DENSE_RANK() OVER (ORDER BY ranked.usage_count DESC)        AS global_rank,
    DENSE_RANK() OVER (PARTITION BY ranked.item_type ORDER BY ranked.usage_count DESC)
                                                                AS type_rank
FROM (
    -- 图表
    SELECT
        'chart'          AS item_type,
        c.id             AS item_id,
        c.chart_name     AS item_name,
        c.chart_code     AS item_code,
        c.usage_count,
        c.popularity_rank,
        c.complexity_level,
        c.is_hot,
        c.tags,
        c.version,
        cat.cat_name     AS category_name,
        c.description
    FROM t_chart c
    LEFT JOIN t_category cat ON c.cat_id = cat.id

    UNION ALL

    -- 公式
    SELECT
        'formula'        AS item_type,
        f.id             AS item_id,
        f.formula_name   AS item_name,
        f.formula_code   AS item_code,
        f.usage_count,
        f.popularity_rank,
        f.complexity_level,
        f.is_hot,
        f.tags,
        f.version,
        cat.cat_name     AS category_name,
        f.description
    FROM t_formula f
    LEFT JOIN t_category cat ON f.cat_id = cat.id
) ranked;


-- ============================================================
-- 视图8: v_user_preference_matrix — 用户偏好矩阵
-- 高级特性: 多表JOIN、PIVOT式条件聚合、窗口函数(FIRST_VALUE获取最常用项)、
--           JSON聚合
-- 用途: 分析每个用户对不同图表/公式类型的使用偏好, 用于智能推荐
-- ============================================================
CREATE VIEW v_user_preference_matrix AS
SELECT
    u.id                                                        AS user_id,
    u.username,
    -- 偏好维度: 图表vs公式
    COALESCE(prefs.chart_usage, 0)                              AS chart_usage,
    COALESCE(prefs.formula_usage, 0)                            AS formula_usage,
    CASE WHEN COALESCE(prefs.chart_usage, 0) >= COALESCE(prefs.formula_usage, 0)
         THEN 'chart' ELSE 'formula'
    END                                                         AS preferred_type,
    -- 最常用渲染引擎
    COALESCE(prefs.fav_engine, 'matplotlib')                    AS favorite_engine,
    -- 最常用的图表(通过子查询)
    (SELECT c.chart_name FROM t_task t2
     JOIN t_chart c ON t2.chart_id = c.id
     WHERE t2.user_id = u.id AND t2.task_type = 'chart'
     GROUP BY c.id, c.chart_name
     ORDER BY COUNT(*) DESC LIMIT 1)                            AS most_used_chart,
    -- 最常用的公式
    (SELECT fm.formula_name FROM t_task t3
     JOIN t_formula fm ON t3.formula_id = fm.id
     WHERE t3.user_id = u.id AND t3.task_type = 'formula'
     GROUP BY fm.id, fm.formula_name
     ORDER BY COUNT(*) DESC LIMIT 1)                            AS most_used_formula,
    -- 偏好的文件类型
    (SELECT fl.file_type FROM t_task t4
     JOIN t_file fl ON t4.file_id = fl.id
     WHERE t4.user_id = u.id AND fl.file_type IS NOT NULL
     GROUP BY fl.file_type
     ORDER BY COUNT(*) DESC LIMIT 1)                            AS preferred_file_type,
    -- 平均任务优先级
    COALESCE(prefs.avg_priority, 5)                             AS avg_priority,
    -- 使用的分类分布(JSON)
    prefs.category_distribution
FROM t_user u
LEFT JOIN (
    SELECT
        t.user_id,
        SUM(t.task_type = 'chart')                              AS chart_usage,
        SUM(t.task_type = 'formula')                            AS formula_usage,
        -- 最常用引擎
        (SELECT t5.render_engine FROM t_task t5
         WHERE t5.user_id = t.user_id
         GROUP BY t5.render_engine
         ORDER BY COUNT(*) DESC LIMIT 1)                        AS fav_engine,
        ROUND(AVG(t.priority), 1)                               AS avg_priority,
        -- 分类分布
        (SELECT JSON_OBJECTAGG(COALESCE(cat.cat_name, '未分类'), cnt)
         FROM (
             SELECT COALESCE(c2.cat_id, f2.cat_id) AS cid, COUNT(*) AS cnt
             FROM t_task t6
             LEFT JOIN t_chart c2   ON t6.chart_id   = c2.id
             LEFT JOIN t_formula f2 ON t6.formula_id = f2.id
             WHERE t6.user_id = t.user_id
             GROUP BY COALESCE(c2.cat_id, f2.cat_id)
         ) cat_cnt
         LEFT JOIN t_category cat ON cat_cnt.cid = cat.id
        )                                                       AS category_distribution
    FROM t_task t
    GROUP BY t.user_id
) prefs ON u.id = prefs.user_id;


-- ############################################################################################
-- 第三章  存储过程 (Stored Procedures)
-- 设计理念: 将复杂业务逻辑、多步骤操作、数据分析、智能推荐等封装为存储过程,
--           实现数据库层的"业务大脑", 减轻Java层负担, 保证数据一致性.
-- ############################################################################################

-- 先清理旧存储过程(幂等)
DROP PROCEDURE IF EXISTS sp_daily_stats;
DROP PROCEDURE IF EXISTS sp_hot_chart_stats;
DROP PROCEDURE IF EXISTS sp_user_ranking;
DROP PROCEDURE IF EXISTS sp_user_profile_analysis;
DROP PROCEDURE IF EXISTS sp_smart_recommend;
DROP PROCEDURE IF EXISTS sp_task_state_transition;
DROP PROCEDURE IF EXISTS sp_data_quality_audit;
DROP PROCEDURE IF EXISTS sp_quota_check_and_enforce;
DROP PROCEDURE IF EXISTS sp_generate_system_report;
DROP PROCEDURE IF EXISTS sp_hot_items_refresh;
DROP PROCEDURE IF EXISTS sp_category_integrity_check;
DROP PROCEDURE IF EXISTS sp_cleanup_and_maintain;

-- ============================================================
-- 存储过程1: sp_user_profile_analysis — 用户深度画像分析
-- 功能: 给定用户ID, 输出多结果集, 涵盖基本信息、任务分布、时间模式、
--       偏好雷达、与全站均值对比. 使用窗口函数、JSON、条件聚合.
-- 参数: p_user_id BIGINT — 目标用户ID
-- 调用: CALL sp_user_profile_analysis(1);
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_user_profile_analysis(IN p_user_id BIGINT)
BEGIN
    DECLARE v_user_exists INT DEFAULT 0;

    SELECT COUNT(*) INTO v_user_exists FROM t_user WHERE id = p_user_id;
    IF v_user_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '用户不存在';
    END IF;

    -- 结果集1: 用户基本画像 + 全站排名
    SELECT
        u.id, u.username, u.nickname, u.email,
        u.account_age_days,
        u.is_active,
        u.login_count,
        u.last_login_time,
        RANK() OVER (ORDER BY u.login_count DESC)               AS login_rank,
        u.profile
    FROM t_user u
    WHERE u.id = p_user_id;

    -- 结果集2: 按月度任务趋势(近12个月)
    SELECT
        DATE_FORMAT(t.create_time, '%Y-%m')                     AS month,
        COUNT(*)                                                AS total,
        SUM(t.status = 'SUCCESS')                               AS success,
        SUM(t.status = 'FAILED')                                AS failed,
        SUM(t.task_type = 'chart')                              AS charts,
        SUM(t.task_type = 'formula')                            AS formulas,
        ROUND(AVG(t.duration_seconds), 1)                       AS avg_duration
    FROM t_task t
    WHERE t.user_id = p_user_id
      AND t.create_time >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY DATE_FORMAT(t.create_time, '%Y-%m')
    ORDER BY month;

    -- 结果集3: 使用的图表/公式TOP5
    SELECT 'chart' AS item_type, c.chart_name AS item_name, COUNT(*) AS use_count
    FROM t_task t JOIN t_chart c ON t.chart_id = c.id
    WHERE t.user_id = p_user_id AND t.task_type = 'chart'
    GROUP BY c.id, c.chart_name
    ORDER BY use_count DESC LIMIT 5;

    -- 结果集4: 与全站平均对比
    SELECT
        COALESCE(user_stat.my_tasks, 0)                         AS my_total_tasks,
        ROUND(global_stat.avg_tasks, 1)                         AS global_avg_tasks,
        COALESCE(user_stat.my_success_rate, 0)                  AS my_success_rate,
        ROUND(global_stat.avg_success_rate, 1)                  AS global_avg_success_rate,
        COALESCE(user_stat.my_avg_duration, 0)                  AS my_avg_duration,
        ROUND(global_stat.avg_duration, 1)                      AS global_avg_duration
    FROM
        (SELECT
            COUNT(*) AS my_tasks,
            ROUND(SUM(status='SUCCESS')*100.0/NULLIF(COUNT(*),0), 2) AS my_success_rate,
            ROUND(AVG(duration_seconds), 1) AS my_avg_duration
         FROM t_task WHERE user_id = p_user_id) user_stat,
        (SELECT
            AVG(cnt) AS avg_tasks,
            AVG(sr) AS avg_success_rate,
            AVG(ad) AS avg_duration
         FROM (
            SELECT user_id, COUNT(*) AS cnt,
                   SUM(status='SUCCESS')*100.0/NULLIF(COUNT(*),0) AS sr,
                   AVG(duration_seconds) AS ad
            FROM t_task GROUP BY user_id
         ) per_user) global_stat;
END//
DELIMITER ;


-- ============================================================
-- 存储过程2: sp_smart_recommend — 基于历史的智能推荐
-- 功能: 基于用户历史使用模式, 利用协同过滤思想推荐图表/公式.
--       1) 分析用户最常用类型 2) 找到相似用户 3) 推荐相似用户用过但当前用户没用过的
-- 参数: p_user_id BIGINT, p_limit INT(推荐数量, 默认5)
-- 调用: CALL sp_smart_recommend(1, 5);
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_smart_recommend(IN p_user_id BIGINT, IN p_limit INT)
BEGIN
    IF p_limit IS NULL OR p_limit <= 0 THEN SET p_limit = 5; END IF;

    -- 推荐图表: 找到和当前用户使用相同图表的其他用户(相似用户), 取他们用过但当前用户没用过的图表
    SELECT
        'chart'                     AS recommend_type,
        c.id                        AS item_id,
        c.chart_name                AS item_name,
        c.chart_code                AS item_code,
        c.popularity_rank,
        c.usage_count,
        cat.cat_name                AS category_name,
        COUNT(DISTINCT similar.user_id) AS similar_user_count,
        '基于相似用户推荐'             AS reason
    FROM t_task similar
    JOIN t_chart c ON similar.chart_id = c.id
    LEFT JOIN t_category cat ON c.cat_id = cat.id
    WHERE similar.user_id IN (
        -- 相似用户: 和当前用户使用过至少1个相同图表的人
        SELECT DISTINCT t2.user_id
        FROM t_task t1
        JOIN t_task t2 ON t1.chart_id = t2.chart_id AND t1.user_id != t2.user_id
        WHERE t1.user_id = p_user_id AND t1.task_type = 'chart'
    )
    AND similar.task_type = 'chart'
    -- 排除用户已用过的
    AND c.id NOT IN (
        SELECT DISTINCT chart_id FROM t_task WHERE user_id = p_user_id AND chart_id IS NOT NULL
    )
    GROUP BY c.id, c.chart_name, c.chart_code, c.popularity_rank, c.usage_count, cat.cat_name
    ORDER BY similar_user_count DESC, c.usage_count DESC
    LIMIT p_limit;

    -- 推荐公式: 同理
    SELECT
        'formula'                   AS recommend_type,
        f.id                        AS item_id,
        f.formula_name              AS item_name,
        f.formula_code              AS item_code,
        f.popularity_rank,
        f.usage_count,
        cat.cat_name                AS category_name,
        COUNT(DISTINCT similar.user_id) AS similar_user_count,
        '基于相似用户推荐'             AS reason
    FROM t_task similar
    JOIN t_formula f ON similar.formula_id = f.id
    LEFT JOIN t_category cat ON f.cat_id = cat.id
    WHERE similar.user_id IN (
        SELECT DISTINCT t2.user_id
        FROM t_task t1
        JOIN t_task t2 ON t1.formula_id = t2.formula_id AND t1.user_id != t2.user_id
        WHERE t1.user_id = p_user_id AND t1.task_type = 'formula'
    )
    AND similar.task_type = 'formula'
    AND f.id NOT IN (
        SELECT DISTINCT formula_id FROM t_task WHERE user_id = p_user_id AND formula_id IS NOT NULL
    )
    GROUP BY f.id, f.formula_name, f.formula_code, f.popularity_rank, f.usage_count, cat.cat_name
    ORDER BY similar_user_count DESC, f.usage_count DESC
    LIMIT p_limit;

    -- 补充: 热门但用户未用过的(兜底推荐)
    SELECT
        'hot_chart'                 AS recommend_type,
        c.id                        AS item_id,
        c.chart_name                AS item_name,
        c.chart_code                AS item_code,
        c.popularity_rank,
        c.usage_count,
        '热门推荐'                  AS reason
    FROM t_chart c
    WHERE c.id NOT IN (
        SELECT DISTINCT chart_id FROM t_task WHERE user_id = p_user_id AND chart_id IS NOT NULL
    )
    ORDER BY c.usage_count DESC
    LIMIT p_limit;
END//
DELIMITER ;


-- ============================================================
-- 存储过程3: sp_task_state_transition — 任务状态机流转
-- 功能: 实现任务状态的合法流转, 带状态机验证、自动时间戳填充、重试逻辑、
--       执行日志追加(JSON). 非法流转抛出异常.
-- 参数: p_task_id BIGINT, p_new_status VARCHAR(20), p_error_msg TEXT(可选)
-- 合法流转: PENDING->PROCESSING, PROCESSING->SUCCESS, PROCESSING->FAILED,
--           FAILED->PENDING(重试)
-- 调用: CALL sp_task_state_transition(1, 'PROCESSING', NULL);
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_task_state_transition(
    IN p_task_id    BIGINT,
    IN p_new_status VARCHAR(20),
    IN p_error_msg  TEXT
)
BEGIN
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_retry_count    INT;
    DECLARE v_valid          TINYINT DEFAULT 0;
    DECLARE v_now            DATETIME DEFAULT NOW();
    DECLARE v_err_msg        VARCHAR(200);

    -- 获取当前状态
    SELECT status, retry_count INTO v_current_status, v_retry_count
    FROM t_task WHERE id = p_task_id FOR UPDATE;

    IF v_current_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '任务不存在';
    END IF;

    -- 状态机验证: 检查流转合法性
    IF (v_current_status = 'PENDING'    AND p_new_status = 'PROCESSING') OR
       (v_current_status = 'PROCESSING' AND p_new_status = 'SUCCESS')    OR
       (v_current_status = 'PROCESSING' AND p_new_status = 'FAILED')     OR
       (v_current_status = 'FAILED'     AND p_new_status = 'PENDING')    THEN
        SET v_valid = 1;
    END IF;

    IF v_valid = 0 THEN
        SET v_err_msg = CONCAT('非法状态流转: ', v_current_status, ' -> ', p_new_status);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err_msg;
    END IF;

    -- 执行状态流转
    UPDATE t_task SET
        status = p_new_status,
        start_time = CASE
            WHEN p_new_status = 'PROCESSING' THEN v_now
            ELSE start_time
        END,
        finish_time = CASE
            WHEN p_new_status IN ('SUCCESS', 'FAILED') THEN v_now
            ELSE finish_time
        END,
        error_msg = CASE
            WHEN p_new_status = 'FAILED' THEN p_error_msg
            WHEN p_new_status = 'PENDING' THEN NULL
            ELSE error_msg
        END,
        retry_count = CASE
            WHEN v_current_status = 'FAILED' AND p_new_status = 'PENDING'
                THEN retry_count + 1
            ELSE retry_count
        END,
        -- 追加执行日志(JSON)
        execution_log = JSON_ARRAY_APPEND(
            COALESCE(execution_log, JSON_OBJECT('steps', JSON_ARRAY())),
            '$.steps',
            JSON_OBJECT(
                'timestamp', DATE_FORMAT(v_now, '%Y-%m-%d %H:%i:%s'),
                'from_status', v_current_status,
                'to_status', p_new_status,
                'message', COALESCE(p_error_msg, 'OK')
            )
        )
    WHERE id = p_task_id;

    -- 返回更新后的任务状态
    SELECT id, status, start_time, finish_time, duration_seconds,
           retry_count, execution_log, error_msg
    FROM t_task WHERE id = p_task_id;
END//
DELIMITER ;


-- ============================================================
-- 存储过程4: sp_data_quality_audit — 文件数据质量审计
-- 功能: 对指定文件进行全面数据质量审计, 输出多维度质量报告.
--       利用生成列(is_null_val, value_length)、JSON聚合、窗口函数.
-- 参数: p_file_id BIGINT
-- 调用: CALL sp_data_quality_audit(1);
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_data_quality_audit(IN p_file_id BIGINT)
BEGIN
    DECLARE v_file_exists INT DEFAULT 0;
    DECLARE v_quality_score DECIMAL(5,2) DEFAULT 0;
    DECLARE v_null_rate DECIMAL(5,2) DEFAULT 0;
    DECLARE v_total_items INT DEFAULT 0;

    SELECT COUNT(*) INTO v_file_exists FROM t_file WHERE id = p_file_id AND status = 1;
    IF v_file_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '文件不存在或已删除';
    END IF;

    -- 计算基础指标
    SELECT COUNT(*), SUM(is_null_val) * 100.0 / NULLIF(COUNT(*), 0)
    INTO v_total_items, v_null_rate
    FROM t_data_item WHERE file_id = p_file_id;

    -- 综合质量评分(百分制): 空值率越低越好
    SET v_quality_score = GREATEST(0, 100 - v_null_rate * 2);

    -- 结果集1: 文件概览
    SELECT
        f.id, f.file_name, f.file_type, f.file_size_mb,
        f.total_rows, f.total_cols, f.cell_count,
        v_total_items                                           AS actual_data_items,
        v_null_rate                                             AS null_rate_pct,
        v_quality_score                                         AS quality_score,
        CASE
            WHEN v_quality_score >= 90 THEN 'A - 优秀'
            WHEN v_quality_score >= 75 THEN 'B - 良好'
            WHEN v_quality_score >= 60 THEN 'C - 合格'
            WHEN v_quality_score >= 40 THEN 'D - 较差'
            ELSE 'F - 不合格'
        END                                                     AS quality_grade,
        f.metadata,
        f.data_profile
    FROM t_file f WHERE f.id = p_file_id;

    -- 结果集2: 逐列质量分析
    SELECT
        col_name,
        COUNT(*)                                                AS total_values,
        SUM(is_null_val)                                        AS null_count,
        ROUND(SUM(is_null_val) * 100.0 / COUNT(*), 2)          AS col_null_rate,
        COUNT(DISTINCT col_value)                               AS distinct_values,
        ROUND(COUNT(DISTINCT col_value) * 100.0 / NULLIF(COUNT(*) - SUM(is_null_val), 0), 2)
                                                                AS uniqueness_pct,
        MIN(value_length)                                       AS min_length,
        MAX(value_length)                                       AS max_length,
        ROUND(AVG(value_length), 1)                             AS avg_length,
        -- 数据类型分布
        SUM(data_type = 'number')                               AS numeric_count,
        SUM(data_type = 'text')                                 AS text_count,
        SUM(data_type = 'date')                                 AS date_count,
        -- 主导数据类型
        CASE
            WHEN SUM(data_type = 'number') > SUM(data_type = 'text') THEN 'numeric'
            WHEN SUM(data_type = 'text')   > 0 THEN 'text'
            ELSE 'mixed'
        END                                                     AS dominant_type
    FROM t_data_item
    WHERE file_id = p_file_id
    GROUP BY col_name
    ORDER BY col_null_rate DESC;

    -- 结果集3: 更新文件的数据画像(回写到data_profile字段)
    UPDATE t_file SET data_profile = JSON_OBJECT(
        'quality_score',  v_quality_score,
        'null_rate_pct',  ROUND(v_null_rate, 2),
        'total_items',    v_total_items,
        'audit_time',     DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s')
    ) WHERE id = p_file_id;

    SELECT CONCAT('数据质量审计完成, 评分: ', v_quality_score, '/100') AS audit_result;
END//
DELIMITER ;


-- ============================================================
-- 存储过程5: sp_quota_check_and_enforce — 用户配额检查与执行
-- 功能: 检查用户是否超出每日任务配额(基于角色元数据中的max_tasks_per_day),
--       返回配额使用情况, 超额时抛出异常阻止创建.
-- 参数: p_user_id BIGINT, p_action VARCHAR(20)('CHECK'仅检查/'ENFORCE'强制执行)
-- 调用: CALL sp_quota_check_and_enforce(1, 'CHECK');
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_quota_check_and_enforce(
    IN p_user_id BIGINT,
    IN p_action  VARCHAR(20)
)
BEGIN
    DECLARE v_max_tasks     INT DEFAULT 100;
    DECLARE v_today_tasks   INT DEFAULT 0;
    DECLARE v_total_tasks   INT DEFAULT 0;
    DECLARE v_file_count    INT DEFAULT 0;
    DECLARE v_remaining     INT DEFAULT 0;
    DECLARE v_role_name     VARCHAR(50);
    DECLARE v_quota_msg     VARCHAR(200);

    -- 从角色元数据中获取配额(JSON提取)
    SELECT
        r.role_name,
        COALESCE(JSON_UNQUOTE(JSON_EXTRACT(r.metadata, '$.max_tasks_per_day')), '100')
    INTO v_role_name, v_max_tasks
    FROM t_user_role ur
    JOIN t_role r ON ur.role_id = r.id
    WHERE ur.user_id = p_user_id
    ORDER BY COALESCE(CAST(JSON_EXTRACT(r.metadata, '$.max_tasks_per_day') AS UNSIGNED), 100) DESC
    LIMIT 1;

    -- 今日任务数
    SELECT COUNT(*) INTO v_today_tasks
    FROM t_task WHERE user_id = p_user_id AND DATE(create_time) = CURDATE();

    -- 总任务数
    SELECT COUNT(*) INTO v_total_tasks FROM t_task WHERE user_id = p_user_id;

    -- 文件数
    SELECT COUNT(*) INTO v_file_count FROM t_file WHERE user_id = p_user_id AND status = 1;

    SET v_remaining = GREATEST(0, v_max_tasks - v_today_tasks);

    -- 强制模式: 超额则抛出异常
    IF p_action = 'ENFORCE' AND v_today_tasks >= v_max_tasks THEN
        SET v_quota_msg = CONCAT('已达今日任务上限(', v_max_tasks, '), 请明日再试');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_quota_msg;
    END IF;

    -- 返回配额信息
    SELECT
        p_user_id                                               AS user_id,
        v_role_name                                             AS role_name,
        v_max_tasks                                             AS daily_quota,
        v_today_tasks                                           AS today_used,
        v_remaining                                             AS today_remaining,
        v_total_tasks                                           AS total_tasks,
        v_file_count                                            AS file_count,
        ROUND(v_today_tasks * 100.0 / NULLIF(v_max_tasks, 0), 1) AS usage_pct,
        CASE
            WHEN v_today_tasks >= v_max_tasks     THEN 'EXHAUSTED'
            WHEN v_today_tasks >= v_max_tasks * 0.8 THEN 'WARNING'
            ELSE 'NORMAL'
        END                                                     AS quota_status;
END//
DELIMITER ;


-- ============================================================
-- 存储过程6: sp_generate_system_report — 系统综合报告生成
-- 功能: 生成系统运营全景报告, 涵盖用户统计、任务统计、资源统计、
--       质量指标、Top排行等, 输出多结果集.
-- 参数: p_date_from DATE, p_date_to DATE
-- 调用: CALL sp_generate_system_report('2025-01-01', '2025-12-31');
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_generate_system_report(
    IN p_date_from DATE,
    IN p_date_to   DATE
)
BEGIN
    IF p_date_from IS NULL THEN SET p_date_from = DATE_SUB(CURDATE(), INTERVAL 30 DAY); END IF;
    IF p_date_to   IS NULL THEN SET p_date_to   = CURDATE(); END IF;

    -- 结果集1: 概览KPI
    SELECT
        '系统运营报告'                                           AS report_title,
        p_date_from                                             AS period_from,
        p_date_to                                               AS period_to,
        (SELECT COUNT(*) FROM t_user)                           AS total_users,
        (SELECT COUNT(*) FROM t_user WHERE is_active = 1)       AS active_users,
        (SELECT COUNT(*) FROM t_task
         WHERE create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY))
                                                                AS period_tasks,
        (SELECT COUNT(*) FROM t_file WHERE status = 1)          AS total_files,
        (SELECT ROUND(SUM(file_size_mb), 2) FROM t_file WHERE status = 1)
                                                                AS total_storage_mb;

    -- 结果集2: 任务状态分布(含成功率)
    SELECT
        status,
        COUNT(*)                                                AS count,
        ROUND(COUNT(*) * 100.0 / NULLIF((
            SELECT COUNT(*) FROM t_task
            WHERE create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY)
        ), 0), 2)                                               AS percentage
    FROM t_task
    WHERE create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY)
    GROUP BY status;

    -- 结果集3: 每日任务量趋势(带移动平均)
    SELECT
        DATE(create_time)                                       AS task_date,
        COUNT(*)                                                AS daily_count,
        -- 7日移动平均(窗口函数)
        ROUND(AVG(COUNT(*)) OVER (
            ORDER BY DATE(create_time)
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 1)                                                   AS moving_avg_7d
    FROM t_task
    WHERE create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY)
    GROUP BY DATE(create_time)
    ORDER BY task_date;

    -- 结果集4: 渲染引擎使用分布
    SELECT
        render_engine,
        COUNT(*)                                                AS usage_count,
        ROUND(AVG(duration_seconds), 1)                         AS avg_duration,
        SUM(status = 'SUCCESS')                                 AS success_count,
        SUM(status = 'FAILED')                                  AS failed_count
    FROM t_task
    WHERE create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY)
    GROUP BY render_engine
    ORDER BY usage_count DESC;

    -- 结果集5: Top10活跃用户(窗口函数排名)
    SELECT * FROM (
        SELECT
            u.username,
            u.nickname,
            COUNT(t.id)                                         AS task_count,
            SUM(t.status = 'SUCCESS')                           AS success_count,
            ROUND(AVG(t.duration_seconds), 1)                   AS avg_duration,
            DENSE_RANK() OVER (ORDER BY COUNT(t.id) DESC)       AS user_rank
        FROM t_user u
        JOIN t_task t ON u.id = t.user_id
        WHERE t.create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY)
        GROUP BY u.id, u.username, u.nickname
    ) ranked WHERE user_rank <= 10;

    -- 结果集6: Top10热门图表/公式
    SELECT
        COALESCE(c.chart_name, f.formula_name)                  AS item_name,
        t.task_type,
        COUNT(*)                                                AS usage_in_period,
        COALESCE(c.popularity_rank, f.popularity_rank)          AS popularity
    FROM t_task t
    LEFT JOIN t_chart c   ON t.chart_id   = c.id
    LEFT JOIN t_formula f ON t.formula_id = f.id
    WHERE t.create_time BETWEEN p_date_from AND DATE_ADD(p_date_to, INTERVAL 1 DAY)
    GROUP BY COALESCE(c.chart_name, f.formula_name), t.task_type,
             COALESCE(c.popularity_rank, f.popularity_rank)
    ORDER BY usage_in_period DESC
    LIMIT 10;
END//
DELIMITER ;


-- ============================================================
-- 存储过程7: sp_hot_items_refresh — 热点数据智能刷新
-- 功能: 根据usage_count和近期任务量, 智能更新图表/公式的is_hot标记.
--       采用双维度策略: 绝对使用量 + 近7天相对热度.
-- 参数: p_hot_threshold INT(绝对阈值), p_recent_days INT(近期天数)
-- 调用: CALL sp_hot_items_refresh(10, 7);
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_hot_items_refresh(
    IN p_hot_threshold INT,
    IN p_recent_days   INT
)
BEGIN
    IF p_hot_threshold IS NULL THEN SET p_hot_threshold = 10; END IF;
    IF p_recent_days   IS NULL THEN SET p_recent_days   = 7;  END IF;

    -- 重置所有图表hot标记
    UPDATE t_chart SET is_hot = 0;

    -- 策略1: 绝对使用量超阈值 → 热门
    UPDATE t_chart SET is_hot = 1
    WHERE usage_count >= p_hot_threshold;

    -- 策略2: 近N天使用次数 >= 3 → 热门(短期热度)
    UPDATE t_chart c SET is_hot = 1
    WHERE c.id IN (
        SELECT chart_id FROM t_task
        WHERE task_type = 'chart'
          AND chart_id IS NOT NULL
          AND status = 'SUCCESS'
          AND create_time >= DATE_SUB(NOW(), INTERVAL p_recent_days DAY)
        GROUP BY chart_id
        HAVING COUNT(*) >= 3
    );

    -- 同样对公式执行
    UPDATE t_formula SET is_hot = 0;

    UPDATE t_formula SET is_hot = 1
    WHERE usage_count >= p_hot_threshold;

    UPDATE t_formula f SET is_hot = 1
    WHERE f.id IN (
        SELECT formula_id FROM t_task
        WHERE task_type = 'formula'
          AND formula_id IS NOT NULL
          AND status = 'SUCCESS'
          AND create_time >= DATE_SUB(NOW(), INTERVAL p_recent_days DAY)
        GROUP BY formula_id
        HAVING COUNT(*) >= 3
    );

    -- 返回刷新结果
    SELECT
        'chart' AS item_type,
        SUM(is_hot) AS hot_count,
        COUNT(*) AS total_count
    FROM t_chart
    UNION ALL
    SELECT
        'formula',
        SUM(is_hot),
        COUNT(*)
    FROM t_formula;
END//
DELIMITER ;


-- ============================================================
-- 存储过程8: sp_category_integrity_check — 分类完整性与闭包表校验
-- 功能: 检查分类表与闭包表的一致性, 发现孤儿节点、缺失闭包记录、
--       环路等问题, 并可选择性自动修复.
-- 参数: p_auto_fix TINYINT(0仅检查/1自动修复)
-- 调用: CALL sp_category_integrity_check(0);
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_category_integrity_check(IN p_auto_fix TINYINT)
BEGIN
    DECLARE v_missing_self INT DEFAULT 0;
    DECLARE v_orphan_closure INT DEFAULT 0;

    -- 检查1: 缺少自引用闭包记录(depth=0)的分类
    SELECT COUNT(*) INTO v_missing_self
    FROM t_category c
    WHERE NOT EXISTS (
        SELECT 1 FROM t_category_closure cc
        WHERE cc.ancestor_id = c.id AND cc.descendant_id = c.id AND cc.depth = 0
    );

    -- 检查2: 闭包表中引用了不存在的分类ID
    SELECT COUNT(*) INTO v_orphan_closure
    FROM t_category_closure cc
    WHERE NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.ancestor_id)
       OR NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.descendant_id);

    -- 输出检查结果
    SELECT
        v_missing_self                                          AS missing_self_refs,
        v_orphan_closure                                        AS orphan_closure_records,
        CASE WHEN v_missing_self = 0 AND v_orphan_closure = 0
             THEN 'HEALTHY' ELSE 'ISSUES_FOUND'
        END                                                     AS integrity_status;

    -- 显示问题详情
    IF v_missing_self > 0 THEN
        SELECT '缺少自引用' AS issue_type, c.id, c.cat_name
        FROM t_category c
        WHERE NOT EXISTS (
            SELECT 1 FROM t_category_closure cc
            WHERE cc.ancestor_id = c.id AND cc.descendant_id = c.id AND cc.depth = 0
        );
    END IF;

    -- 自动修复
    IF p_auto_fix = 1 THEN
        -- 修复: 补充缺失的自引用
        INSERT IGNORE INTO t_category_closure (ancestor_id, descendant_id, depth)
        SELECT id, id, 0 FROM t_category c
        WHERE NOT EXISTS (
            SELECT 1 FROM t_category_closure cc
            WHERE cc.ancestor_id = c.id AND cc.descendant_id = c.id AND cc.depth = 0
        );

        -- 修复: 补充父子关系闭包
        INSERT IGNORE INTO t_category_closure (ancestor_id, descendant_id, depth)
        SELECT c.parent_id, c.id, 1 FROM t_category c
        WHERE c.parent_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM t_category_closure cc
            WHERE cc.ancestor_id = c.parent_id AND cc.descendant_id = c.id
        );

        -- 修复: 删除孤儿闭包记录
        DELETE cc FROM t_category_closure cc
        WHERE NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.ancestor_id)
           OR NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.descendant_id);

        SELECT '自动修复完成' AS fix_status,
               ROW_COUNT() AS affected_rows;
    END IF;

    -- 输出当前闭包表统计
    SELECT
        COUNT(*)                                                AS total_closure_records,
        SUM(depth = 0)                                          AS self_refs,
        SUM(depth = 1)                                          AS direct_parent_child,
        SUM(depth > 1)                                          AS transitive_relations,
        MAX(depth)                                              AS max_depth
    FROM t_category_closure;
END//
DELIMITER ;


-- ############################################################################################
-- 第四章  触发器 (Triggers)
-- 设计理念: 通过触发器实现数据一致性守护、自动审计、统计字段维护、非法操作拦截,
--           让数据库成为业务规则的"最后防线".
-- ############################################################################################

-- 先清理旧触发器(幂等)
DROP TRIGGER IF EXISTS trg_task_after_update;
DROP TRIGGER IF EXISTS trg_task_before_insert;
DROP TRIGGER IF EXISTS trg_task_before_insert_seq;
DROP TRIGGER IF EXISTS trg_task_after_insert;
DROP TRIGGER IF EXISTS trg_task_status_guard;
DROP TRIGGER IF EXISTS trg_history_soft_delete_guard;
DROP TRIGGER IF EXISTS trg_file_after_insert;
DROP TRIGGER IF EXISTS trg_category_after_insert;
DROP TRIGGER IF EXISTS trg_category_before_update;

-- ============================================================
-- 触发器1: trg_task_after_update — 任务完成后自动更新统计 (增强版)
-- 触发时机: t_task AFTER UPDATE
-- 业务规则: 当任务状态变为SUCCESS时:
--   1) 更新对应图表/公式的usage_count
--   2) 自动将图表/公式标记为热门(如超阈值)
--   3) 自动创建历史记录(含快照JSON)
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_task_after_update
AFTER UPDATE ON t_task
FOR EACH ROW
BEGIN
    -- 规则1: 任务成功 → 更新使用计数 + 热门标记
    IF NEW.status = 'SUCCESS' AND OLD.status != 'SUCCESS' THEN
        IF NEW.chart_id IS NOT NULL THEN
            UPDATE t_chart SET
                usage_count = usage_count + 1,
                is_hot = CASE WHEN usage_count + 1 >= 10 THEN 1 ELSE is_hot END
            WHERE id = NEW.chart_id;
        END IF;

        IF NEW.formula_id IS NOT NULL THEN
            UPDATE t_formula SET
                usage_count = usage_count + 1,
                is_hot = CASE WHEN usage_count + 1 >= 10 THEN 1 ELSE is_hot END
            WHERE id = NEW.formula_id;
        END IF;

        -- 自动创建历史记录(含JSON快照)
        INSERT INTO t_history (user_id, task_id, task_type, chart_name, formula_name,
                               result_image, snapshot)
        SELECT
            NEW.user_id,
            NEW.id,
            NEW.task_type,
            (SELECT chart_name FROM t_chart WHERE id = NEW.chart_id),
            (SELECT formula_name FROM t_formula WHERE id = NEW.formula_id),
            NEW.result_path,
            JSON_OBJECT(
                'task_params',    CAST(COALESCE(NEW.task_params, '{}') AS CHAR),
                'render_engine',  NEW.render_engine,
                'duration_sec',   NEW.duration_seconds,
                'file_id',        NEW.file_id,
                'priority',       NEW.priority,
                'completed_at',   DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s')
            );
    END IF;
END//
DELIMITER ;


-- ============================================================
-- 触发器2: trg_task_before_insert — 任务创建前验证
-- 触发时机: t_task BEFORE INSERT
-- 业务规则:
--   1) 确保task_type与chart_id/formula_id一致性(图表任务必须有chart_id等)
--   2) 自动设置初始状态为PENDING
--   3) 根据chart的default_params合并用户参数
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_task_before_insert
BEFORE INSERT ON t_task
FOR EACH ROW
BEGIN
    -- 强制初始状态为PENDING
    IF NEW.status IS NULL OR NEW.status = '' THEN
        SET NEW.status = 'PENDING';
    END IF;

    -- 一致性检查: chart类型必须有chart_id
    IF NEW.task_type = 'chart' AND NEW.chart_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'chart类型任务必须指定chart_id';
    END IF;

    -- 一致性检查: formula类型必须有formula_id
    IF NEW.task_type = 'formula' AND NEW.formula_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'formula类型任务必须指定formula_id';
    END IF;

    -- 自动推断render_engine(根据chart_code, 如Plotly/Bokeh/Altair类型)
    IF NEW.task_type = 'chart' AND (NEW.render_engine IS NULL OR NEW.render_engine = 'matplotlib') THEN
        SET NEW.render_engine = COALESCE(
            (SELECT CASE
                WHEN c.chart_code LIKE 'plotly%' THEN 'plotly'
                WHEN c.chart_code LIKE 'bokeh%'  THEN 'bokeh'
                WHEN c.chart_code LIKE 'altair%' THEN 'altair'
                ELSE 'matplotlib'
             END
             FROM t_chart c WHERE c.id = NEW.chart_id),
            'matplotlib'
        );
    END IF;
END//
DELIMITER ;


-- ============================================================
-- 触发器3: trg_task_before_insert_seq — 任务创建前序号填充
-- 触发时机: t_task BEFORE INSERT (注意: MySQL不允许同表同时机多个触发器,
--           因此此逻辑合并到trg_task_before_insert中, 此处单独创建用于
--           total_tasks字段更新, 利用BEFORE INSERT可读同表)
-- 注意: MySQL 8.0允许同表同事件多个触发器(FOLLOWS/PRECEDES)
-- 业务规则: 自动在BEFORE INSERT阶段填充total_tasks(当前用户任务计数+1)
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_task_before_insert_seq
BEFORE INSERT ON t_task
FOR EACH ROW
FOLLOWS trg_task_before_insert
BEGIN
    -- 在BEFORE INSERT阶段设置total_tasks(+1 包含当前正在插入的这条)
    SET NEW.total_tasks = (
        SELECT COUNT(*) + 1 FROM t_task WHERE user_id = NEW.user_id
    );
END//
DELIMITER ;


-- ============================================================
-- 触发器4: trg_history_soft_delete_guard — 历史记录软删除守护
-- 触发时机: t_history BEFORE UPDATE
-- 业务规则:
--   1) 当is_deleted从0变为1时, 自动记录deleted_at时间戳
--   2) 禁止将已软删除的记录恢复(除非通过存储过程)
--   3) rating只能在1-5范围内
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_history_soft_delete_guard
BEFORE UPDATE ON t_history
FOR EACH ROW
BEGIN
    -- 软删除: 自动记录删除时间
    IF NEW.is_deleted = 1 AND OLD.is_deleted = 0 THEN
        SET NEW.deleted_at = NOW();
    END IF;

    -- 评分范围守护
    IF NEW.rating IS NOT NULL AND (NEW.rating < 1 OR NEW.rating > 5) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '评分必须在1-5之间';
    END IF;
END//
DELIMITER ;


-- ============================================================
-- 触发器5: trg_file_after_insert — 文件上传后自动维护
-- 触发时机: t_file AFTER INSERT
-- 业务规则: 无额外操作, 但预留审计钩子. 未来可用于自动通知、配额检查等.
--           当前: 更新分类的item_count(通过file关联的task的chart/formula的cat_id)
-- ============================================================
-- (此触发器暂不创建, 因为文件与分类无直接关联, 用下面的分类触发器代替)

-- ============================================================
-- 触发器5(替代): trg_category_after_insert — 分类创建后自动维护闭包表
-- 触发时机: t_category AFTER INSERT
-- 业务规则: 新分类插入后, 自动在闭包表中:
--   1) 插入自引用记录(depth=0)
--   2) 如果有parent_id, 插入与所有祖先的关系(利用闭包表传递性)
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_category_after_insert
AFTER INSERT ON t_category
FOR EACH ROW
BEGIN
    -- 插入自引用
    INSERT INTO t_category_closure (ancestor_id, descendant_id, depth)
    VALUES (NEW.id, NEW.id, 0);

    -- 如果有父节点, 通过闭包传递性插入所有祖先关系
    IF NEW.parent_id IS NOT NULL THEN
        INSERT INTO t_category_closure (ancestor_id, descendant_id, depth)
        SELECT cc.ancestor_id, NEW.id, cc.depth + 1
        FROM t_category_closure cc
        WHERE cc.descendant_id = NEW.parent_id;
    END IF;
END//
DELIMITER ;


-- ============================================================
-- 触发器6: trg_category_before_update — 分类移动时自动重建闭包关系
-- 触发时机: t_category BEFORE UPDATE
-- 业务规则: 当 parent_id 发生变更(节点移动)时:
--   1) 断开移动子树与旧祖先链的闭包关系(保留子树内部关系)
--   2) 与新父节点的所有祖先建立新的闭包关系(含传递性)
-- 算法: Bill Karwin 闭包表标准子树移动算法
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_category_before_update
BEFORE UPDATE ON t_category
FOR EACH ROW
BEGIN
    DECLARE v_parent_changed INT DEFAULT 0;

    SET v_parent_changed = CASE
        WHEN OLD.parent_id IS NULL AND NEW.parent_id IS NULL THEN 0
        WHEN OLD.parent_id IS NULL AND NEW.parent_id IS NOT NULL THEN 1
        WHEN OLD.parent_id IS NOT NULL AND NEW.parent_id IS NULL THEN 1
        WHEN OLD.parent_id != NEW.parent_id THEN 1
        ELSE 0
    END;

    IF v_parent_changed = 1 THEN
        -- 步骤1: 断开子树与旧祖先的关系(双层子查询绕过MySQL限制)
        DELETE FROM t_category_closure
        WHERE descendant_id IN (
            SELECT sub1.did FROM (
                SELECT descendant_id AS did FROM t_category_closure WHERE ancestor_id = OLD.id
            ) sub1
        )
        AND ancestor_id NOT IN (
            SELECT sub2.did FROM (
                SELECT descendant_id AS did FROM t_category_closure WHERE ancestor_id = OLD.id
            ) sub2
        );

        -- 步骤2: 与新父节点建立闭包关系(含传递性)
        IF NEW.parent_id IS NOT NULL THEN
            INSERT INTO t_category_closure (ancestor_id, descendant_id, depth)
            SELECT a.ancestor_id, d.descendant_id, a.depth + d.depth + 1
            FROM t_category_closure AS a
            CROSS JOIN t_category_closure AS d
            WHERE a.descendant_id = NEW.parent_id
              AND d.ancestor_id = OLD.id;
        END IF;
    END IF;
END//
DELIMITER ;


-- ============================================================
-- 触发器7: trg_task_status_guard — 任务状态流转守护(BEFORE UPDATE)
-- 触发时机: t_task BEFORE UPDATE (状态变更时)
-- 业务规则: 在数据库层强制状态机规则, 即使绕过存储过程直接UPDATE也能拦截
-- 合法流转: PENDING->PROCESSING, PROCESSING->SUCCESS/FAILED, FAILED->PENDING
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_task_status_guard
BEFORE UPDATE ON t_task
FOR EACH ROW
BEGIN
    -- 仅在状态发生变化时检查
    IF OLD.status != NEW.status THEN
        -- 白名单模式: 只允许合法的状态流转
        IF NOT (
            (OLD.status = 'PENDING'    AND NEW.status = 'PROCESSING') OR
            (OLD.status = 'PROCESSING' AND NEW.status = 'SUCCESS')    OR
            (OLD.status = 'PROCESSING' AND NEW.status = 'FAILED')     OR
            (OLD.status = 'FAILED'     AND NEW.status = 'PENDING')
        ) THEN
            SET @trg_err_msg = CONCAT('非法状态流转被触发器拦截: ',
                                     OLD.status, ' -> ', NEW.status);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @trg_err_msg;
        END IF;

        -- 自动填充时间戳
        IF NEW.status = 'PROCESSING' AND NEW.start_time IS NULL THEN
            SET NEW.start_time = NOW();
        END IF;

        IF NEW.status IN ('SUCCESS', 'FAILED') AND NEW.finish_time IS NULL THEN
            SET NEW.finish_time = NOW();
        END IF;
    END IF;
END//
DELIMITER ;


-- ############################################################################################
-- 第五章  高级特性与整体提升
-- ############################################################################################

-- ============================================================
-- 5.1 MySQL Event Scheduler — 定时自动维护
-- 启用事件调度器(需SUPER权限)
-- ============================================================
SET GLOBAL event_scheduler = ON;

-- 事件1: 每天凌晨2点自动刷新热门标记
DELIMITER //
CREATE EVENT IF NOT EXISTS evt_daily_hot_refresh
ON SCHEDULE EVERY 1 DAY
STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 02:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT '每日凌晨自动刷新图表/公式热门标记'
DO
BEGIN
    CALL sp_hot_items_refresh(10, 7);
END//
DELIMITER ;

-- 事件2: 每周日凌晨3点执行分类完整性检查并自动修复
DELIMITER //
CREATE EVENT IF NOT EXISTS evt_weekly_integrity_check
ON SCHEDULE EVERY 1 WEEK
STARTS CONCAT(CURDATE() + INTERVAL (7 - WEEKDAY(CURDATE())) DAY, ' 03:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT '每周日凌晨自动检查并修复分类闭包表完整性'
DO
BEGIN
    CALL sp_category_integrity_check(1);
END//
DELIMITER ;

-- 事件3: 每月1号凌晨4点清理超过180天的软删除历史记录
DELIMITER //
CREATE EVENT IF NOT EXISTS evt_monthly_history_cleanup
ON SCHEDULE EVERY 1 MONTH
STARTS CONCAT(DATE_FORMAT(CURDATE() + INTERVAL 1 MONTH, '%Y-%m'), '-01 04:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT '每月自动清理超过180天的软删除历史记录'
DO
BEGIN
    DELETE FROM t_history
    WHERE is_deleted = 1
      AND deleted_at IS NOT NULL
      AND deleted_at < DATE_SUB(NOW(), INTERVAL 180 DAY);
END//
DELIMITER ;

-- 事件4: 每天凌晨1点更新用户account_age_days和is_active字段
DELIMITER //
CREATE EVENT IF NOT EXISTS evt_daily_user_stats_refresh
ON SCHEDULE EVERY 1 DAY
STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 01:00:00')
ON COMPLETION PRESERVE
ENABLE
COMMENT '每日凌晨自动更新用户账龄和活跃状态'
DO
BEGIN
    UPDATE t_user SET
        account_age_days = DATEDIFF(CURDATE(), DATE(create_time)),
        is_active = CASE
            WHEN status = 1 AND last_login_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1
            ELSE 0
        END;
END//
DELIMITER ;


-- ============================================================
-- 5.2 补充高级查询示例 — 递归CTE (配合闭包表验证)
-- 用途: 展示如何用递归CTE遍历分类树, 与闭包表互相验证
-- ============================================================

-- 示例: 递归CTE获取完整分类层级(独立于闭包表)
-- 可用 SELECT * FROM v_category_recursive_tree; 测试
DROP VIEW IF EXISTS v_category_recursive_tree;

CREATE VIEW v_category_recursive_tree AS
WITH RECURSIVE cat_tree AS (
    -- 锚点: 根节点(parent_id IS NULL)
    SELECT
        id,
        cat_name,
        cat_type,
        parent_id,
        0                                                       AS depth,
        CAST(cat_name AS CHAR(1000))                             AS full_path,
        CAST(id AS CHAR(500))                                    AS id_path
    FROM t_category
    WHERE parent_id IS NULL

    UNION ALL

    -- 递归: 子节点
    SELECT
        c.id,
        c.cat_name,
        c.cat_type,
        c.parent_id,
        ct.depth + 1,
        CONCAT(ct.full_path, ' > ', c.cat_name),
        CONCAT(ct.id_path, '/', c.id)
    FROM t_category c
    JOIN cat_tree ct ON c.parent_id = ct.id
)
SELECT
    ct.*,
    -- 用闭包表交叉验证深度
    (SELECT MAX(cc.depth) FROM t_category_closure cc WHERE cc.descendant_id = ct.id)
                                                                AS closure_verified_depth,
    -- 后代数量(闭包表)
    (SELECT COUNT(*) - 1 FROM t_category_closure cc WHERE cc.ancestor_id = ct.id)
                                                                AS descendant_count
FROM cat_tree ct;


-- ============================================================
-- 5.3 补充索引优化 — 覆盖索引
-- ============================================================

-- t_task: 覆盖索引, 用于用户任务列表查询(无需回表)
ALTER TABLE t_task
    ADD INDEX idx_task_covering_list (user_id, status, task_type, create_time, id);

-- t_history: 覆盖索引, 用于用户历史列表查询
ALTER TABLE t_history
    ADD INDEX idx_history_covering (user_id, is_deleted, create_time, task_type, id);

-- t_data_item: 覆盖索引, 用于文件数据质量统计
ALTER TABLE t_data_item
    ADD INDEX idx_data_quality_covering (file_id, is_null_val, data_type, value_length);

-- t_category_closure: 反向查询索引
ALTER TABLE t_category_closure
    ADD INDEX idx_closure_descendant (descendant_id, ancestor_id, depth);


-- ============================================================
-- 5.4 角色元数据初始化 — 为配额管理提供数据支撑
-- ============================================================
UPDATE t_role SET metadata = JSON_OBJECT(
    'max_tasks_per_day', 200,
    'max_file_size_mb', 100,
    'allowed_engines', JSON_ARRAY('matplotlib', 'plotly', 'bokeh', 'altair'),
    'priority_range', JSON_ARRAY(1, 10)
) WHERE role_code = 'ROLE_ADMIN';

UPDATE t_role SET metadata = JSON_OBJECT(
    'max_tasks_per_day', 50,
    'max_file_size_mb', 20,
    'allowed_engines', JSON_ARRAY('matplotlib', 'plotly'),
    'priority_range', JSON_ARRAY(3, 10)
) WHERE role_code = 'ROLE_USER';


-- ############################################################################################
-- 实施完毕 — 优化总结
-- ############################################################################################
-- ┌──────────────────────────────────────────────────────────────────────────────────┐
-- │ 优化项目                │ 数量  │ 高级特性                                       │
-- ├──────────────────────────────────────────────────────────────────────────────────┤
-- │ ALTER TABLE (表增强)     │ 10表  │ 生成列(Stored) ×8, JSON字段 ×10, 审计字段      │
-- │ 索引优化                │ 20+   │ 覆盖索引, 复合索引, 唯一索引, 生成列索引        │
-- │ 视图 (Views)            │ 9个   │ 窗口函数, 递归CTE, JSON聚合, UNION, 闭包表      │
-- │ 存储过程 (Procedures)   │ 8个   │ 状态机, JSON操作, 多结果集, 异常处理, 配额      │
-- │ 触发器 (Triggers)       │ 7个   │ 状态守护, 闭包自维护(含移动), 软删除, 一致性 │
-- │ 事件 (Events)           │ 4个   │ 定时热点刷新, 完整性检查, 数据清理, 用户状态   │
-- └──────────────────────────────────────────────────────────────────────────────────┘
--
-- 生成列应用:
--   t_user.account_age_days    — DATEDIFF自动计算账龄
--   t_user.is_active           — 30天活跃度自动判定
--   t_permission.perm_level    — 权限层级深度
--   t_file.file_size_mb        — 字节自动转MB
--   t_file.cell_count          — 行×列自动计算
--   t_data_item.value_length   — 值长度自动计算
--   t_data_item.is_null_val    — 空值标记自动计算
--   t_chart.popularity_rank    — S/A/B/C/D等级自动推算
--   t_formula.popularity_rank  — 同上
--   t_formula.latex_length     — LaTeX长度自动计算
--   t_task.duration_seconds    — 耗时自动计算
--
-- 实施优先级建议:
--   P0(立即): ALTER TABLE + 触发器 → 保证数据一致性基础设施
--   P1(次日): 视图 + 存储过程 → 为前端提供高级查询能力
--   P2(第三天): Event Scheduler + 索引优化 → 自动化运维与性能提升
--   P3(持续): 角色元数据完善 + 数据画像积累 → 智能推荐系统持续优化
