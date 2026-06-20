package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.cache.annotation.Cacheable;
import java.io.*;
import java.nio.file.Files;
import java.util.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class TaskServiceImpl implements TaskService {
    private final TaskMapper taskMapper;
    private final HistoryMapper historyMapper;
    private final UserMapper userMapper;
    private final DatabaseMapper databaseMapper;

    @Override
    public Task getTask(Long taskId) {
        return taskMapper.selectById(taskId);
    }

    @Override
    public List<Task> listByUser(Long userId) {
        return taskMapper.selectList(new LambdaQueryWrapper<Task>()
                .eq(Task::getUserId, userId).orderByDesc(Task::getCreateTime));
    }

    @Override
    public List<History> listHistory(Long userId) {
        return historyMapper.selectList(new LambdaQueryWrapper<History>()
                .eq(History::getUserId, userId).eq(History::getIsDeleted, 0)
                .orderByDesc(History::getCreateTime));
    }

    @Override
    public byte[] getResultImage(Long taskId) {
        Task task = taskMapper.selectById(taskId);
        if (task == null || task.getResultPath() == null) return null;
        try { return Files.readAllBytes(new File(task.getResultPath()).toPath()); }
        catch (IOException e) { log.warn("读取结果图片失败: taskId={}, error={}", taskId, e.getMessage()); return null; }
    }

    @Override
    @Transactional
    @CacheEvict(value = {"stats", "userProfile360"}, allEntries = true)
    public void deleteHistory(Long historyId, Long userId) {
        History h = historyMapper.selectById(historyId);
        if (h == null) throw new BusinessException(404, "记录不存在");
        if (!h.getUserId().equals(userId)) throw new BusinessException(403, "无权删除");
        h.setIsDeleted(1);
        historyMapper.updateById(h);
        log.info("用户[{}]软删除历史记录: historyId={}", userId, historyId);
    }

    @Override
    @Cacheable(value = "stats")
    public Map<String, Object> getStats() {
        log.info("加载系统统计数据(缓存未命中)");
        Map<String, Object> stats = new HashMap<>();
        long totalUsers = userMapper.selectCount(null);
        long totalTasks = taskMapper.selectCount(null);
        long successTasks = taskMapper.selectCount(
                new LambdaQueryWrapper<Task>().eq(Task::getStatus, "SUCCESS"));
        long todayTasks = taskMapper.selectCount(
                new LambdaQueryWrapper<Task>().apply("DATE(create_time) = CURDATE()"));
        stats.put("totalUsers", totalUsers);
        stats.put("totalTasks", totalTasks);
        stats.put("successTasks", successTasks);
        stats.put("successRate", totalTasks > 0 ? Math.round(successTasks * 1000.0 / totalTasks) / 10.0 : 0);
        stats.put("todayTasks", todayTasks);
        stats.put("avgTasksPerUser", totalUsers > 0 ? Math.round(totalTasks * 10.0 / totalUsers) / 10.0 : 0);
        stats.put("weeklyTrend", databaseMapper.getWeeklyTrend(4));
        stats.put("hotItems", databaseMapper.getHotItemsRanking(5));
        return stats;
    }

    @Override
    @Cacheable(value = "ranking", key = "#topN")
    public Map<String, Object> getUserRanking(int topN) {
        log.info("加载用户排行(缓存未命中): topN={}", topN);
        List<Map<String, Object>> users = databaseMapper.getUserRankingFromView(topN);
        users.sort((a, b) -> {
            double scoreA = numVal(a, "totalTasks") + numVal(a, "successRatePct") * 0.3;
            double scoreB = numVal(b, "totalTasks") + numVal(b, "successRatePct") * 0.3;
            return Double.compare(scoreB, scoreA);
        });
        for (int i = 0; i < users.size(); i++) {
            users.get(i).put("taskCountRank", i + 1);
        }
        Map<String, Object> result = new HashMap<>();
        result.put("top", users);
        return result;
    }

    private static double numVal(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof Number ? ((Number) v).doubleValue() : 0;
    }
}
