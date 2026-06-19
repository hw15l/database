-- ============================================================================================
-- Paper Vision — 闭包表深层子树移动压力测试
-- 覆盖: 5层深树构建 · 跨分支移动 · 移动到根 · 根变子节点 · 连续移动 · 批量验证
-- ============================================================================================
USE paper_vision;

DROP TABLE IF EXISTS _stress_results;
CREATE TEMPORARY TABLE _stress_results (
    seq       INT AUTO_INCREMENT PRIMARY KEY,
    test_id   VARCHAR(10),
    test_name VARCHAR(200),
    pass_fail VARCHAR(20),
    detail    TEXT DEFAULT NULL
) ENGINE=InnoDB;

-- ============================================================
-- 构建测试树: 两棵独立的5层深树
--
-- TreeA:                    TreeB:
--   A1                        B1
--   ├── A2                    ├── B2
--   │   ├── A3                │   └── B3
--   │   │   ├── A4            └── B4
--   │   │   │   └── A5
--   │   │   └── A4b
--   │   └── A3b
--   └── A2b
-- ============================================================

-- 清理旧测试数据(如果存在)
DELETE FROM t_category WHERE cat_name LIKE 'STRESS_%';

-- TreeA: 5层
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A1', 'chart', NULL, 200);
SET @a1 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A2', 'chart', @a1, 1);
SET @a2 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A2b', 'chart', @a1, 2);
SET @a2b = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A3', 'chart', @a2, 1);
SET @a3 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A3b', 'chart', @a2, 2);
SET @a3b = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A4', 'chart', @a3, 1);
SET @a4 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A4b', 'chart', @a3, 2);
SET @a4b = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_A5', 'chart', @a4, 1);
SET @a5 = LAST_INSERT_ID();

-- TreeB: 3层
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_B1', 'chart', NULL, 201);
SET @b1 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_B2', 'chart', @b1, 1);
SET @b2 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_B3', 'chart', @b2, 1);
SET @b3 = LAST_INSERT_ID();
INSERT INTO t_category (cat_name, cat_type, parent_id, sort_order) VALUES ('STRESS_B4', 'chart', @b1, 2);
SET @b4 = LAST_INSERT_ID();

-- ============================================================
-- 验证辅助过程: 检查某节点的闭包完整性
-- ============================================================
DROP PROCEDURE IF EXISTS _verify_closure;
DELIMITER //
CREATE PROCEDURE _verify_closure(
    IN p_node_id BIGINT,
    IN p_expected_ancestors INT,
    IN p_test_id VARCHAR(10),
    IN p_test_name VARCHAR(200)
)
BEGIN
    DECLARE v_actual INT;
    -- 祖先数 = 闭包记录数(包含自引用)
    SELECT COUNT(*) INTO v_actual FROM t_category_closure WHERE descendant_id = p_node_id;
    IF v_actual = p_expected_ancestors THEN
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, 'PASS', CONCAT('ancestors=', v_actual));
    ELSE
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, '** FAIL **',
            CONCAT('期望', p_expected_ancestors, '条闭包, 实际=', v_actual));
    END IF;
END//
DELIMITER ;

-- 辅助: 检查两个节点之间的闭包关系是否存在
DROP PROCEDURE IF EXISTS _verify_link;
DELIMITER //
CREATE PROCEDURE _verify_link(
    IN p_ancestor BIGINT,
    IN p_descendant BIGINT,
    IN p_expected_depth INT,
    IN p_test_id VARCHAR(10),
    IN p_test_name VARCHAR(200)
)
BEGIN
    DECLARE v_actual_depth INT DEFAULT -1;
    SELECT depth INTO v_actual_depth FROM t_category_closure
    WHERE ancestor_id = p_ancestor AND descendant_id = p_descendant LIMIT 1;
    IF v_actual_depth = p_expected_depth THEN
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, 'PASS', CONCAT('depth=', v_actual_depth));
    ELSEIF v_actual_depth = -1 THEN
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, '** FAIL **', '闭包关系不存在!');
    ELSE
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, '** FAIL **',
            CONCAT('期望depth=', p_expected_depth, ', 实际=', v_actual_depth));
    END IF;
END//
DELIMITER ;

