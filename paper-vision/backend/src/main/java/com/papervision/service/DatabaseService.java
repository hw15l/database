package com.papervision.service;

import java.util.List;
import java.util.Map;

/**
 * 数据库增强服务接口 — 封装存储过程调用与高级视图查询
 * <p>将数据库层的复杂能力(状态机/推荐/配额/画像/审计)暴露给Controller层</p>
 */
public interface DatabaseService {

    /**
     * 任务状态机流转(调用sp_task_state_transition)
     * <p>合法流转: PENDING→PROCESSING→SUCCESS/FAILED, FAILED→PENDING(重试)</p>
     *
     * @param taskId    任务ID
     * @param newStatus 目标状态
     * @param errorMsg  错误信息(仅FAILED时有效)
     * @return 更新后的任务信息
     */
    Map<String, Object> transitionTaskState(Long taskId, String newStatus, String errorMsg);

    /** 检查用户今日配额使用情况(不强制) */
    Map<String, Object> checkQuota(Long userId);

    /** 强制配额检查, 超额抛出BusinessException */
    void enforceQuota(Long userId);

    /** 基于协同过滤的智能推荐(图表+公式) */
    List<Map<String, Object>> getSmartRecommendations(Long userId, Integer limit);

    /** 执行文件数据质量审计, 回写data_profile到t_file */
    void runDataQualityAudit(Long fileId);

    /** 用户360度全景画像(v_user_profile_360视图) */
    Map<String, Object> getUserProfile360(Long userId);

    /** 任务详情增强(v_task_detail_enhanced视图, 含分类路径/耗时排名) */
    Map<String, Object> getTaskDetailEnhanced(Long taskId);

    /** 文件数据质量仪表盘(v_data_quality_dashboard视图) */
    Map<String, Object> getDataQualityDashboard(Long fileId);

    /** 图表/公式统一热度排行(v_hot_items_unified_ranking视图) */
    List<Map<String, Object>> getHotItemsRanking(Integer limit);

    /** 周度趋势分析, 含环比增长率(v_trend_analysis_weekly视图) */
    List<Map<String, Object>> getWeeklyTrend(Integer weeks);

    /** 用户偏好矩阵(v_user_preference_matrix视图) */
    Map<String, Object> getUserPreference(Long userId);

    /** 分类完整树(v_category_tree_full视图, 带缓存) */
    List<Map<String, Object>> getCategoryTree(String catType);

    /** 用户活动审计时间线(v_system_activity_audit视图) */
    List<Map<String, Object>> getUserActivityAudit(Long userId, Integer limit);

    /** 手动刷新热点数据(调用sp_hot_items_refresh) */
    void refreshHotItems();
}
