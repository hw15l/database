package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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
        catch (IOException e) { log.warn("读取结果图片失败: taskId={}, {}", taskId, e.getMessage()); return null; }
    }

    /**
     * 软删除历史记录
     * <p>[DB] trg_history_soft_delete_guard: 自动填充deleted_at时间戳 + rating范围守护(1-5)</p>
     */
    @Override
    @Transactional
    public void deleteHistory(Long historyId, Long userId) {
        History h = historyMapper.selectById(historyId);
        if (h == null) throw new BusinessException(404, "记录不存在");
        if (!h.getUserId().equals(userId)) throw new BusinessException(403, "无权删除");
        // [DB] trg_history_soft_delete_guard: is_deleted 0→1 时自动设置 deleted_at = NOW()
        h.setIsDeleted(1);
        historyMapper.updateById(h);
        log.info("用户[{}]软删除历史记录: historyId={}", userId, historyId);
    }

    /**
     * 系统统计 — 混合使用基础查询 + 数据库视图
     * <p>[DB] v_trend_analysis_weekly: 窗口函数LAG环比 + SUM OVER累计</p>
     * <p>[DB] v_hot_items_unified_ranking: UNION ALL合并 + DENSE_RANK排名</p>
     */
    @Override
    @Cacheable(value = "stats")
    public Map<String, Object> getStats() {
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
        // [DB] 视图 v_trend_analysis_weekly + v_hot_items_unified_ranking
        stats.put("weeklyTrend", databaseMapper.getWeeklyTrend(4));
        stats.put("hotItems", databaseMapper.getHotItemsRanking(5));
        return stats;
    }

    /**
     * 用户排行 — 使用 v_user_profile_360 视图替代手写SQL
     * <p>[DB] v_user_profile_360: 6表JOIN + RANK()窗口函数 + 用户分层</p>
     */
    @Override
    @Cacheable(value = "ranking", key = "#topN")
    public Map<String, Object> getUserRanking(int topN) {
        Map<String, Object> result = new HashMap<>();
        // [DB] v_user_profile_360 视图: 窗口函数RANK()排名, 替代手写JOIN+GROUP BY
        result.put("top", databaseMapper.getUserRankingFromView(topN));
        return result;
    }
}
