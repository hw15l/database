package com.papervision.mapper;

import org.apache.ibatis.annotations.*;
import java.util.List;
import java.util.Map;

/**
 * 数据库增强 Mapper — 存储过程调用 + 高级视图查询
 * <p>对应数据库对象: 9个存储过程 + 9个视图</p>
 */
@Mapper
public interface DatabaseMapper {

    // ──── 存储过程 ────

    /** sp_task_state_transition: 任务状态机(行锁+验证+日志+时间戳) */
    @Select("CALL sp_task_state_transition(#{taskId}, #{newStatus}, #{errorMsg})")
    Map<String, Object> callTaskStateTransition(@Param("taskId") Long taskId,
                                                 @Param("newStatus") String newStatus,
                                                 @Param("errorMsg") String errorMsg);

    /** sp_quota_check_and_enforce: 配额检查(从角色JSON元数据提取限额) */
    @Select("CALL sp_quota_check_and_enforce(#{userId}, #{action})")
    Map<String, Object> callQuotaCheck(@Param("userId") Long userId,
                                       @Param("action") String action);

    /** sp_smart_recommend: 协同过滤推荐(相似用户+兜底热门) */
    @Select("CALL sp_smart_recommend(#{userId}, #{limit})")
    List<Map<String, Object>> callSmartRecommend(@Param("userId") Long userId,
                                                  @Param("limit") Integer limit);

    /** sp_data_quality_audit: 数据质量审计(回写data_profile到t_file) */
    @Update("CALL sp_data_quality_audit(#{fileId})")
    void callDataQualityAudit(@Param("fileId") Long fileId);

    /** sp_hot_items_refresh: 热点刷新(绝对阈值+近期热度) */
    @Update("CALL sp_hot_items_refresh(#{threshold}, #{recentDays})")
    void callHotItemsRefresh(@Param("threshold") Integer threshold,
                              @Param("recentDays") Integer recentDays);

    /** sp_category_integrity_check: 闭包表完整性检查+修复 */
    @Update("CALL sp_category_integrity_check(#{autoFix})")
    void callCategoryIntegrityCheck(@Param("autoFix") Integer autoFix);

    // ──── 视图查询 ────

    /** v_user_profile_360: 用户360画像(6表JOIN+窗口函数RANK/PERCENT_RANK+JSON聚合) */
    @Select("SELECT * FROM v_user_profile_360 WHERE user_id = #{userId}")
    Map<String, Object> getUserProfile360(@Param("userId") Long userId);

    /** v_user_profile_360: 用户排行(窗口函数RANK排名, 替代手写JOIN+GROUP BY) */
    @Select("SELECT user_id AS userId, username, nickname, " +
            "total_tasks AS totalTasks, success_count AS successCount, " +
            "success_rate_pct AS successRatePct, user_tier AS userTier, " +
            "task_count_rank AS taskCountRank " +
            "FROM v_user_profile_360 ORDER BY task_count_rank LIMIT #{topN}")
    List<Map<String, Object>> getUserRankingFromView(@Param("topN") int topN);

    /** v_task_detail_enhanced: 任务详情(6表JOIN+窗口函数ROW_NUMBER/LAG/RANK+闭包表路径) */
    @Select("SELECT * FROM v_task_detail_enhanced WHERE task_id = #{taskId}")
    Map<String, Object> getTaskDetailEnhanced(@Param("taskId") Long taskId);

    /** v_data_quality_dashboard: 数据质量(生成列is_null_val+NTILE分桶+JSON类型分布) */
    @Select("SELECT * FROM v_data_quality_dashboard WHERE file_id = #{fileId}")
    Map<String, Object> getDataQuality(@Param("fileId") Long fileId);

    /** v_hot_items_unified_ranking: 图表/公式统一排行(UNION ALL+DENSE_RANK双排名) */
    @Select("SELECT item_type AS itemType, item_id AS itemId, item_name AS itemName, " +
            "item_code AS itemCode, usage_count AS usageCount, popularity_rank AS popularityRank, " +
            "complexity_level AS complexityLevel, is_hot AS isHot, category_name AS categoryName, " +
            "global_rank AS globalRank, type_rank AS typeRank " +
            "FROM v_hot_items_unified_ranking ORDER BY global_rank LIMIT #{limit}")
    List<Map<String, Object>> getHotItemsRanking(@Param("limit") Integer limit);

    /** v_trend_analysis_weekly: 周趋势(YEARWEEK聚合+LAG环比+SUM OVER累计) */
    @Select("SELECT * FROM v_trend_analysis_weekly ORDER BY year_week DESC LIMIT #{weeks}")
    List<Map<String, Object>> getWeeklyTrend(@Param("weeks") Integer weeks);

    /** v_user_preference_matrix: 用户偏好(条件聚合+FIRST_VALUE+JSON_OBJECTAGG) */
    @Select("SELECT * FROM v_user_preference_matrix WHERE user_id = #{userId}")
    Map<String, Object> getUserPreference(@Param("userId") Long userId);

    /** v_category_tree_full: 分类完整树(闭包表JOIN+JSON_ARRAYAGG+GROUP_CONCAT路径) */
    @Select("SELECT * FROM v_category_tree_full WHERE cat_type = #{catType} ORDER BY sort_order")
    List<Map<String, Object>> getCategoryTree(@Param("catType") String catType);

    /** v_system_activity_audit: 活动审计(UNION ALL多源汇聚+JSON_OBJECT详情) */
    @Select("SELECT * FROM v_system_activity_audit WHERE user_id = #{userId} " +
            "ORDER BY activity_time DESC LIMIT #{limit}")
    List<Map<String, Object>> getUserActivityAudit(@Param("userId") Long userId,
                                                    @Param("limit") Integer limit);
}
