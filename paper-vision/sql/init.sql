-- ============================================================
-- 论文可视化助手系统 - 数据库初始化脚本
-- MySQL 8.0+
-- ============================================================

CREATE DATABASE IF NOT EXISTS paper_vision DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE paper_vision;

-- ============================================================
-- 1. 用户表
-- ============================================================
CREATE TABLE t_user (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    nickname VARCHAR(50),
    avatar VARCHAR(255),
    status TINYINT DEFAULT 1 COMMENT '0禁用 1启用',
    last_login_time DATETIME,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- ============================================================
-- 2. 角色表
-- ============================================================
CREATE TABLE t_role (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    role_code VARCHAR(30) NOT NULL UNIQUE COMMENT '角色编码 ROLE_ADMIN/ROLE_USER',
    role_name VARCHAR(50) NOT NULL COMMENT '角色名称',
    description VARCHAR(200),
    status TINYINT DEFAULT 1,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色表';

-- ============================================================
-- 3. 权限表
-- ============================================================
CREATE TABLE t_permission (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    perm_code VARCHAR(50) NOT NULL UNIQUE COMMENT '权限编码 user:view, chart:create 等',
    perm_name VARCHAR(50) NOT NULL COMMENT '权限名称',
    parent_id BIGINT DEFAULT NULL,
    perm_type VARCHAR(20) NOT NULL COMMENT 'menu/button',
    path VARCHAR(100),
    icon VARCHAR(50),
    sort_order INT DEFAULT 0,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (parent_id) REFERENCES t_permission(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限表';

-- ============================================================
-- 4. 用户-角色关联表
-- ============================================================
CREATE TABLE t_user_role (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_user_role (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES t_user(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES t_role(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户角色关联表';

-- ============================================================
-- 5. 角色-权限关联表
-- ============================================================
CREATE TABLE t_role_permission (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    role_id BIGINT NOT NULL,
    perm_id BIGINT NOT NULL,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_role_perm (role_id, perm_id),
    FOREIGN KEY (role_id) REFERENCES t_role(id) ON DELETE CASCADE,
    FOREIGN KEY (perm_id) REFERENCES t_permission(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色权限关联表';

-- ============================================================
-- 6. 文件表
-- ============================================================
CREATE TABLE t_file (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    file_name VARCHAR(255) NOT NULL COMMENT '原始文件名',
    file_path VARCHAR(500) NOT NULL COMMENT '存储路径',
    file_type VARCHAR(20) NOT NULL COMMENT 'csv/excel/txt',
    file_size BIGINT COMMENT '文件大小(字节)',
    total_rows INT DEFAULT 0 COMMENT '数据行数',
    total_cols INT DEFAULT 0 COMMENT '数据列数',
    status TINYINT DEFAULT 1 COMMENT '0删除 1正常',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_file (user_id, create_time),
    INDEX idx_file_type (file_type),
    FOREIGN KEY (user_id) REFERENCES t_user(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='文件表';

-- ============================================================
-- 7. 数据项表
-- ============================================================
CREATE TABLE t_data_item (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    file_id BIGINT NOT NULL,
    row_index INT NOT NULL COMMENT '行索引',
    col_name VARCHAR(100) NOT NULL COMMENT '列名',
    col_value TEXT COMMENT '单元格值',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_file_col (file_id, col_name),
    FOREIGN KEY (file_id) REFERENCES t_file(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='数据项表';

-- ============================================================
-- 8. 分类表 (闭包约束: 树形结构)
-- ============================================================
CREATE TABLE t_category (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cat_name VARCHAR(100) NOT NULL,
    cat_type VARCHAR(20) NOT NULL COMMENT 'chart/formula',
    parent_id BIGINT DEFAULT NULL,
    sort_order INT DEFAULT 0,
    description VARCHAR(255),
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (parent_id) REFERENCES t_category(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分类表(图表/公式)';

-- 分类闭包表
CREATE TABLE t_category_closure (
    ancestor_id BIGINT NOT NULL,
    descendant_id BIGINT NOT NULL,
    depth INT NOT NULL DEFAULT 0,
    PRIMARY KEY (ancestor_id, descendant_id),
    FOREIGN KEY (ancestor_id) REFERENCES t_category(id) ON DELETE CASCADE,
    FOREIGN KEY (descendant_id) REFERENCES t_category(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='分类闭包表';

-- ============================================================
-- 9. 图表表
-- ============================================================
CREATE TABLE t_chart (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    chart_name VARCHAR(100) NOT NULL,
    chart_code VARCHAR(50) NOT NULL UNIQUE COMMENT 'bar, line, pie, scatter...',
    cat_id BIGINT,
    description VARCHAR(500),
    default_params JSON COMMENT '默认参数JSON',
    usage_count BIGINT DEFAULT 0 COMMENT '使用次数',
    is_hot TINYINT DEFAULT 0,
    sort_order INT DEFAULT 0,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_chart_code (chart_code),
    INDEX idx_chart_hot (is_hot, usage_count),
    INDEX idx_chart_cat (cat_id),
    FOREIGN KEY (cat_id) REFERENCES t_category(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='图表表';

-- ============================================================
-- 10. 公式表
-- ============================================================
CREATE TABLE t_formula (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    formula_name VARCHAR(100) NOT NULL,
    formula_code VARCHAR(50) NOT NULL UNIQUE COMMENT 'integral, sum, matrix...',
    cat_id BIGINT,
    latex_template TEXT COMMENT 'LaTeX模板',
    description VARCHAR(500),
    usage_count BIGINT DEFAULT 0,
    is_hot TINYINT DEFAULT 0,
    sort_order INT DEFAULT 0,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_formula_code (formula_code),
    INDEX idx_formula_hot (is_hot, usage_count),
    INDEX idx_formula_cat (cat_id),
    FOREIGN KEY (cat_id) REFERENCES t_category(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='公式表';

-- ============================================================
-- 11. 任务表
-- ============================================================
CREATE TABLE t_task (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    task_type VARCHAR(20) NOT NULL COMMENT 'chart/formula',
    chart_id BIGINT DEFAULT NULL,
    formula_id BIGINT DEFAULT NULL,
    file_id BIGINT DEFAULT NULL,
    task_params JSON COMMENT '用户自定义参数字段/颜色等',
    result_path VARCHAR(500) COMMENT '结果图片路径',
    result_pdf VARCHAR(500) COMMENT 'PDF矢量路径',
    status VARCHAR(20) DEFAULT 'PENDING' COMMENT 'PENDING/PROCESSING/SUCCESS/FAILED',
    error_msg TEXT,
    total_tasks BIGINT DEFAULT 0 COMMENT '用户总任务数(触发器更新)',
    start_time DATETIME,
    finish_time DATETIME,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_task (user_id, create_time),
    INDEX idx_task_type (task_type),
    INDEX idx_task_status (status),
    INDEX idx_task_create (create_time),
    FOREIGN KEY (user_id) REFERENCES t_user(id) ON DELETE CASCADE,
    FOREIGN KEY (chart_id) REFERENCES t_chart(id) ON DELETE SET NULL,
    FOREIGN KEY (formula_id) REFERENCES t_formula(id) ON DELETE SET NULL,
    FOREIGN KEY (file_id) REFERENCES t_file(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='任务表';

-- ============================================================
-- 12. 历史记录表
-- ============================================================
CREATE TABLE t_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    task_id BIGINT NOT NULL,
    task_type VARCHAR(20) NOT NULL,
    chart_name VARCHAR(100),
    formula_name VARCHAR(100),
    result_image VARCHAR(500) COMMENT '图片Base64或路径',
    is_deleted TINYINT DEFAULT 0,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_history (user_id, create_time),
    FOREIGN KEY (user_id) REFERENCES t_user(id) ON DELETE CASCADE,
    FOREIGN KEY (task_id) REFERENCES t_task(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='历史记录表';

-- ============================================================
-- 触发器: 任务完成自动更新统计字段
-- ============================================================
DELIMITER //
CREATE TRIGGER trg_task_after_update
AFTER UPDATE ON t_task
FOR EACH ROW
BEGIN
    IF NEW.status = 'SUCCESS' AND OLD.status != 'SUCCESS' THEN
        IF NEW.chart_id IS NOT NULL THEN
            UPDATE t_chart SET usage_count = usage_count + 1 WHERE id = NEW.chart_id;
        END IF;
        IF NEW.formula_id IS NOT NULL THEN
            UPDATE t_formula SET usage_count = usage_count + 1 WHERE id = NEW.formula_id;
        END IF;
    END IF;
END//
DELIMITER ;

-- ============================================================
-- 视图1: 热门图表
-- ============================================================
CREATE VIEW v_hot_charts AS
SELECT c.id, c.chart_name, c.chart_code, c.usage_count, c.is_hot,
       cat.cat_name AS category_name
FROM t_chart c
LEFT JOIN t_category cat ON c.cat_id = cat.id
WHERE c.is_hot = 1 OR c.usage_count > 5
ORDER BY c.usage_count DESC, c.sort_order
LIMIT 20;

-- ============================================================
-- 视图2: 热门公式
-- ============================================================
CREATE VIEW v_hot_formulas AS
SELECT f.id, f.formula_name, f.formula_code, f.usage_count, f.is_hot,
       cat.cat_name AS category_name
FROM t_formula f
LEFT JOIN t_category cat ON f.cat_id = cat.id
WHERE f.is_hot = 1 OR f.usage_count > 5
ORDER BY f.usage_count DESC, f.sort_order
LIMIT 20;

-- ============================================================
-- 视图3: 用户任务统计
-- ============================================================
CREATE VIEW v_user_task_stats AS
SELECT u.id AS user_id, u.username,
       COUNT(t.id) AS total_tasks,
       SUM(CASE WHEN t.status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
       SUM(CASE WHEN t.status = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
       SUM(CASE WHEN t.task_type = 'chart' THEN 1 ELSE 0 END) AS chart_count,
       SUM(CASE WHEN t.task_type = 'formula' THEN 1 ELSE 0 END) AS formula_count,
       MAX(t.create_time) AS last_task_time
FROM t_user u
LEFT JOIN t_task t ON u.id = t.user_id
GROUP BY u.id, u.username;

-- ============================================================
-- 存储过程1: 每日统计
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_daily_stats(IN stat_date DATE)
BEGIN
    SELECT
        stat_date AS date,
        COUNT(*) AS total_tasks,
        SUM(CASE WHEN task_type = 'chart' THEN 1 ELSE 0 END) AS chart_tasks,
        SUM(CASE WHEN task_type = 'formula' THEN 1 ELSE 0 END) AS formula_tasks,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
        SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) AS failed_count,
        COUNT(DISTINCT user_id) AS active_users
    FROM t_task
    WHERE DATE(create_time) = stat_date;
END//
DELIMITER ;

-- ============================================================
-- 存储过程2: 热门图表统计 (Top N)
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_hot_chart_stats(IN top_n INT)
BEGIN
    SELECT c.id, c.chart_name, c.chart_code, c.usage_count,
           cat.cat_name AS category_name
    FROM t_chart c
    LEFT JOIN t_category cat ON c.cat_id = cat.id
    ORDER BY c.usage_count DESC
    LIMIT top_n;
END//
DELIMITER ;

-- ============================================================
-- 存储过程3: 用户排行
-- ============================================================
DELIMITER //
CREATE PROCEDURE sp_user_ranking(IN top_n INT)
BEGIN
    SELECT u.id, u.username, u.nickname,
           COUNT(t.id) AS total_tasks,
           SUM(CASE WHEN t.status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count
    FROM t_user u
    LEFT JOIN t_task t ON u.id = t.user_id
    GROUP BY u.id, u.username, u.nickname
    ORDER BY total_tasks DESC, success_count DESC
    LIMIT top_n;
END//
DELIMITER ;

-- ============================================================
-- 初始数据: 角色
-- ============================================================
INSERT INTO t_role (role_code, role_name, description) VALUES
('ROLE_ADMIN', '管理员', '系统管理员，拥有全部权限'),
('ROLE_USER', '普通用户', '普通注册用户');

-- ============================================================
-- 初始数据: 权限
-- ============================================================
INSERT INTO t_permission (perm_code, perm_name, parent_id, perm_type, path, sort_order) VALUES
('dashboard', '仪表盘', NULL, 'menu', '/dashboard', 1),
('user:list', '用户列表', NULL, 'menu', '/admin/users', 2),
('user:create', '创建用户', NULL, 'button', NULL, 3),
('user:update', '修改用户', NULL, 'button', NULL, 4),
('user:delete', '删除用户', NULL, 'button', NULL, 5),
('role:manage', '角色管理', NULL, 'menu', '/admin/roles', 6),
('data:upload', '数据上传', NULL, 'menu', '/data/upload', 7),
('data:view', '数据查看', NULL, 'menu', '/data/view', 8),
('chart:create', '生成图表', NULL, 'menu', '/chart/create', 9),
('formula:create', '生成公式', NULL, 'menu', '/formula/create', 10),
('history:view', '历史记录', NULL, 'menu', '/history', 11),
('admin:stats', '管理统计', NULL, 'menu', '/admin/stats', 12);

-- ============================================================
-- 初始数据: 角色-权限关联 (管理员拥有所有权限)
-- ============================================================
INSERT INTO t_role_permission (role_id, perm_id)
SELECT 1, id FROM t_permission;

-- 普通用户权限
INSERT INTO t_role_permission (role_id, perm_id) VALUES
(2, 1), (2, 7), (2, 8), (2, 9), (2, 10), (2, 11);

-- ============================================================
-- 初始数据: 分类
-- ============================================================
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order, description) VALUES
('统计图表', 'chart', NULL, 1, '常用统计图表类型'),
('关系图表', 'chart', NULL, 2, '用于展示数据关系'),
('分布图表', 'chart', NULL, 3, '数据分布相关图表'),
('时序图表', 'chart', NULL, 4, '时间序列数据图表'),
('数学公式', 'formula', NULL, 1, '基础数学公式'),
('微积分', 'formula', NULL, 2, '积分与微分公式'),
('概率统计', 'formula', NULL, 3, '概率与统计公式');

-- 插入闭包数据 (自引用)
INSERT INTO t_category_closure (ancestor_id, descendant_id, depth)
SELECT id, id, 0 FROM t_category;

-- ============================================================
-- 初始数据: 图表 (20+种)
-- ============================================================
INSERT INTO t_chart (chart_name, chart_code, cat_id, description, default_params, sort_order) VALUES
('柱状图', 'bar', 1, '标准柱状图，支持水平和垂直方向', '{"orientation":"vertical","color":"Blues"}', 1),
('分组柱状图', 'grouped_bar', 1, '多系列分组柱状图', '{"orientation":"vertical","color":"Set2"}', 2),
('堆叠柱状图', 'stacked_bar', 1, '多系列堆叠柱状图', '{"orientation":"vertical","color":"Set3"}', 3),
('折线图', 'line', 4, '标准折线图，展示趋势', '{"marker":"o","color":"tab10"}', 4),
('多折线图', 'multi_line', 4, '多系列折线对比图', '{"marker":"o","color":"tab10"}', 5),
('散点图', 'scatter', 2, '二维散点图', '{"color":"viridis","size":50}', 6),
('气泡图', 'bubble', 2, '三维气泡散点图', '{"color":"plasma","scale":200}', 7),
('饼图', 'pie', 1, '饼图展示比例', '{"explode":0,"color":"Pastel1"}', 8),
('环形图', 'donut', 1, '环形/甜甜圈图', '{"inner_radius":0.4,"color":"Pastel2"}', 9),
('热力图', 'heatmap', 2, '相关性矩阵热力图', '{"cmap":"coolwarm","annot":true}', 10),
('箱线图', 'boxplot', 3, '箱线图展示数据分布', '{"orientation":"vertical","color":"Set2"}', 11),
('小提琴图', 'violin', 3, '小提琴图加箱线', '{"color":"Set3"}', 12),
('雷达图', 'radar', 2, '多维度雷达/蜘蛛图', '{"fill":true,"color":"tab10"}', 13),
('甘特图', 'gantt', 4, '项目进度甘特图', '{"color":"tab20"}', 14),
('桑基图', 'sankey', 2, '流向桑基图', '{"color":"Set3"}', 15),
('Treemap', 'treemap', 3, '矩形树图', '{"cmap":"viridis"}', 16),
('平行坐标图', 'parallel', 2, '多维平行坐标图', '{"color":"tab10"}', 17),
('词云', 'wordcloud', 3, '词云图', '{"max_words":100,"bg":"white"}', 18),
('3D曲面图', 'surface3d', 3, '三维曲面/等高线图', '{"cmap":"viridis","elevation":30}', 19),
('帕累托图', 'pareto', 1, '二八原则帕累托图', '{"color":"tab10"}', 20),
('K线图', 'candlestick', 4, '股票K线/OHLC图', '{"up_color":"red","down_color":"green"}', 21),
('面积图', 'area', 4, '堆叠面积图', '{"color":"Set2","alpha":0.7}', 22),
('韦恩图', 'venn', 3, 'matplotlib-venn 集合关系图', '{"color":"Set2"}', 23),
('网络关系图', 'network', 2, 'NetworkX 网络拓扑图', '{"color":"Set2"}', 24),
('Plotly散点图', 'plotly_scatter', 2, 'Plotly 交互式散点图(HTML)', '{}', 25),
('Bokeh柱状图', 'bokeh_bar', 1, 'Bokeh 交互式柱状图(HTML)', '{}', 26),
('Altair图表', 'altair', 1, 'Altair 声明式交互图表(HTML)', '{}', 27);

-- ============================================================
-- 初始数据: 公式 (10+种)
-- ============================================================
INSERT INTO t_formula (formula_name, formula_code, cat_id, latex_template, description, sort_order) VALUES
('定积分', 'integral', 6, '\\int_{a}^{b} f(x) \\, dx', '定积分公式渲染', 1),
('双重积分', 'double_integral', 6, '\\iint_{D} f(x,y) \\, dx\\,dy', '双重积分', 2),
('求和公式', 'sum', 5, '\\sum_{i=1}^{n} a_i', '求和公式', 3),
('多重求和', 'multi_sum', 5, '\\sum_{i=1}^{n}\\sum_{j=1}^{m} a_{ij}', '嵌套求和', 4),
('矩阵', 'matrix', 5, '\\begin{pmatrix} a_{11} & a_{12} \\\\ a_{21} & a_{22} \\end{pmatrix}', '矩阵', 5),
('行列式', 'determinant', 5, '\\begin{vmatrix} a & b \\\\ c & d \\end{vmatrix}', '行列式', 6),
('偏微分', 'partial_diff', 6, '\\frac{\\partial f}{\\partial x}', '偏微分', 7),
('梯度', 'gradient', 6, '\\nabla f = \\left( \\frac{\\partial f}{\\partial x}, \\frac{\\partial f}{\\partial y} \\right)', '梯度算子', 8),
('正态分布', 'normal_dist', 7, 'f(x) = \\frac{1}{\\sigma\\sqrt{2\\pi}} e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}', '正态分布概率密度', 9),
('贝叶斯公式', 'bayes', 7, 'P(A|B) = \\frac{P(B|A) \\cdot P(A)}{P(B)}', '贝叶斯定理', 10),
('傅里叶变换', 'fourier', 5, 'F(\\omega) = \\int_{-\\infty}^{\\infty} f(t) e^{-i\\omega t} dt', '傅里叶变换', 11),
('矩阵乘法', 'matrix_mul', 5, 'C_{ij} = \\sum_{k} A_{ik} B_{kj}', '矩阵乘法', 12);

-- ============================================================
-- 初始数据: 管理员用户 (密码: admin123  BCrypt)
-- ============================================================
INSERT INTO t_user (username, password, email, nickname) VALUES
('admin', '$2b$10$Wn9xdoa5Cm3MZk8Ui4srmu4/b10aefuYM/fMPZrAXFqAXjs1Amu9u', 'admin@papervision.com', '系统管理员');

INSERT INTO t_user_role (user_id, role_id) VALUES (1, 1);
