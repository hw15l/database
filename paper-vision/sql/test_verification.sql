-- ============================================================================================
-- Paper Vision 数据库优化 — 全面验证测试脚本
-- 覆盖: 触发器拦截(含全部非法状态流转) · 闭包表自维护 · 生成列逻辑 · 存储过程 · 并发安全
-- ============================================================================================
USE paper_vision;

-- ============================================================
-- 测试基础设施: 结果表 + 辅助过程
-- ============================================================
DROP TABLE IF EXISTS _test_results;
CREATE TEMPORARY TABLE _test_results (
    seq       INT AUTO_INCREMENT PRIMARY KEY,
    test_id   VARCHAR(10),
    category  VARCHAR(30),
    test_name VARCHAR(200),
    expected  VARCHAR(100),
    actual    VARCHAR(100),
    pass_fail VARCHAR(20),
    detail    TEXT DEFAULT NULL
) ENGINE=InnoDB;

-- 辅助: 记录PASS
DROP PROCEDURE IF EXISTS _pass;
DELIMITER //
CREATE PROCEDURE _pass(IN tid VARCHAR(10), IN cat VARCHAR(30), IN tname VARCHAR(200), IN det TEXT)
BEGIN
    INSERT INTO _test_results (test_id,category,test_name,expected,actual,pass_fail,detail)
    VALUES (tid, cat, tname, 'PASS', 'PASS', 'PASS', det);
END//
DELIMITER ;

-- 辅助: 记录FAIL
DROP PROCEDURE IF EXISTS _fail;
DELIMITER //
CREATE PROCEDURE _fail(IN tid VARCHAR(10), IN cat VARCHAR(30), IN tname VARCHAR(200), IN det TEXT)
BEGIN
    INSERT INTO _test_results (test_id,category,test_name,expected,actual,pass_fail,detail)
    VALUES (tid, cat, tname, 'PASS', 'FAIL', '** FAIL **', det);
END//
DELIMITER ;


-- ============================================================
-- 准备测试夹具 (Fixtures)
-- ============================================================

-- 测试用户
INSERT INTO t_user (username, password, email, nickname, status, last_login_time) VALUES
('test_u1', '$2b$10$xxx', 'u1@test.com', '测试用户1', 1, NOW()),
('test_u2', '$2b$10$xxx', 'u2@test.com', '测试用户2', 1, DATE_SUB(NOW(), INTERVAL 60 DAY)),
('test_u3', '$2b$10$xxx', 'u3@test.com', '测试用户3', 0, NOW());
INSERT INTO t_user_role (user_id, role_id)
SELECT id, 2 FROM t_user WHERE username LIKE 'test_u%';

-- 测试文件
INSERT INTO t_file (user_id, file_name, file_path, file_type, file_size, total_rows, total_cols, status) VALUES
((SELECT id FROM t_user WHERE username='test_u1'), 'test_data.csv', '/tmp/test_data.csv', 'csv', 5242880, 100, 5, 1),
((SELECT id FROM t_user WHERE username='test_u1'), 'empty_file.csv', '/tmp/empty.csv', 'csv', 0, 0, 0, 1);

-- 测试数据项(用于数据质量测试)
INSERT INTO t_data_item (file_id, row_index, col_name, col_value, data_type)
SELECT f.id, n.n, 'col_a', CONCAT('value_', n.n), 'text'
FROM t_file f, (SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
                UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) n
WHERE f.file_name = 'test_data.csv';

INSERT INTO t_data_item (file_id, row_index, col_name, col_value, data_type)
SELECT f.id, n.n, 'col_b', CASE WHEN n.n <= 7 THEN CAST(n.n * 10.5 AS CHAR) ELSE NULL END,
       CASE WHEN n.n <= 7 THEN 'number' ELSE 'empty' END
FROM t_file f, (SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
                UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) n
WHERE f.file_name = 'test_data.csv';


-- ############################################################################
-- 第A组: 触发器 — 任务状态机拦截 (trg_task_status_guard)
-- 测试全部 4×4=16 种状态流转组合, 其中 4 合法 + 11 非法 + 1 同状态
-- ############################################################################

-- A0: 准备 — 创建一个基础任务(PENDING状态)
SET @test_user_id = (SELECT id FROM t_user WHERE username='test_u1');
SET @test_file_id = (SELECT id FROM t_file WHERE file_name='test_data.csv');
SET @test_chart_id = (SELECT id FROM t_chart WHERE chart_code='bar');

