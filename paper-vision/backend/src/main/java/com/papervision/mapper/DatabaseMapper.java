package com.papervision.mapper;

import org.apache.ibatis.annotations.*;
import java.util.List;
import java.util.Map;

@Mapper
public interface DatabaseMapper {

    @Select("CALL sp_task_state_transition(#{taskId}, #{newStatus}, #{errorMsg})")
    Map<String, Object> callTaskStateTransition(@Param("taskId") Long taskId,
                                                 @Param("newStatus") String newStatus,
                                                 @Param("errorMsg") String errorMsg);

    @Select("CALL sp_quota_check_and_enforce(#{userId}, #{action})")
    Map<String, Object> callQuotaCheck(@Param("userId") Long userId,
                                       @Param("action") String action);

    @Select("CALL sp_smart_recommend(#{userId}, #{limit})")
    List<Map<String, Object>> callSmartRecommend(@Param("userId") Long userId,
                                                  @Param("limit") Integer limit);

    @Update("CALL sp_data_quality_audit(#{fileId})")
    void callDataQualityAudit(@Param("fileId") Long fileId);

    @Update("CALL sp_hot_items_refresh(#{threshold}, #{recentDays})")
    void callHotItemsRefresh(@Param("threshold") Integer threshold,
                              @Param("recentDays") Integer recentDays);

    @Update("CALL sp_category_integrity_check(#{autoFix})")
    void callCategoryIntegrityCheck(@Param("autoFix") Integer autoFix);

    @Select("SELECT * FROM v_user_profile_360 WHERE user_id = #{userId}")
    Map<String, Object> getUserProfile360(@Param("userId") Long userId);

    @Select("SELECT * FROM v_task_detail_enhanced WHERE task_id = #{taskId}")
    Map<String, Object> getTaskDetailEnhanced(@Param("taskId") Long taskId);

    @Select("SELECT * FROM v_data_quality_dashboard WHERE file_id = #{fileId}")
    Map<String, Object> getDataQuality(@Param("fileId") Long fileId);

    @Select("SELECT * FROM v_hot_items_unified_ranking ORDER BY global_rank LIMIT #{limit}")
    List<Map<String, Object>> getHotItemsRanking(@Param("limit") Integer limit);

    @Select("SELECT * FROM v_trend_analysis_weekly ORDER BY year_week DESC LIMIT #{weeks}")
    List<Map<String, Object>> getWeeklyTrend(@Param("weeks") Integer weeks);

    @Select("SELECT * FROM v_user_preference_matrix WHERE user_id = #{userId}")
    Map<String, Object> getUserPreference(@Param("userId") Long userId);

    @Select("SELECT * FROM v_category_tree_full WHERE cat_type = #{catType} ORDER BY sort_order")
    List<Map<String, Object>> getCategoryTree(@Param("catType") String catType);

    @Select("SELECT * FROM v_system_activity_audit WHERE user_id = #{userId} " +
            "ORDER BY activity_time DESC LIMIT #{limit}")
    List<Map<String, Object>> getUserActivityAudit(@Param("userId") Long userId,
                                                    @Param("limit") Integer limit);
}
