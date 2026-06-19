-- ============================================================================================
-- Paper Vision — 缺陷修复补丁
-- 修复 E5: 闭包表在节点移动(parent_id变更)时不自动更新
-- ============================================================================================
USE paper_vision;

-- ============================================================
-- 补丁1: trg_category_before_update — 分类移动时自动重建闭包关系
-- 触发时机: t_category BEFORE UPDATE
-- 业务规则: 当 parent_id 发生变更时:
--   1) 断开移动子树与旧祖先链的闭包关系(保留子树内部关系)
--   2) 与新父节点的所有祖先建立新的闭包关系
--   3) 处理边界: 变为根节点(parent_id=NULL) / 从根变为子节点
-- 算法: Bill Karwin 闭包表移动子树标准算法
-- ============================================================
DROP TRIGGER IF EXISTS trg_category_before_update;

DELIMITER //
CREATE TRIGGER trg_category_before_update
BEFORE UPDATE ON t_category
FOR EACH ROW
BEGIN
    DECLARE v_parent_changed INT DEFAULT 0;

    -- 判断 parent_id 是否真正发生了变更
    SET v_parent_changed = CASE
        WHEN OLD.parent_id IS NULL AND NEW.parent_id IS NULL THEN 0
        WHEN OLD.parent_id IS NULL AND NEW.parent_id IS NOT NULL THEN 1
        WHEN OLD.parent_id IS NOT NULL AND NEW.parent_id IS NULL THEN 1
        WHEN OLD.parent_id != NEW.parent_id THEN 1
        ELSE 0
    END;

    IF v_parent_changed = 1 THEN
        -- 步骤1: 断开子树与旧祖先的关系
        -- 删除所有"穿过旧父节点"的闭包记录:
        --   descendant 是移动节点的后代(含自身), ancestor 不是移动节点的后代(即外部祖先)
        -- 使用双层子查询绕过 MySQL "can't specify target table" 限制
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

        -- 步骤2: 与新父节点建立闭包关系
        -- 对新父的所有祖先 × 移动节点的所有后代, 插入新闭包记录
        IF NEW.parent_id IS NOT NULL THEN
            INSERT INTO t_category_closure (ancestor_id, descendant_id, depth)
            SELECT
                ancestors.ancestor_id,
                descendants.descendant_id,
                ancestors.depth + descendants.depth + 1
            FROM t_category_closure AS ancestors
            CROSS JOIN t_category_closure AS descendants
            WHERE ancestors.descendant_id = NEW.parent_id
              AND descendants.ancestor_id = OLD.id;
        END IF;
    END IF;
END//
DELIMITER ;


-- ============================================================
-- 验证补丁: 运行移动节点测试
-- ============================================================
DROP PROCEDURE IF EXISTS _test_move_patch;
DELIMITER //
CREATE PROCEDURE _test_move_patch()
BEGIN
    DECLARE v_root_a BIGINT;
    DECLARE v_child_b BIGINT;
    DECLARE v_grandchild_c BIGINT;
    DECLARE v_new_parent BIGINT DEFAULT 1;  -- "统计图表" id=1
    DECLARE v_closure_count_before INT;
    DECLARE v_closure_count_after INT;
    DECLARE v_has_new_ancestor INT;
    DECLARE v_has_old_ancestor INT;
    DECLARE v_gc_depth INT;

    -- 创建测试树: root_a → child_b → grandchild_c
    INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('补丁测试根', 'chart', NULL, 99);
    SET v_root_a = LAST_INSERT_ID();

    INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('补丁子节点', 'chart', v_root_a, 1);
    SET v_child_b = LAST_INSERT_ID();

    INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('补丁孙节点', 'chart', v_child_b, 1);
    SET v_grandchild_c = LAST_INSERT_ID();

    -- 验证初始状态: grandchild_c 应有3条闭包 (self + child_b + root_a)
    SELECT COUNT(*) INTO v_closure_count_before FROM t_category_closure WHERE descendant_id = v_grandchild_c;

    SELECT '=== 移动前闭包状态 ===' AS '';
    SELECT * FROM t_category_closure WHERE descendant_id = v_child_b OR descendant_id = v_grandchild_c;

    -- 执行移动: 把 child_b 从 root_a 下移到 "统计图表"(id=1) 下
    UPDATE t_category SET parent_id = v_new_parent WHERE id = v_child_b;

    SELECT '=== 移动后闭包状态 ===' AS '';
    SELECT * FROM t_category_closure WHERE descendant_id = v_child_b OR descendant_id = v_grandchild_c;

    -- 验证1: child_b 是否有新祖先(统计图表 id=1)
    SELECT COUNT(*) INTO v_has_new_ancestor FROM t_category_closure
    WHERE descendant_id = v_child_b AND ancestor_id = v_new_parent AND depth > 0;

    -- 验证2: child_b 是否已断开旧祖先(root_a)
    SELECT COUNT(*) INTO v_has_old_ancestor FROM t_category_closure
    WHERE descendant_id = v_child_b AND ancestor_id = v_root_a AND depth > 0;

    -- 验证3: grandchild_c 的传递性关系是否正确(应该也挂在统计图表下)
    SELECT COUNT(*) INTO v_gc_depth FROM t_category_closure
    WHERE descendant_id = v_grandchild_c AND ancestor_id = v_new_parent;

    SELECT
        CASE WHEN v_has_new_ancestor > 0 THEN 'PASS' ELSE 'FAIL' END AS test_new_ancestor,
        CASE WHEN v_has_old_ancestor = 0 THEN 'PASS' ELSE 'FAIL' END AS test_old_disconnected,
        CASE WHEN v_gc_depth > 0 THEN 'PASS' ELSE 'FAIL' END AS test_grandchild_transitive;

    -- 清理测试数据
    DELETE FROM t_category WHERE id IN (v_grandchild_c, v_child_b, v_root_a);
END//
DELIMITER ;

CALL _test_move_patch();
DROP PROCEDURE IF EXISTS _test_move_patch;
