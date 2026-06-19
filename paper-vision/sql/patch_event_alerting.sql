-- ============================================================================================
-- Paper Vision — Event Scheduler 增强补丁
-- 增强: 巡检告警(写入admin.profile JSON) · 错误处理 · 执行日志
-- ============================================================================================
USE paper_vision;

-- ============================================================
-- 辅助过程: 将告警信息写入管理员用户的 profile JSON
-- 不新增表, 利用 t_user.profile 的 "system_alerts" 字段
-- ============================================================
DROP PROCEDURE IF EXISTS sp_write_alert;
DELIMITER //
CREATE PROCEDURE sp_write_alert(IN p_source VARCHAR(50), IN p_level VARCHAR(10), IN p_message TEXT)
BEGIN
    DECLARE v_admin_id BIGINT;
    SELECT id INTO v_admin_id FROM t_user WHERE username = 'admin' LIMIT 1;

    IF v_admin_id IS NOT NULL THEN
        UPDATE t_user SET profile = JSON_SET(
            COALESCE(profile, '{}'),
            '$.system_alerts',
            JSON_ARRAY_APPEND(
                COALESCE(JSON_EXTRACT(profile, '$.system_alerts'), JSON_ARRAY()),
                '$',
                JSON_OBJECT(
                    'time',    DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s'),
                    'source',  p_source,
                    'level',   p_level,
                    'message', p_message
                )
            ),
            '$.last_alert_time', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s')
        ) WHERE id = v_admin_id;
    END IF;
END//
DELIMITER ;

-- ============================================================
-- 替换事件: 每日热点刷新 + 告警
-- ============================================================
DROP EVENT IF EXISTS evt_daily_hot_refresh;
DELIMITER //
CREATE EVENT evt_daily_hot_refresh
ON SCHEDULE EVERY 1 DAY
STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 02:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT '每日凌晨刷新热点 + 执行巡检'
DO
BEGIN
    DECLARE v_err_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT;
        CALL sp_write_alert('evt_daily_hot_refresh', 'ERROR', v_err_msg);
    END;

    CALL sp_hot_items_refresh(10, 7);

    CALL sp_write_alert('evt_daily_hot_refresh', 'INFO', '热点刷新完成');
END//
DELIMITER ;

-- ============================================================
-- 替换事件: 每周完整性巡检 + 告警
-- ============================================================
DROP EVENT IF EXISTS evt_weekly_integrity_check;
DELIMITER //
CREATE EVENT evt_weekly_integrity_check
ON SCHEDULE EVERY 1 WEEK
STARTS CONCAT(CURDATE() + INTERVAL (7 - WEEKDAY(CURDATE())) DAY, ' 03:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT '每周闭包表完整性巡检 + 自动修复 + 告警'
DO
BEGIN
    DECLARE v_missing INT DEFAULT 0;
    DECLARE v_orphan INT DEFAULT 0;
    DECLARE v_err_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT;
        CALL sp_write_alert('evt_weekly_integrity_check', 'ERROR', v_err_msg);
    END;

    SELECT COUNT(*) INTO v_missing FROM t_category c
    WHERE NOT EXISTS (
        SELECT 1 FROM t_category_closure cc
        WHERE cc.ancestor_id = c.id AND cc.descendant_id = c.id AND cc.depth = 0
    );

    SELECT COUNT(*) INTO v_orphan FROM t_category_closure cc
    WHERE NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.ancestor_id)
       OR NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.descendant_id);

    IF v_missing > 0 OR v_orphan > 0 THEN
        CALL sp_category_integrity_check(1);
        CALL sp_write_alert('evt_weekly_integrity_check', 'WARN',
            CONCAT('发现并修复问题: 缺失自引用=', v_missing, ', 孤儿闭包=', v_orphan));
    ELSE
        CALL sp_write_alert('evt_weekly_integrity_check', 'INFO', '闭包表完整性正常');
    END IF;
END//
DELIMITER ;

-- ============================================================
-- 替换事件: 每日用户状态刷新 + 活跃度告警
-- ============================================================
DROP EVENT IF EXISTS evt_daily_user_stats_refresh;
DELIMITER //
CREATE EVENT evt_daily_user_stats_refresh
ON SCHEDULE EVERY 1 DAY
STARTS CONCAT(CURDATE() + INTERVAL 1 DAY, ' 01:00:00')
ON COMPLETION PRESERVE ENABLE
COMMENT '每日更新用户账龄/活跃状态 + 活跃度告警'
DO
BEGIN
    DECLARE v_total_users INT;
    DECLARE v_active_users INT;
    DECLARE v_err_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT;
        CALL sp_write_alert('evt_daily_user_stats_refresh', 'ERROR', v_err_msg);
    END;

    UPDATE t_user SET
        account_age_days = DATEDIFF(CURDATE(), DATE(create_time)),
        is_active = CASE
            WHEN status = 1 AND last_login_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1
            ELSE 0
        END;

    SELECT COUNT(*), SUM(is_active) INTO v_total_users, v_active_users FROM t_user;

    IF v_active_users * 100.0 / NULLIF(v_total_users, 0) < 20 THEN
        CALL sp_write_alert('evt_daily_user_stats_refresh', 'WARN',
            CONCAT('活跃率低于20%! 活跃:', v_active_users, '/', v_total_users));
    ELSE
        CALL sp_write_alert('evt_daily_user_stats_refresh', 'INFO',
            CONCAT('用户状态已更新, 活跃:', v_active_users, '/', v_total_users));
    END IF;
END//
DELIMITER ;

-- Java层可通过以下方式查询告警:
-- SELECT JSON_EXTRACT(profile, '$.system_alerts') FROM t_user WHERE username = 'admin';
-- 或通过 v_user_profile_360 视图的 roles_json 获取