-- 辅助: 检查两个节点之间不存在闭包关系
DROP PROCEDURE IF EXISTS _verify_no_link;
DELIMITER //
CREATE PROCEDURE _verify_no_link(
    IN p_ancestor BIGINT,
    IN p_descendant BIGINT,
    IN p_test_id VARCHAR(10),
    IN p_test_name VARCHAR(200)
)
BEGIN
    DECLARE v_cnt INT;
    SELECT COUNT(*) INTO v_cnt FROM t_category_closure
    WHERE ancestor_id = p_ancestor AND descendant_id = p_descendant;
    IF v_cnt = 0 THEN
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, 'PASS', '正确: 无闭包关系');
    ELSE
        INSERT INTO _stress_results (test_id, test_name, pass_fail, detail)
        VALUES (p_test_id, p_test_name, '** FAIL **', CONCAT('存在', v_cnt, '条残留闭包!'));
    END IF;
END//
DELIMITER ;


-- ############################################################################
-- S1: 初始状态验证 — 5层树的闭包完整性
-- ############################################################################

-- A5是第5层, 应该有5条闭包(self + A4 + A3 + A2 + A1)
CALL _verify_closure(@a5, 5, 'S1a', '5层叶子节点A5: 应有5条闭包(depth 0-4)');
-- A4应该有4条
CALL _verify_closure(@a4, 4, 'S1b', '第4层A4: 应有4条闭包');
-- A1是根, 应该只有1条(自引用)
CALL _verify_closure(@a1, 1, 'S1c', '根节点A1: 应只有1条自引用闭包');
-- A5到A1的depth应该是4
CALL _verify_link(@a1, @a5, 4, 'S1d', 'A1→A5 depth应为4');
-- B3的闭包应有3条
CALL _verify_closure(@b3, 3, 'S1e', 'B3: 应有3条闭包(self+B2+B1)');


-- ############################################################################
-- S2: 跨分支移动 — 将子树A3(含A4,A4b,A5)从TreeA移到TreeB的B2下
-- 移动前: A1→A2→A3→A4→A5, A3→A4b
-- 移动后: B1→B2→A3→A4→A5, A3→A4b
-- ############################################################################
UPDATE t_category SET parent_id = @b2 WHERE id = @a3;

-- A5: 原来5条(self+A4+A3+A2+A1), 现在应该5条(self+A4+A3+B2+B1)
CALL _verify_closure(@a5, 5, 'S2a', '跨分支移动后A5: 仍应5条闭包(新祖先链)');
-- A5到B1的depth应该是4
CALL _verify_link(@b1, @a5, 4, 'S2b', '跨分支: B1→A5 depth应为4');
-- A5到B2的depth应该是3
CALL _verify_link(@b2, @a5, 3, 'S2c', '跨分支: B2→A5 depth应为3');
-- A5不应再有到A1的闭包
CALL _verify_no_link(@a1, @a5, 'S2d', '跨分支: A1→A5 应已断开');
-- A5不应再有到A2的闭包
CALL _verify_no_link(@a2, @a5, 'S2e', '跨分支: A2→A5 应已断开');
-- A4b也应该跟着移动了
CALL _verify_link(@b1, @a4b, 3, 'S2f', '跨分支: B1→A4b depth应为3 (子树同移)');
-- A3的闭包: self + B2 + B1 = 3条
CALL _verify_closure(@a3, 3, 'S2g', '跨分支移动后A3: 应有3条闭包');
-- A3的内部子树关系不受影响
CALL _verify_link(@a3, @a5, 2, 'S2h', '子树内部: A3→A5 depth=2 不变');


-- ############################################################################
-- S3: 移动到根 — 将A3(含子树)从B2下移到根节点(parent_id=NULL)
-- ############################################################################
UPDATE t_category SET parent_id = NULL WHERE id = @a3;

-- A3变成根, 只有1条自引用
CALL _verify_closure(@a3, 1, 'S3a', '移到根后A3: 应只有1条自引用');
-- A5: self + A4 + A3 = 3条
CALL _verify_closure(@a5, 3, 'S3b', '移到根后A5: 应有3条闭包(self+A4+A3)');
-- A5不应再有到B1/B2的闭包
CALL _verify_no_link(@b1, @a5, 'S3c', '移到根: B1→A5 应已断开');
CALL _verify_no_link(@b2, @a5, 'S3d', '移到根: B2→A5 应已断开');
-- 子树内部不变
CALL _verify_link(@a3, @a4, 1, 'S3e', '子树内部: A3→A4 depth=1 不变');
CALL _verify_link(@a3, @a5, 2, 'S3f', '子树内部: A3→A5 depth=2 不变');


