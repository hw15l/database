package com.papervision.service;

import com.papervision.entity.Task;
import com.papervision.entity.History;
import java.util.List;
import java.util.Map;

/**
 * 任务服务接口 — 任务查询、历史记录管理、系统统计
 */
public interface TaskService {

    /** 根据ID查询任务 */
    Task getTask(Long taskId);

    /** 查询用户的所有任务(按创建时间降序) */
    List<Task> listByUser(Long userId);

    /** 查询用户的历史记录(排除已软删除) */
    List<History> listHistory(Long userId);

    /** 获取任务结果图片的二进制数据 */
    byte[] getResultImage(Long taskId);

    /**
     * 软删除历史记录
     * <p>触发器trg_history_soft_delete_guard自动填充deleted_at时间戳</p>
     */
    void deleteHistory(Long historyId, Long userId);

    /** 获取系统统计数据(带缓存), 含周趋势和热门排行 */
    Map<String, Object> getStats();

    /** 获取用户排行榜(Top N) */
    Map<String, Object> getUserRanking(int topN);
}
