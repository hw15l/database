package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
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

    @Override
    public void deleteHistory(Long historyId, Long userId) {
        History h = historyMapper.selectById(historyId);
        if (h == null || !h.getUserId().equals(userId)) throw new BusinessException(403, "无权删除");
        h.setIsDeleted(1);
        historyMapper.updateById(h);
        log.info("用户[{}]软删除历史记录: historyId={}", userId, historyId);
    }

    @Override
    @Cacheable(value = "stats")
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalUsers", userMapper.selectCount(null));
        stats.put("totalTasks", taskMapper.selectCount(null));
        stats.put("successTasks", taskMapper.selectCount(
                new LambdaQueryWrapper<Task>().eq(Task::getStatus, "SUCCESS")));
        stats.put("weeklyTrend", databaseMapper.getWeeklyTrend(4));
        stats.put("hotItems", databaseMapper.getHotItemsRanking(5));
        return stats;
    }

    @Override
    public Map<String, Object> getUserRanking(int topN) {
        Map<String, Object> result = new HashMap<>();
        result.put("top", taskMapper.getUserRanking(topN));
        return result;
    }
}