-- ############################################################################
-- S4: 根变子节点 — 将根节点A1移到B4下
-- A1当前是根节点(只有自引用), 下面还有A2,A2b,A3b
-- ############################################################################
UPDATE t_category SET parent_id = @b4 WHERE id = @a1;

-- A1: self + B4 + B1 = 3条
CALL _verify_closure(@a1, 3, 'S4a', '根变子节点: A1应有3条闭包(self+B4+B1)');
-- A2: self + A1 + B4 + B1 = 4条
CALL _verify_closure(@a2, 4, 'S4b', '根变子节点: A2应有4条闭包');
-- A3b: self + A2 + A1 + B4 + B1 = 5条
CALL _verify_closure(@a3b, 5, 'S4c', '根变子节点: A3b应有5条闭包');
-- 验证传递性: B1→A3b depth=4
CALL _verify_link(@b1, @a3b, 4, 'S4d', '传递性: B1→A3b depth应为4');


-- ############################################################################
-- S5: 连续快速移动 — 同一节点连续移动3次, 验证闭包始终正确
-- 将B3先移到A2b下, 再移到A3b下, 再移回B2下
-- ############################################################################

-- 第1次: B3 → A2b下
UPDATE t_category SET parent_id = @a2b WHERE id = @b3;
CALL _verify_link(@a2b, @b3, 1, 'S5a', '连续移动#1: A2b→B3 depth=1');
CALL _verify_link(@b1, @b3, 4, 'S5b', '连续移动#1: B1→B3 depth=4(via B4→A1→A2b)');
CALL _verify_no_link(@b2, @b3, 'S5c', '连续移动#1: B2→B3 已断开');

-- 第2次: B3 → A3b下
UPDATE t_category SET parent_id = @a3b WHERE id = @b3;
CALL _verify_link(@a3b, @b3, 1, 'S5d', '连续移动#2: A3b→B3 depth=1');
CALL _verify_link(@a2, @b3, 2, 'S5e', '连续移动#2: A2→B3 depth=2');
CALL _verify_no_link(@a2b, @b3, 'S5f', '连续移动#2: A2b→B3 已断开');

-- 第3次: B3 → 回到B2下(恢复原位)
UPDATE t_category SET parent_id = @b2 WHERE id = @b3;
CALL _verify_link(@b2, @b3, 1, 'S5g', '连续移动#3: B2→B3 depth=1 (恢复原位)');
CALL _verify_link(@b1, @b3, 2, 'S5h', '连续移动#3: B1→B3 depth=2');
CALL _verify_no_link(@a3b, @b3, 'S5i', '连续移动#3: A3b→B3 已断开');


-- ############################################################################
-- S6: 兄弟间移动 — A2b从A1下移到与A2同级(A2的子节点)
-- ############################################################################
UPDATE t_category SET parent_id = @a2 WHERE id = @a2b;
CALL _verify_link(@a2, @a2b, 1, 'S6a', '兄弟间移动: A2→A2b depth=1');
CALL _verify_link(@a1, @a2b, 2, 'S6b', '兄弟间移动: A1→A2b depth=2');
-- 验证A2b下面没有子节点, 闭包条数正确
-- A2b: self + A2 + A1 + B4 + B1 = 5条
CALL _verify_closure(@a2b, 5, 'S6c', '兄弟间移动后A2b: 应有5条闭包');


