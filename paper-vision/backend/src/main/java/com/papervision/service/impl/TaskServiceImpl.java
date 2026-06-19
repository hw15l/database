package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.cache.annotation.Cacheable;
import java.io.*;
import java.nio.file.Files;
import java.util.*;

@Service
@RequiredArgsConstructor
public class TaskServiceImpl implements TaskService {
    private final TaskMapper taskMapper;
    private final HistoryMapper historyMapper;
    private final UserMapper userMapper;

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
        catch (IOException e) { return null; }
    }

    @Override
    public void deleteHistory(Long historyId, Long userId) {
        History h = historyMapper.selectById(historyId);
        if (h == null || !h.getUserId().equals(userId)) throw new RuntimeException("无权删除");
        h.setIsDeleted(1); historyMapper.updateById(h);
    }

    @Override
    @Cacheable(value = "stats")
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("totalUsers", userMapper.selectCount(null));
        stats.put("totalTasks", taskMapper.selectCount(null));
        stats.put("successTasks", taskMapper.selectCount(
                new LambdaQueryWrapper<Task>().eq(Task::getStatus, "SUCCESS")));
        return stats;
    }

    @Override
    public Map<String, Object> getUserRanking(int topN) {
        Map<String, Object> result = new HashMap<>();
        result.put("top", taskMapper.getUserRanking(topN));
        return result;
    }
}
