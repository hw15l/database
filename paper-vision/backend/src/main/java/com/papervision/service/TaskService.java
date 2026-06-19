package com.papervision.service;

import com.papervision.entity.Task;
import com.papervision.entity.History;
import java.util.List;
import java.util.Map;

public interface TaskService {
    Task getTask(Long taskId);
    List<Task> listByUser(Long userId);
    List<History> listHistory(Long userId);
    byte[] getResultImage(Long taskId);
    void deleteHistory(Long historyId, Long userId);
    Map<String, Object> getStats();
    Map<String, Object> getUserRanking(int topN);
}
