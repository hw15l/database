package com.papervision.service;

import java.util.List;
import java.util.Map;

public interface DatabaseService {

    Map<String, Object> transitionTaskState(Long taskId, String newStatus, String errorMsg);

    Map<String, Object> checkQuota(Long userId);

    void enforceQuota(Long userId);

    List<Map<String, Object>> getSmartRecommendations(Long userId, Integer limit);

    void runDataQualityAudit(Long fileId);

    Map<String, Object> getUserProfile360(Long userId);

    Map<String, Object> getTaskDetailEnhanced(Long taskId);

    Map<String, Object> getDataQualityDashboard(Long fileId);

    List<Map<String, Object>> getHotItemsRanking(Integer limit);

    List<Map<String, Object>> getWeeklyTrend(Integer weeks);

    Map<String, Object> getUserPreference(Long userId);

    List<Map<String, Object>> getCategoryTree(String catType);

    List<Map<String, Object>> getUserActivityAudit(Long userId, Integer limit);

    void refreshHotItems();
}