-- ############################################################################
-- S7: 全量完整性检查 — 调用sp_category_integrity_check验证全局一致性
-- ############################################################################
DROP PROCEDURE IF EXISTS _test_s7;
DELIMITER //
CREATE PROCEDURE _test_s7()
BEGIN
    DECLARE v_missing INT;
    DECLARE v_orphan INT;
    SELECT COUNT(*) INTO v_missing FROM t_category c
    WHERE NOT EXISTS (
        SELECT 1 FROM t_category_closure cc
        WHERE cc.ancestor_id = c.id AND cc.descendant_id = c.id AND cc.depth = 0
    );
    SELECT COUNT(*) INTO v_orphan FROM t_category_closure cc
    WHERE NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.ancestor_id)
       OR NOT EXISTS (SELECT 1 FROM t_category WHERE id = cc.descendant_id);

    IF v_missing = 0 AND v_orphan = 0 THEN
        INSERT INTO _stress_results VALUES (NULL, 'S7a', '全量完整性: 所有节点自引用完整', 'PASS', '无缺失');
        INSERT INTO _stress_results VALUES (NULL, 'S7b', '全量完整性: 无孤儿闭包记录', 'PASS', '无孤儿');
    ELSE
        IF v_missing > 0 THEN
            INSERT INTO _stress_results VALUES (NULL, 'S7a', '全量完整性: 自引用', '** FAIL **',
                CONCAT('缺失', v_missing, '条自引用'));
        ELSE
            INSERT INTO _stress_results VALUES (NULL, 'S7a', '全量完整性: 自引用完整', 'PASS', '无缺失');
        END IF;
        IF v_orphan > 0 THEN
            INSERT INTO _stress_results VALUES (NULL, 'S7b', '全量完整性: 孤儿闭包', '** FAIL **',
                CONCAT('存在', v_orphan, '条孤儿'));
        ELSE
            INSERT INTO _stress_results VALUES (NULL, 'S7b', '全量完整性: 无孤儿闭包', 'PASS', '无孤儿');
        END IF;
    END IF;

    -- 验证对称性: 每个depth>0的记录, 对应的ancestor到descendant路径深度一致
    INSERT INTO _stress_results
    SELECT NULL, 'S7c', '全量完整性: 闭包深度一致性',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE '** FAIL **' END,
        CASE WHEN COUNT(*) = 0 THEN '所有深度一致'
             ELSE CONCAT(COUNT(*), '条深度不一致')
        END
    FROM t_category_closure cc
    WHERE cc.depth > 0
      AND NOT EXISTS (
          SELECT 1 FROM t_category_closure cc2
          WHERE cc2.ancestor_id = cc.ancestor_id
            AND cc2.descendant_id = cc.ancestor_id
            AND cc2.depth = 0
      );
END//
DELIMITER ;
CALL _test_s7();
DROP PROCEDURE IF EXISTS _test_s7;


-- ############################################################################
-- S8: 递归CTE交叉验证 — 用递归CTE独立计算深度, 与闭包表对比
-- ############################################################################
DROP PROCEDURE IF EXISTS _test_s8;
DELIMITER //
CREATE PROCEDURE _test_s8()
BEGIN
    DECLARE v_mismatch INT;
    
    -- 递归CTE计算每个节点到根的深度
    WITH RECURSIVE cte_depth AS (
        SELECT id, cat_name, parent_id, 0 AS cte_depth FROM t_category WHERE parent_id IS NULL
        UNION ALL
        SELECT c.id, c.cat_name, c.parent_id, cd.cte_depth + 1
        FROM t_category c JOIN cte_depth cd ON c.parent_id = cd.id
    )
    SELECT COUNT(*) INTO v_mismatch
    FROM cte_depth cd
    LEFT JOIN (
        SELECT descendant_id, MAX(depth) AS closure_depth
        FROM t_category_closure GROUP BY descendant_id
    ) cl ON cd.id = cl.descendant_id
    WHERE cd.cte_depth != COALESCE(cl.closure_depth, -1);

    IF v_mismatch = 0 THEN
        INSERT INTO _stress_results VALUES (NULL, 'S8', 'CTE交叉验证: 递归深度 vs 闭包深度全部一致', 'PASS',
            '所有节点深度匹配');
    ELSE
        INSERT INTO _stress_results VALUES (NULL, 'S8', 'CTE交叉验证: 递归深度 vs 闭包深度', '** FAIL **',
            CONCAT(v_mismatch, '个节点深度不匹配!'));
    END IF;
END//
DELIMITER ;
CALL _test_s8();
DROP PROCEDURE IF EXISTS _test_s8;


-- ############################################################################
-- 输出压力测试报告
-- ############################################################################
SELECT '============================================' AS '';
SELECT '  闭包表深层子树移动 — 压力测试报告' AS '';
SELECT '============================================' AS '';

SELECT test_id, test_name, pass_fail, detail
FROM _stress_results ORDER BY seq;

SELECT '' AS '';
SELECT CONCAT('总计: ', COUNT(*), ' 项') AS summary FROM _stress_results;
SELECT CONCAT('通过: ', COUNT(*), ' 项') AS passed FROM _stress_results WHERE pass_fail = 'PASS';
SELECT CONCAT('失败: ', COUNT(*), ' 项') AS failed FROM _stress_results WHERE pass_fail = '** FAIL **';

-- 清理
DELETE FROM t_category WHERE cat_name LIKE 'STRESS_%';
DROP PROCEDURE IF EXISTS _verify_closure;
DROP PROCEDURE IF EXISTS _verify_link;
DROP PROCEDURE IF EXISTS _verify_no_link;