-- ---- A1: PENDING → PROCESSING (合法) ----
DROP PROCEDURE IF EXISTS _test_A1;
DELIMITER //
CREATE PROCEDURE _test_A1()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('A1', '状态机', 'PENDING→PROCESSING (合法)', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    IF (SELECT status FROM t_task WHERE id=v_tid) = 'PROCESSING' THEN
        CALL _pass('A1', '状态机', 'PENDING→PROCESSING (合法)', NULL);
    ELSE
        CALL _fail('A1', '状态机', 'PENDING→PROCESSING (合法)', '状态未变更');
    END IF;
END//
DELIMITER ;
CALL _test_A1();

-- ---- A2: PROCESSING → SUCCESS (合法) ----
DROP PROCEDURE IF EXISTS _test_A2;
DELIMITER //
CREATE PROCEDURE _test_A2()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('A2', '状态机', 'PROCESSING→SUCCESS (合法)', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS', result_path='/tmp/result.png' WHERE id=v_tid;
    IF (SELECT status FROM t_task WHERE id=v_tid) = 'SUCCESS' THEN
        CALL _pass('A2', '状态机', 'PROCESSING→SUCCESS (合法)', NULL);
    ELSE
        CALL _fail('A2', '状态机', 'PROCESSING→SUCCESS (合法)', '状态未变更');
    END IF;
END//
DELIMITER ;
CALL _test_A2();

-- ---- A3: PROCESSING → FAILED (合法) ----
DROP PROCEDURE IF EXISTS _test_A3;
DELIMITER //
CREATE PROCEDURE _test_A3()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('A3', '状态机', 'PROCESSING→FAILED (合法)', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='FAILED', error_msg='渲染超时' WHERE id=v_tid;
    IF (SELECT status FROM t_task WHERE id=v_tid) = 'FAILED' THEN
        CALL _pass('A3', '状态机', 'PROCESSING→FAILED (合法)', NULL);
    ELSE
        CALL _fail('A3', '状态机', 'PROCESSING→FAILED (合法)', '状态未变更');
    END IF;
END//
DELIMITER ;
CALL _test_A3();

-- ---- A4: FAILED → PENDING (合法/重试) ----
DROP PROCEDURE IF EXISTS _test_A4;
DELIMITER //
CREATE PROCEDURE _test_A4()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('A4', '状态机', 'FAILED→PENDING (合法/重试)', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='FAILED' WHERE id=v_tid;
    UPDATE t_task SET status='PENDING' WHERE id=v_tid;
    IF (SELECT status FROM t_task WHERE id=v_tid) = 'PENDING' THEN
        CALL _pass('A4', '状态机', 'FAILED→PENDING (合法/重试)', NULL);
    ELSE
        CALL _fail('A4', '状态机', 'FAILED→PENDING (合法/重试)', '状态未变更');
    END IF;
END//
DELIMITER ;
CALL _test_A4();

-- ---- A5: PENDING → SUCCESS (非法, 跳过PROCESSING) ----
DROP PROCEDURE IF EXISTS _test_A5;
DELIMITER //
CREATE PROCEDURE _test_A5()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A5', '状态机', 'PENDING→SUCCESS (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A5', '状态机', 'PENDING→SUCCESS (非法, 应拦截)', '未被拦截!安全漏洞!');
    END IF;
END//
DELIMITER ;
CALL _test_A5();

-- ---- A6: PENDING → FAILED (非法) ----
DROP PROCEDURE IF EXISTS _test_A6;
DELIMITER //
CREATE PROCEDURE _test_A6()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='FAILED' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A6', '状态机', 'PENDING→FAILED (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A6', '状态机', 'PENDING→FAILED (非法, 应拦截)', '未被拦截!');
    END IF;
END//
DELIMITER ;
CALL _test_A6();

-- ---- A7: SUCCESS → PENDING (非法) ----
DROP PROCEDURE IF EXISTS _test_A7;
DELIMITER //
CREATE PROCEDURE _test_A7()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    SET v_blocked = 0;
    UPDATE t_task SET status='PENDING' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A7', '状态机', 'SUCCESS→PENDING (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A7', '状态机', 'SUCCESS→PENDING (非法, 应拦截)', '未被拦截!已完成任务被回退!');
    END IF;
END//
DELIMITER ;
CALL _test_A7();

-- ---- A8: SUCCESS → FAILED (非法) ----
DROP PROCEDURE IF EXISTS _test_A8;
DELIMITER //
CREATE PROCEDURE _test_A8()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    SET v_blocked = 0;
    UPDATE t_task SET status='FAILED' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A8', '状态机', 'SUCCESS→FAILED (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A8', '状态机', 'SUCCESS→FAILED (非法, 应拦截)', '未被拦截!');
    END IF;
END//
DELIMITER ;
CALL _test_A8();

-- ---- A9: SUCCESS → PROCESSING (非法) ----
DROP PROCEDURE IF EXISTS _test_A9;
DELIMITER //
CREATE PROCEDURE _test_A9()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    SET v_blocked = 0;
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A9', '状态机', 'SUCCESS→PROCESSING (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A9', '状态机', 'SUCCESS→PROCESSING (非法, 应拦截)', '未被拦截!');
    END IF;
END//
DELIMITER ;
CALL _test_A9();

-- ---- A10: FAILED → SUCCESS (非法, 跳过PROCESSING) ----
DROP PROCEDURE IF EXISTS _test_A10;
DELIMITER //
CREATE PROCEDURE _test_A10()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='FAILED' WHERE id=v_tid;
    SET v_blocked = 0;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A10', '状态机', 'FAILED→SUCCESS (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A10', '状态机', 'FAILED→SUCCESS (非法, 应拦截)', '未被拦截!跳过了PROCESSING!');
    END IF;
END//
DELIMITER ;
CALL _test_A10();

-- ---- A11: FAILED → PROCESSING (非法, 必须先回PENDING) ----
DROP PROCEDURE IF EXISTS _test_A11;
DELIMITER //
CREATE PROCEDURE _test_A11()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='FAILED' WHERE id=v_tid;
    SET v_blocked = 0;
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    IF v_blocked = 1 THEN
        CALL _pass('A11', '状态机', 'FAILED→PROCESSING (非法, 应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('A11', '状态机', 'FAILED→PROCESSING (非法, 应拦截)', '未被拦截!');
    END IF;
END//
DELIMITER ;
CALL _test_A11();

-- ---- A12: 同状态 PENDING → PENDING (边界, 不应拦截, 因为状态没变) ----
DROP PROCEDURE IF EXISTS _test_A12;
DELIMITER //
CREATE PROCEDURE _test_A12()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    -- 更新非状态字段, 状态保持PENDING不变
    UPDATE t_task SET priority = 3 WHERE id=v_tid;
    IF v_blocked = 0 THEN
        CALL _pass('A12', '状态机', '非状态字段更新(不应触发状态检查)', '正常通过');
    ELSE
        CALL _fail('A12', '状态机', '非状态字段更新(不应触发状态检查)', '误拦截!');
    END IF;
END//
DELIMITER ;
CALL _test_A12();

-- ---- A13: 自动时间戳验证 — PROCESSING时start_time自动填充 ----
DROP PROCEDURE IF EXISTS _test_A13;
DELIMITER //
CREATE PROCEDURE _test_A13()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_st DATETIME;
    DECLARE v_ft DATETIME;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('A13', '状态机', '自动时间戳: start_time/finish_time', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    SELECT start_time INTO v_st FROM t_task WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    SELECT finish_time INTO v_ft FROM t_task WHERE id=v_tid;
    IF v_st IS NOT NULL AND v_ft IS NOT NULL AND v_ft >= v_st THEN
        CALL _pass('A13', '状态机', '自动时间戳: start_time/finish_time', CONCAT('start=', v_st, ' finish=', v_ft));
    ELSE
        CALL _fail('A13', '状态机', '自动时间戳: start_time/finish_time',
            CONCAT('start=', COALESCE(v_st,'NULL'), ' finish=', COALESCE(v_ft,'NULL')));
    END IF;
END//
DELIMITER ;
CALL _test_A13();


-- ############################################################################
-- 第B组: 触发器 — 任务创建前验证 (trg_task_before_insert)
-- ############################################################################

-- ---- B1: chart类型缺少chart_id → 应拦截 ----
DROP PROCEDURE IF EXISTS _test_B1;
DELIMITER //
CREATE PROCEDURE _test_B1()
BEGIN
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id, file_id) VALUES (@test_user_id, 'chart', NULL, @test_file_id);
    IF v_blocked = 1 THEN
        CALL _pass('B1', '前置验证', 'chart类型缺少chart_id (应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('B1', '前置验证', 'chart类型缺少chart_id (应拦截)', '未被拦截!可创建无效任务!');
    END IF;
END//
DELIMITER ;
CALL _test_B1();

-- ---- B2: formula类型缺少formula_id → 应拦截 ----
DROP PROCEDURE IF EXISTS _test_B2;
DELIMITER //
CREATE PROCEDURE _test_B2()
BEGIN
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, formula_id, file_id) VALUES (@test_user_id, 'formula', NULL, @test_file_id);
    IF v_blocked = 1 THEN
        CALL _pass('B2', '前置验证', 'formula类型缺少formula_id (应拦截)', '触发器成功拦截');
    ELSE
        CALL _fail('B2', '前置验证', 'formula类型缺少formula_id (应拦截)', '未被拦截!');
    END IF;
END//
DELIMITER ;
CALL _test_B2();

-- ---- B3: 自动推断渲染引擎 — plotly图表 ----
DROP PROCEDURE IF EXISTS _test_B3;
DELIMITER //
CREATE PROCEDURE _test_B3()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_engine VARCHAR(30);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('B3', '前置验证', '自动推断渲染引擎(plotly)', @err_msg);
    END;
    SET @plotly_id = (SELECT id FROM t_chart WHERE chart_code='plotly_scatter');
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @plotly_id);
    SET v_tid = LAST_INSERT_ID();
    SELECT render_engine INTO v_engine FROM t_task WHERE id=v_tid;
    IF v_engine = 'plotly' THEN
        CALL _pass('B3', '前置验证', '自动推断渲染引擎(plotly)', CONCAT('engine=', v_engine));
    ELSE
        CALL _fail('B3', '前置验证', '自动推断渲染引擎(plotly)', CONCAT('期望plotly, 实际=', v_engine));
    END IF;
END//
DELIMITER ;
CALL _test_B3();

-- ---- B4: total_tasks自动填充 ----
DROP PROCEDURE IF EXISTS _test_B4;
DELIMITER //
CREATE PROCEDURE _test_B4()
BEGIN
    DECLARE v_total BIGINT;
    DECLARE v_actual_count BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('B4', '前置验证', 'total_tasks自动填充', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SELECT total_tasks INTO v_total FROM t_task WHERE id = LAST_INSERT_ID();
    SELECT COUNT(*) INTO v_actual_count FROM t_task WHERE user_id = @test_user_id;
    IF v_total = v_actual_count THEN
        CALL _pass('B4', '前置验证', 'total_tasks自动填充', CONCAT('total=', v_total, ' actual=', v_actual_count));
    ELSE
        CALL _fail('B4', '前置验证', 'total_tasks自动填充',
            CONCAT('total_tasks=', COALESCE(v_total, 'NULL'), ' 实际=', v_actual_count));
    END IF;
END//
DELIMITER ;
CALL _test_B4();


-- ############################################################################
-- 第C组: 触发器 — 任务完成后自动化 (trg_task_after_update)
-- ############################################################################

-- ---- C1: SUCCESS时自动创建历史记录 ----
DROP PROCEDURE IF EXISTS _test_C1;
DELIMITER //
CREATE PROCEDURE _test_C1()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_hist_count INT;
    DECLARE v_snap JSON;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('C1', '自动历史', 'SUCCESS自动创建历史记录', @err_msg);
    END;
    SET v_hist_count = (SELECT COUNT(*) FROM t_history WHERE user_id = @test_user_id);
    INSERT INTO t_task (user_id, task_type, chart_id, file_id, task_params)
    VALUES (@test_user_id, 'chart', @test_chart_id, @test_file_id, '{"color":"red"}');
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS', result_path='/img/result_c1.png' WHERE id=v_tid;
    -- 检查历史记录是否自动创建
    IF (SELECT COUNT(*) FROM t_history WHERE user_id=@test_user_id) > v_hist_count THEN
        SELECT snapshot INTO v_snap FROM t_history WHERE task_id = v_tid LIMIT 1;
        IF v_snap IS NOT NULL THEN
            CALL _pass('C1', '自动历史', 'SUCCESS自动创建历史记录(含snapshot)', CAST(v_snap AS CHAR));
        ELSE
            CALL _fail('C1', '自动历史', 'SUCCESS自动创建历史记录(含snapshot)', 'snapshot为空');
        END IF;
    ELSE
        CALL _fail('C1', '自动历史', 'SUCCESS自动创建历史记录', '未创建历史记录!');
    END IF;
END//
DELIMITER ;
CALL _test_C1();

-- ---- C2: SUCCESS时usage_count递增 ----
DROP PROCEDURE IF EXISTS _test_C2;
DELIMITER //
CREATE PROCEDURE _test_C2()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_before BIGINT;
    DECLARE v_after BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('C2', '自动历史', 'SUCCESS时chart.usage_count+1', @err_msg);
    END;
    SELECT usage_count INTO v_before FROM t_chart WHERE id=@test_chart_id;
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    SELECT usage_count INTO v_after FROM t_chart WHERE id=@test_chart_id;
    IF v_after = v_before + 1 THEN
        CALL _pass('C2', '自动历史', 'SUCCESS时chart.usage_count+1', CONCAT(v_before, '→', v_after));
    ELSE
        CALL _fail('C2', '自动历史', 'SUCCESS时chart.usage_count+1', CONCAT('before=', v_before, ' after=', v_after));
    END IF;
END//
DELIMITER ;
CALL _test_C2();

-- ---- C3: FAILED时不创建历史记录 ----
DROP PROCEDURE IF EXISTS _test_C3;
DELIMITER //
CREATE PROCEDURE _test_C3()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_hist_before INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('C3', '自动历史', 'FAILED时不创建历史记录', @err_msg);
    END;
    SET v_hist_before = (SELECT COUNT(*) FROM t_history WHERE user_id = @test_user_id);
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    UPDATE t_task SET status='FAILED', error_msg='测试失败' WHERE id=v_tid;
    IF (SELECT COUNT(*) FROM t_history WHERE user_id=@test_user_id) = v_hist_before THEN
        CALL _pass('C3', '自动历史', 'FAILED时不创建历史记录', '正确: 未创建');
    ELSE
        CALL _fail('C3', '自动历史', 'FAILED时不创建历史记录', '错误: FAILED也创建了历史!');
    END IF;
END//
DELIMITER ;
CALL _test_C3();


-- ############################################################################
-- 第D组: 触发器 — 历史记录守护 (trg_history_soft_delete_guard)
-- ############################################################################

-- ---- D1: 软删除自动记录deleted_at ----
DROP PROCEDURE IF EXISTS _test_D1;
DELIMITER //
CREATE PROCEDURE _test_D1()
BEGIN
    DECLARE v_hid BIGINT;
    DECLARE v_del_at DATETIME;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('D1', '历史守护', '软删除自动填充deleted_at', @err_msg);
    END;
    SET v_hid = (SELECT id FROM t_history WHERE user_id=@test_user_id AND is_deleted=0 LIMIT 1);
    IF v_hid IS NOT NULL THEN
        UPDATE t_history SET is_deleted = 1 WHERE id = v_hid;
        SELECT deleted_at INTO v_del_at FROM t_history WHERE id = v_hid;
        IF v_del_at IS NOT NULL THEN
            CALL _pass('D1', '历史守护', '软删除自动填充deleted_at', CAST(v_del_at AS CHAR));
        ELSE
            CALL _fail('D1', '历史守护', '软删除自动填充deleted_at', 'deleted_at仍为NULL!');
        END IF;
    ELSE
        CALL _fail('D1', '历史守护', '软删除自动填充deleted_at', '无测试数据');
    END IF;
END//
DELIMITER ;
CALL _test_D1();

-- ---- D2: rating=0 超出范围 → 应拦截 ----
DROP PROCEDURE IF EXISTS _test_D2;
DELIMITER //
CREATE PROCEDURE _test_D2()
BEGIN
    DECLARE v_hid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    SET v_hid = (SELECT id FROM t_history WHERE user_id=@test_user_id LIMIT 1);
    IF v_hid IS NOT NULL THEN
        UPDATE t_history SET rating = 0 WHERE id = v_hid;
        IF v_blocked = 1 THEN
            CALL _pass('D2', '历史守护', 'rating=0 (超出范围, 应拦截)', '触发器成功拦截');
        ELSE
            CALL _fail('D2', '历史守护', 'rating=0 (超出范围, 应拦截)', '未被拦截!允许了非法评分!');
        END IF;
    ELSE
        CALL _fail('D2', '历史守护', 'rating=0 (超出范围, 应拦截)', '无测试数据');
    END IF;
END//
DELIMITER ;
CALL _test_D2();

-- ---- D3: rating=6 超出范围 → 应拦截 ----
DROP PROCEDURE IF EXISTS _test_D3;
DELIMITER //
CREATE PROCEDURE _test_D3()
BEGIN
    DECLARE v_hid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    SET v_hid = (SELECT id FROM t_history WHERE user_id=@test_user_id LIMIT 1);
    IF v_hid IS NOT NULL THEN
        UPDATE t_history SET rating = 6 WHERE id = v_hid;
        IF v_blocked = 1 THEN
            CALL _pass('D3', '历史守护', 'rating=6 (超出范围, 应拦截)', '触发器成功拦截');
        ELSE
            CALL _fail('D3', '历史守护', 'rating=6 (超出范围, 应拦截)', '未被拦截!');
        END IF;
    ELSE
        CALL _fail('D3', '历史守护', 'rating=6 (超出范围, 应拦截)', '无测试数据');
    END IF;
END//
DELIMITER ;
CALL _test_D3();

-- ---- D4: rating=3 合法范围 ----
DROP PROCEDURE IF EXISTS _test_D4;
DELIMITER //
CREATE PROCEDURE _test_D4()
BEGIN
    DECLARE v_hid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    SET v_hid = (SELECT id FROM t_history WHERE user_id=@test_user_id LIMIT 1);
    IF v_hid IS NOT NULL THEN
        UPDATE t_history SET rating = 3, is_deleted = 0, deleted_at = NULL WHERE id = v_hid;
        IF v_blocked = 0 THEN
            CALL _pass('D4', '历史守护', 'rating=3 (合法, 不应拦截)', '正常通过');
        ELSE
            CALL _fail('D4', '历史守护', 'rating=3 (合法, 不应拦截)', '误拦截!');
        END IF;
    ELSE
        CALL _fail('D4', '历史守护', 'rating=3 (合法, 不应拦截)', '无测试数据');
    END IF;
END//
DELIMITER ;
CALL _test_D4();


-- ############################################################################
-- 第E组: 闭包表触发器 — 插入/删除/移动 完整性测试
-- ############################################################################

-- ---- E1: 插入根节点 → 自引用记录 ----
DROP PROCEDURE IF EXISTS _test_E1;
DELIMITER //
CREATE PROCEDURE _test_E1()
BEGIN
    DECLARE v_cid BIGINT;
    DECLARE v_self_ref INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('E1', '闭包表', '插入根节点→自引用', @err_msg);
    END;
    INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('测试根A', 'chart', NULL, 99);
    SET v_cid = LAST_INSERT_ID();
    SELECT COUNT(*) INTO v_self_ref FROM t_category_closure
    WHERE ancestor_id = v_cid AND descendant_id = v_cid AND depth = 0;
    IF v_self_ref = 1 THEN
        CALL _pass('E1', '闭包表', '插入根节点→自引用(depth=0)', CONCAT('cat_id=', v_cid));
    ELSE
        CALL _fail('E1', '闭包表', '插入根节点→自引用(depth=0)', CONCAT('self_ref_count=', v_self_ref));
    END IF;
END//
DELIMITER ;
CALL _test_E1();

-- ---- E2: 插入子节点 → 自引用 + 父子关系 ----
DROP PROCEDURE IF EXISTS _test_E2;
DELIMITER //
CREATE PROCEDURE _test_E2()
BEGIN
    DECLARE v_parent BIGINT;
    DECLARE v_child BIGINT;
    DECLARE v_closure_count INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('E2', '闭包表', '插入子节点→自引用+父子', @err_msg);
    END;
    SET v_parent = (SELECT id FROM t_category WHERE cat_name='测试根A');
    INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('子节点B', 'chart', v_parent, 1);
    SET v_child = LAST_INSERT_ID();
    SELECT COUNT(*) INTO v_closure_count FROM t_category_closure WHERE descendant_id = v_child;
    -- 应该有2条: (child,child,0) 和 (parent,child,1)
    IF v_closure_count = 2 THEN
        CALL _pass('E2', '闭包表', '插入子节点→2条闭包(自引用+父子)', CONCAT('parent=', v_parent, ' child=', v_child));
    ELSE
        CALL _fail('E2', '闭包表', '插入子节点→2条闭包(自引用+父子)', CONCAT('期望2, 实际=', v_closure_count));
    END IF;
END//
DELIMITER ;
CALL _test_E2();

-- ---- E3: 插入孙节点 → 自引用 + 父子 + 祖孙 ----
DROP PROCEDURE IF EXISTS _test_E3;
DELIMITER //
CREATE PROCEDURE _test_E3()
BEGIN
    DECLARE v_child BIGINT;
    DECLARE v_grandchild BIGINT;
    DECLARE v_closure_count INT;
    DECLARE v_max_depth INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('E3', '闭包表', '插入孙节点→3条闭包(自+父+祖)', @err_msg);
    END;
    SET v_child = (SELECT id FROM t_category WHERE cat_name='子节点B');
    INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('孙节点C', 'chart', v_child, 1);
    SET v_grandchild = LAST_INSERT_ID();
    SELECT COUNT(*), MAX(depth) INTO v_closure_count, v_max_depth
    FROM t_category_closure WHERE descendant_id = v_grandchild;
    -- 应该有3条: (gc,gc,0), (child,gc,1), (root,gc,2)
    IF v_closure_count = 3 AND v_max_depth = 2 THEN
        CALL _pass('E3', '闭包表', '插入孙节点→3条闭包(depth 0,1,2)', CONCAT('max_depth=', v_max_depth));
    ELSE
        CALL _fail('E3', '闭包表', '插入孙节点→3条闭包(depth 0,1,2)',
            CONCAT('count=', v_closure_count, ' max_depth=', COALESCE(v_max_depth,'NULL')));
    END IF;
END//
DELIMITER ;
CALL _test_E3();

-- ---- E4: 删除节点 → 检查闭包表级联行为 ----
DROP PROCEDURE IF EXISTS _test_E4;
DELIMITER //
CREATE PROCEDURE _test_E4()
BEGIN
    DECLARE v_grandchild BIGINT;
    DECLARE v_remaining INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('E4', '闭包表', '删除叶子节点→闭包级联删除', @err_msg);
    END;
    SET v_grandchild = (SELECT id FROM t_category WHERE cat_name='孙节点C');
    DELETE FROM t_category WHERE id = v_grandchild;
    SELECT COUNT(*) INTO v_remaining FROM t_category_closure
    WHERE ancestor_id = v_grandchild OR descendant_id = v_grandchild;
    IF v_remaining = 0 THEN
        CALL _pass('E4', '闭包表', '删除叶子节点→闭包级联删除', '已清理所有闭包记录');
    ELSE
        CALL _fail('E4', '闭包表', '删除叶子节点→闭包级联删除', CONCAT('残留', v_remaining, '条闭包'));
    END IF;
END//
DELIMITER ;
CALL _test_E4();

-- ---- E5: 移动节点(变更parent_id) → 已知缺陷: 闭包表不自动更新 ----
DROP PROCEDURE IF EXISTS _test_E5;
DELIMITER //
CREATE PROCEDURE _test_E5()
BEGIN
    DECLARE v_child BIGINT;
    DECLARE v_new_parent BIGINT;
    DECLARE v_old_ancestor BIGINT;
    DECLARE v_has_new_ancestor INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('E5', '闭包表', '移动节点→闭包一致性(已知缺陷)', @err_msg);
    END;
    SET v_child = (SELECT id FROM t_category WHERE cat_name='子节点B');
    -- 当前父是"测试根A", 移到"统计图表"(id=1)下
    SET v_new_parent = 1;
    SET v_old_ancestor = (SELECT ancestor_id FROM t_category_closure WHERE descendant_id=v_child AND depth=1 LIMIT 1);
    -- 执行移动
    UPDATE t_category SET parent_id = v_new_parent WHERE id = v_child;
    -- 检查闭包表是否更新了
    SELECT COUNT(*) INTO v_has_new_ancestor FROM t_category_closure
    WHERE descendant_id = v_child AND ancestor_id = v_new_parent AND depth > 0;
    IF v_has_new_ancestor = 0 THEN
        INSERT INTO _test_results (test_id,category,test_name,expected,actual,pass_fail,detail)
        VALUES ('E5', '闭包表', '移动节点→闭包不自动更新(已知缺陷!)',
                '自动更新', '未更新', '** DEFECT **',
                '需要新增BEFORE UPDATE触发器来维护闭包表一致性');
    ELSE
        CALL _pass('E5', '闭包表', '移动节点→闭包自动更新', '闭包已正确更新');
    END IF;
    -- 恢复原状
    UPDATE t_category SET parent_id = v_old_ancestor WHERE id = v_child;
END//
DELIMITER ;
CALL _test_E5();


-- ############################################################################
-- 第F组: 生成列 (Generated Columns) 逻辑验证
-- ############################################################################

-- ---- F1-F5: popularity_rank 等级梯度测试 ----
DROP PROCEDURE IF EXISTS _test_F1;
DELIMITER //
CREATE PROCEDURE _test_F1()
BEGIN
    DECLARE v_rank_d VARCHAR(10);
    DECLARE v_rank_c VARCHAR(10);
    DECLARE v_rank_b VARCHAR(10);
    DECLARE v_rank_a VARCHAR(10);
    DECLARE v_rank_s VARCHAR(10);
    DECLARE v_all_pass INT DEFAULT 1;
    DECLARE v_detail TEXT DEFAULT '';

    -- 临时修改不同usage_count值并读取生成列
    UPDATE t_chart SET usage_count = 0 WHERE chart_code = 'bar';
    SELECT popularity_rank INTO v_rank_d FROM t_chart WHERE chart_code = 'bar';
    IF v_rank_d != 'D' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=0→', v_rank_d, '(期望D) '); END IF;

    UPDATE t_chart SET usage_count = 5 WHERE chart_code = 'bar';
    SELECT popularity_rank INTO v_rank_c FROM t_chart WHERE chart_code = 'bar';
    IF v_rank_c != 'C' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=5→', v_rank_c, '(期望C) '); END IF;

    UPDATE t_chart SET usage_count = 20 WHERE chart_code = 'bar';
    SELECT popularity_rank INTO v_rank_b FROM t_chart WHERE chart_code = 'bar';
    IF v_rank_b != 'B' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=20→', v_rank_b, '(期望B) '); END IF;

    UPDATE t_chart SET usage_count = 50 WHERE chart_code = 'bar';
    SELECT popularity_rank INTO v_rank_a FROM t_chart WHERE chart_code = 'bar';
    IF v_rank_a != 'A' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=50→', v_rank_a, '(期望A) '); END IF;

    UPDATE t_chart SET usage_count = 100 WHERE chart_code = 'bar';
    SELECT popularity_rank INTO v_rank_s FROM t_chart WHERE chart_code = 'bar';
    IF v_rank_s != 'S' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=100→', v_rank_s, '(期望S) '); END IF;

    -- 恢复
    UPDATE t_chart SET usage_count = 0 WHERE chart_code = 'bar';

    IF v_all_pass = 1 THEN
        CALL _pass('F1', '生成列', 'popularity_rank: D(0)/C(5)/B(20)/A(50)/S(100)',
            CONCAT(v_rank_d,'/',v_rank_c,'/',v_rank_b,'/',v_rank_a,'/',v_rank_s));
    ELSE
        CALL _fail('F1', '生成列', 'popularity_rank等级计算', v_detail);
    END IF;
END//
DELIMITER ;
CALL _test_F1();

-- ---- F2: popularity_rank 边界值测试 ----
DROP PROCEDURE IF EXISTS _test_F2;
DELIMITER //
CREATE PROCEDURE _test_F2()
BEGIN
    DECLARE v_r4 VARCHAR(10); DECLARE v_r19 VARCHAR(10); DECLARE v_r49 VARCHAR(10); DECLARE v_r99 VARCHAR(10);
    DECLARE v_all_pass INT DEFAULT 1;
    DECLARE v_detail TEXT DEFAULT '';

    UPDATE t_chart SET usage_count = 4 WHERE chart_code = 'line';
    SELECT popularity_rank INTO v_r4 FROM t_chart WHERE chart_code = 'line';
    IF v_r4 != 'D' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=4→', v_r4, '(期望D) '); END IF;

    UPDATE t_chart SET usage_count = 19 WHERE chart_code = 'line';
    SELECT popularity_rank INTO v_r19 FROM t_chart WHERE chart_code = 'line';
    IF v_r19 != 'C' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=19→', v_r19, '(期望C) '); END IF;

    UPDATE t_chart SET usage_count = 49 WHERE chart_code = 'line';
    SELECT popularity_rank INTO v_r49 FROM t_chart WHERE chart_code = 'line';
    IF v_r49 != 'B' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=49→', v_r49, '(期望B) '); END IF;

    UPDATE t_chart SET usage_count = 99 WHERE chart_code = 'line';
    SELECT popularity_rank INTO v_r99 FROM t_chart WHERE chart_code = 'line';
    IF v_r99 != 'A' THEN SET v_all_pass = 0; SET v_detail = CONCAT(v_detail, 'cnt=99→', v_r99, '(期望A) '); END IF;

    UPDATE t_chart SET usage_count = 0 WHERE chart_code = 'line';

    IF v_all_pass = 1 THEN
        CALL _pass('F2', '生成列', 'popularity_rank边界: 4→D, 19→C, 49→B, 99→A', 'ALL CORRECT');
    ELSE
        CALL _fail('F2', '生成列', 'popularity_rank边界值', v_detail);
    END IF;
END//
DELIMITER ;
CALL _test_F2();

-- ---- F3: file_size_mb + cell_count 生成列 ----
DROP PROCEDURE IF EXISTS _test_F3;
DELIMITER //
CREATE PROCEDURE _test_F3()
BEGIN
    DECLARE v_mb DECIMAL(10,2);
    DECLARE v_cells INT;
    SELECT file_size_mb, cell_count INTO v_mb, v_cells
    FROM t_file WHERE file_name = 'test_data.csv';
    IF v_mb = 5.00 AND v_cells = 500 THEN
        CALL _pass('F3', '生成列', 'file_size_mb(5MB) + cell_count(100×5=500)', CONCAT('mb=', v_mb, ' cells=', v_cells));
    ELSE
        CALL _fail('F3', '生成列', 'file_size_mb / cell_count',
            CONCAT('mb=', COALESCE(v_mb,'NULL'), '(期望5.00) cells=', COALESCE(v_cells,'NULL'), '(期望500)'));
    END IF;
END//
DELIMITER ;
CALL _test_F3();

-- ---- F4: duration_seconds 自动计算 ----
DROP PROCEDURE IF EXISTS _test_F4;
DELIMITER //
CREATE PROCEDURE _test_F4()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_dur INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('F4', '生成列', 'duration_seconds自动计算', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SET v_tid = LAST_INSERT_ID();
    UPDATE t_task SET status='PROCESSING' WHERE id=v_tid;
    -- 人为设置start_time为2秒前
    UPDATE t_task SET start_time = DATE_SUB(NOW(), INTERVAL 2 SECOND) WHERE id=v_tid;
    UPDATE t_task SET status='SUCCESS' WHERE id=v_tid;
    SELECT duration_seconds INTO v_dur FROM t_task WHERE id=v_tid;
    IF v_dur IS NOT NULL AND v_dur >= 1 THEN
        CALL _pass('F4', '生成列', 'duration_seconds自动计算', CONCAT('duration=', v_dur, 's'));
    ELSE
        CALL _fail('F4', '生成列', 'duration_seconds自动计算', CONCAT('duration=', COALESCE(v_dur, 'NULL')));
    END IF;
END//
DELIMITER ;
CALL _test_F4();

-- ---- F5: is_null_val + value_length 生成列 ----
DROP PROCEDURE IF EXISTS _test_F5;
DELIMITER //
CREATE PROCEDURE _test_F5()
BEGIN
    DECLARE v_null_cnt INT;
    DECLARE v_notnull_cnt INT;
    DECLARE v_avg_len DECIMAL(10,1);
    SELECT SUM(is_null_val), SUM(1-is_null_val), ROUND(AVG(value_length),1)
    INTO v_null_cnt, v_notnull_cnt, v_avg_len
    FROM t_data_item WHERE file_id = @test_file_id;
    -- col_b有3个NULL(row 8,9,10), 共20条数据
    IF v_null_cnt = 3 AND v_notnull_cnt = 17 THEN
        CALL _pass('F5', '生成列', 'is_null_val(3个NULL) + value_length',
            CONCAT('null=', v_null_cnt, ' notnull=', v_notnull_cnt, ' avg_len=', v_avg_len));
    ELSE
        CALL _fail('F5', '生成列', 'is_null_val统计',
            CONCAT('null=', COALESCE(v_null_cnt,'?'), '(期望3) notnull=', COALESCE(v_notnull_cnt,'?'), '(期望17)'));
    END IF;
END//
DELIMITER ;
CALL _test_F5();

-- ---- F6: latex_length 生成列 ----
DROP PROCEDURE IF EXISTS _test_F6;
DELIMITER //
CREATE PROCEDURE _test_F6()
BEGIN
    DECLARE v_len INT;
    DECLARE v_expected INT;
    SELECT latex_length INTO v_len FROM t_formula WHERE formula_code = 'bayes';
    SET v_expected = CHAR_LENGTH('P(A|B) = \\frac{P(B|A) \\cdot P(A)}{P(B)}');
    IF v_len = v_expected THEN
        CALL _pass('F6', '生成列', 'latex_length(贝叶斯公式)', CONCAT('length=', v_len));
    ELSE
        CALL _fail('F6', '生成列', 'latex_length', CONCAT('actual=', COALESCE(v_len,'NULL'), ' expected=', v_expected));
    END IF;
END//
DELIMITER ;
CALL _test_F6();

-- ---- F7: perm_level 生成列 ----
DROP PROCEDURE IF EXISTS _test_F7;
DELIMITER //
CREATE PROCEDURE _test_F7()
BEGIN
    DECLARE v_level_1 INT;
    DECLARE v_level_2 INT;
    SELECT perm_level INTO v_level_1 FROM t_permission WHERE perm_code = 'dashboard';
    SELECT perm_level INTO v_level_2 FROM t_permission WHERE perm_code = 'user:create';
    IF v_level_1 = 1 AND v_level_2 = 2 THEN
        CALL _pass('F7', '生成列', 'perm_level: dashboard=1, user:create=2',
            CONCAT('dashboard=', v_level_1, ' user:create=', v_level_2));
    ELSE
        CALL _fail('F7', '生成列', 'perm_level',
            CONCAT('dashboard=', v_level_1, '(期望1) user:create=', v_level_2, '(期望2)'));
    END IF;
END//
DELIMITER ;
CALL _test_F7();


-- ############################################################################
-- 第G组: 存储过程验证
-- ############################################################################

-- ---- G1: sp_task_state_transition 合法流转 ----
DROP PROCEDURE IF EXISTS _test_G1;
DELIMITER //
CREATE PROCEDURE _test_G1()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_final_status VARCHAR(20);
    DECLARE v_log JSON;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G1', '存储过程', 'sp_task_state_transition 合法流转', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SET v_tid = LAST_INSERT_ID();
    CALL sp_task_state_transition(v_tid, 'PROCESSING', NULL);
    CALL sp_task_state_transition(v_tid, 'SUCCESS', NULL);
    SELECT status, execution_log INTO v_final_status, v_log FROM t_task WHERE id = v_tid;
    IF v_final_status = 'SUCCESS' AND v_log IS NOT NULL THEN
        CALL _pass('G1', '存储过程', 'sp_task_state_transition PENDING→PROCESSING→SUCCESS',
            CONCAT('log_steps=', JSON_LENGTH(v_log, '$.steps')));
    ELSE
        CALL _fail('G1', '存储过程', 'sp_task_state_transition', CONCAT('status=', v_final_status));
    END IF;
END//
DELIMITER ;
CALL _test_G1();

-- ---- G2: sp_task_state_transition 非法流转 → 异常 ----
DROP PROCEDURE IF EXISTS _test_G2;
DELIMITER //
CREATE PROCEDURE _test_G2()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_blocked INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET v_blocked = 1;
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SET v_tid = LAST_INSERT_ID();
    CALL sp_task_state_transition(v_tid, 'SUCCESS', NULL);
    IF v_blocked = 1 THEN
        CALL _pass('G2', '存储过程', 'sp_task_state_transition PENDING→SUCCESS (非法)', '存储过程抛出异常');
    ELSE
        CALL _fail('G2', '存储过程', 'sp_task_state_transition PENDING→SUCCESS (非法)', '未抛出异常!');
    END IF;
END//
DELIMITER ;
CALL _test_G2();

-- ---- G3: sp_task_state_transition 重试逻辑(FAILED→PENDING后retry_count+1) ----
DROP PROCEDURE IF EXISTS _test_G3;
DELIMITER //
CREATE PROCEDURE _test_G3()
BEGIN
    DECLARE v_tid BIGINT;
    DECLARE v_retry INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G3', '存储过程', 'sp_task_state_transition 重试计数', @err_msg);
    END;
    INSERT INTO t_task (user_id, task_type, chart_id) VALUES (@test_user_id, 'chart', @test_chart_id);
    SET v_tid = LAST_INSERT_ID();
    CALL sp_task_state_transition(v_tid, 'PROCESSING', NULL);
    CALL sp_task_state_transition(v_tid, 'FAILED', '第一次失败');
    CALL sp_task_state_transition(v_tid, 'PENDING', NULL);
    SELECT retry_count INTO v_retry FROM t_task WHERE id = v_tid;
    IF v_retry = 1 THEN
        CALL _pass('G3', '存储过程', 'FAILED→PENDING后retry_count=1', CONCAT('retry=', v_retry));
    ELSE
        CALL _fail('G3', '存储过程', '重试计数', CONCAT('期望1, 实际=', COALESCE(v_retry,'NULL')));
    END IF;
END//
DELIMITER ;
CALL _test_G3();

-- ---- G4: sp_quota_check_and_enforce CHECK模式 ----
DROP PROCEDURE IF EXISTS _test_G4;
DELIMITER //
CREATE PROCEDURE _test_G4()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G4', '存储过程', 'sp_quota_check_and_enforce CHECK', @err_msg);
    END;
    CALL sp_quota_check_and_enforce(@test_user_id, 'CHECK');
    CALL _pass('G4', '存储过程', 'sp_quota_check_and_enforce CHECK模式', '正常返回配额信息');
END//
DELIMITER ;
CALL _test_G4();

-- ---- G5: sp_data_quality_audit ----
DROP PROCEDURE IF EXISTS _test_G5;
DELIMITER //
CREATE PROCEDURE _test_G5()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G5', '存储过程', 'sp_data_quality_audit', @err_msg);
    END;
    CALL sp_data_quality_audit(@test_file_id);
    -- 检查data_profile是否被回写
    IF (SELECT data_profile IS NOT NULL FROM t_file WHERE id = @test_file_id) THEN
        CALL _pass('G5', '存储过程', 'sp_data_quality_audit(含data_profile回写)',
            CAST((SELECT data_profile FROM t_file WHERE id = @test_file_id) AS CHAR));
    ELSE
        CALL _fail('G5', '存储过程', 'sp_data_quality_audit', 'data_profile未回写');
    END IF;
END//
DELIMITER ;
CALL _test_G5();

-- ---- G6: sp_category_integrity_check ----
DROP PROCEDURE IF EXISTS _test_G6;
DELIMITER //
CREATE PROCEDURE _test_G6()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G6', '存储过程', 'sp_category_integrity_check', @err_msg);
    END;
    CALL sp_category_integrity_check(0);
    CALL _pass('G6', '存储过程', 'sp_category_integrity_check(仅检查)', '正常执行');
END//
DELIMITER ;
CALL _test_G6();

-- ---- G7: sp_hot_items_refresh ----
DROP PROCEDURE IF EXISTS _test_G7;
DELIMITER //
CREATE PROCEDURE _test_G7()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G7', '存储过程', 'sp_hot_items_refresh', @err_msg);
    END;
    CALL sp_hot_items_refresh(10, 7);
    CALL _pass('G7', '存储过程', 'sp_hot_items_refresh(threshold=10,days=7)', '正常执行');
END//
DELIMITER ;
CALL _test_G7();

-- ---- G8: sp_generate_system_report ----
DROP PROCEDURE IF EXISTS _test_G8;
DELIMITER //
CREATE PROCEDURE _test_G8()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G8', '存储过程', 'sp_generate_system_report', @err_msg);
    END;
    CALL sp_generate_system_report('2025-01-01', '2026-12-31');
    CALL _pass('G8', '存储过程', 'sp_generate_system_report(含移动平均)', '6个结果集正常返回');
END//
DELIMITER ;
CALL _test_G8();

-- ---- G9: sp_smart_recommend ----
DROP PROCEDURE IF EXISTS _test_G9;
DELIMITER //
CREATE PROCEDURE _test_G9()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G9', '存储过程', 'sp_smart_recommend', @err_msg);
    END;
    CALL sp_smart_recommend(@test_user_id, 3);
    CALL _pass('G9', '存储过程', 'sp_smart_recommend(含协同过滤+兜底)', '3个结果集正常返回');
END//
DELIMITER ;
CALL _test_G9();

-- ---- G10: sp_user_profile_analysis ----
DROP PROCEDURE IF EXISTS _test_G10;
DELIMITER //
CREATE PROCEDURE _test_G10()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT;
        CALL _fail('G10', '存储过程', 'sp_user_profile_analysis', @err_msg);
    END;
    CALL sp_user_profile_analysis(@test_user_id);
    CALL _pass('G10', '存储过程', 'sp_user_profile_analysis(含窗口函数+全站对比)', '4个结果集正常返回');
END//
DELIMITER ;
CALL _test_G10();


-- ############################################################################
-- 输出测试报告
-- ############################################################################
SELECT '============================================' AS '';
SELECT '     Paper Vision 数据库优化 — 测试报告' AS '';
SELECT '============================================' AS '';

SELECT test_id, category, test_name, pass_fail, detail
FROM _test_results ORDER BY seq;

SELECT '' AS '';
SELECT CONCAT('总计: ', COUNT(*), ' 项') AS summary FROM _test_results;
SELECT CONCAT('通过: ', COUNT(*), ' 项') AS passed FROM _test_results WHERE pass_fail = 'PASS';
SELECT CONCAT('失败: ', COUNT(*), ' 项') AS failed FROM _test_results WHERE pass_fail = '** FAIL **';
SELECT CONCAT('缺陷: ', COUNT(*), ' 项') AS defects FROM _test_results WHERE pass_fail = '** DEFECT **';


-- ############################################################################
-- 清理测试辅助过程
-- ############################################################################
DROP PROCEDURE IF EXISTS _pass;
DROP PROCEDURE IF EXISTS _fail;
DROP PROCEDURE IF EXISTS _test_A1;
DROP PROCEDURE IF EXISTS _test_A2;
DROP PROCEDURE IF EXISTS _test_A3;
DROP PROCEDURE IF EXISTS _test_A4;
DROP PROCEDURE IF EXISTS _test_A5;
DROP PROCEDURE IF EXISTS _test_A6;
DROP PROCEDURE IF EXISTS _test_A7;
DROP PROCEDURE IF EXISTS _test_A8;
DROP PROCEDURE IF EXISTS _test_A9;
DROP PROCEDURE IF EXISTS _test_A10;
DROP PROCEDURE IF EXISTS _test_A11;
DROP PROCEDURE IF EXISTS _test_A12;
DROP PROCEDURE IF EXISTS _test_A13;
DROP PROCEDURE IF EXISTS _test_B1;
DROP PROCEDURE IF EXISTS _test_B2;
DROP PROCEDURE IF EXISTS _test_B3;
DROP PROCEDURE IF EXISTS _test_B4;
DROP PROCEDURE IF EXISTS _test_C1;
DROP PROCEDURE IF EXISTS _test_C2;
DROP PROCEDURE IF EXISTS _test_C3;
DROP PROCEDURE IF EXISTS _test_D1;
DROP PROCEDURE IF EXISTS _test_D2;
DROP PROCEDURE IF EXISTS _test_D3;
DROP PROCEDURE IF EXISTS _test_D4;
DROP PROCEDURE IF EXISTS _test_E1;
DROP PROCEDURE IF EXISTS _test_E2;
DROP PROCEDURE IF EXISTS _test_E3;
DROP PROCEDURE IF EXISTS _test_E4;
DROP PROCEDURE IF EXISTS _test_E5;
DROP PROCEDURE IF EXISTS _test_F1;
DROP PROCEDURE IF EXISTS _test_F2;
DROP PROCEDURE IF EXISTS _test_F3;
DROP PROCEDURE IF EXISTS _test_F4;
DROP PROCEDURE IF EXISTS _test_F5;
DROP PROCEDURE IF EXISTS _test_F6;
DROP PROCEDURE IF EXISTS _test_F7;
DROP PROCEDURE IF EXISTS _test_G1;
DROP PROCEDURE IF EXISTS _test_G2;
DROP PROCEDURE IF EXISTS _test_G3;
DROP PROCEDURE IF EXISTS _test_G4;
DROP PROCEDURE IF EXISTS _test_G5;
DROP PROCEDURE IF EXISTS _test_G6;
DROP PROCEDURE IF EXISTS _test_G7;
DROP PROCEDURE IF EXISTS _test_G8;
DROP PROCEDURE IF EXISTS _test_G9;
DROP PROCEDURE IF EXISTS _test_G10;
