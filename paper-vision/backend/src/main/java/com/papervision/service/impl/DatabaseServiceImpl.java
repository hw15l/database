package com.papervision.service.impl;

import com.papervision.common.BusinessException;
import com.papervision.mapper.DatabaseMapper;
import com.papervision.service.DatabaseService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;
import java.util.Map;

/**
 * 数据库增强服务实现 — 存储过程调用 + 高级视图查询
 * <p>类级别默认readOnly事务, 写方法单独标注@Transactional覆盖</p>
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class DatabaseServiceImpl implements DatabaseService {
    private final DatabaseMapper databaseMapper;

    @Override
    @Transactional
    public Map<String, Object> transitionTaskState(Long taskId, String newStatus, String errorMsg) {
        try {
            return databaseMapper.callTaskStateTransition(taskId, newStatus, errorMsg);
        } catch (Exception e) {
            log.warn("任务状态流转失败: taskId={}, {}→{}, reason={}",
                    taskId, "?", newStatus, e.getMessage());
            throw new BusinessException("状态流转失败: " + e.getMessage());
        }
    }

    @Override
    public Map<String, Object> checkQuota(Long userId) {
        return databaseMapper.callQuotaCheck(userId, "CHECK");
    }

    @Override
    public void enforceQuota(Long userId) {
        try {
            databaseMapper.callQuotaCheck(userId, "ENFORCE");
        } catch (Exception e) {
            throw new BusinessException(e.getMessage());
        }
    }

    @Override
    public List<Map<String, Object>> getSmartRecommendations(Long userId, Integer limit) {
        if (limit == null || limit <= 0) limit = 5;
        return databaseMapper.callSmartRecommend(userId, limit);
    }

    @Override
    @Transactional
    public void runDataQualityAudit(Long fileId) {
        databaseMapper.callDataQualityAudit(fileId);
    }

    @Override
    @Cacheable(value = "userProfile360", key = "#userId")
    public Map<String, Object> getUserProfile360(Long userId) {
        Map<String, Object> profile = databaseMapper.getUserProfile360(userId);
        if (profile == null) throw new BusinessException("用户不存在");
        return profile;
    }

    @Override
    public Map<String, Object> getTaskDetailEnhanced(Long taskId) {
        Map<String, Object> detail = databaseMapper.getTaskDetailEnhanced(taskId);
        if (detail == null) throw new BusinessException("任务不存在");
        return detail;
    }

    @Override
    public Map<String, Object> getDataQualityDashboard(Long fileId) {
        return databaseMapper.getDataQuality(fileId);
    }

    @Override
    @Cacheable(value = "hotItems", key = "#limit")
    public List<Map<String, Object>> getHotItemsRanking(Integer limit) {
        if (limit == null || limit <= 0) limit = 20;
        return databaseMapper.getHotItemsRanking(limit);
    }

    @Override
    @Cacheable(value = "weeklyTrend", key = "#weeks")
    public List<Map<String, Object>> getWeeklyTrend(Integer weeks) {
        if (weeks == null || weeks <= 0) weeks = 12;
        return databaseMapper.getWeeklyTrend(weeks);
    }

    @Override
    public Map<String, Object> getUserPreference(Long userId) {
        return databaseMapper.getUserPreference(userId);
    }

    @Override
    @Cacheable(value = "categoryTree", key = "#catType")
    public List<Map<String, Object>> getCategoryTree(String catType) {
        return databaseMapper.getCategoryTree(catType);
    }

    @Override
    public List<Map<String, Object>> getUserActivityAudit(Long userId, Integer limit) {
        if (limit == null || limit <= 0) limit = 50;
        return databaseMapper.getUserActivityAudit(userId, limit);
    }

    @Override
    @Transactional
    public void refreshHotItems() {
        databaseMapper.callHotItemsRefresh(10, 7);
        log.info("热点数据刷新完成");
    }
}
