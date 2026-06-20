package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.ChartService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.*;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestTemplate;
import java.util.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class ChartServiceImpl implements ChartService {
    private final ChartMapper chartMapper;
    private final TaskMapper taskMapper;
    private final FileMapper fileMapper;
    private final DatabaseMapper databaseMapper;
    private final RestTemplate restTemplate;

    @Value("${python.service.url}")
    private String pythonServiceUrl;

    @Override
    @Cacheable(value = "chartList")
    public List<Chart> listCharts() {
        return chartMapper.selectList(new LambdaQueryWrapper<Chart>().orderByAsc(Chart::getSortOrder));
    }

    @Override
    public List<Chart> listByCategory(Long catId) {
        return chartMapper.selectList(new LambdaQueryWrapper<Chart>().eq(Chart::getCatId, catId));
    }

    @Override
    @Cacheable(value = "chart", key = "#chartCode")
    public Chart getByCode(String chartCode) {
        return chartMapper.selectOne(new LambdaQueryWrapper<Chart>().eq(Chart::getChartCode, chartCode));
    }

    /**
     * 创建图表渲染任务 — 数据库层深度集成
     * <p>全流程涉及的数据库对象:</p>
     * <ul>
     *   <li>[存储过程] sp_quota_check_and_enforce: 配额检查(从t_role.metadata JSON提取限额)</li>
     *   <li>[触发器] trg_task_before_insert: 自动设status=PENDING + 推断render_engine + 校验chart_id</li>
     *   <li>[触发器] trg_task_before_insert_seq: 自动填充total_tasks计数</li>
     *   <li>[存储过程] sp_task_state_transition: 状态机验证 + start_time/finish_time + execution_log(JSON)</li>
     *   <li>[触发器] trg_task_status_guard: BEFORE UPDATE拦截非法状态流转</li>
     *   <li>[触发器] trg_task_after_update: SUCCESS时自动创建t_history(含snapshot) + usage_count+1 + is_hot判定</li>
     *   <li>[生成列] duration_seconds: TIMESTAMPDIFF(start_time, finish_time)自动计算</li>
     *   <li>[生成列] popularity_rank: 由usage_count自动推算S/A/B/C/D等级</li>
     * </ul>
     */
    @Override
    @Transactional
    @CacheEvict(value = {"stats", "ranking", "hotItems", "weeklyTrend", "userProfile360"}, allEntries = true)
    public Task createChartTask(Long userId, Long chartId, Long fileId, Map<String, Object> params) {
        Chart chart = chartMapper.selectById(chartId);
        if (chart == null) throw new BusinessException("图表不存在");

        if (params == null) params = new HashMap<>();
        if (params.size() > 20) throw new BusinessException("参数数量超过限制");
        Object dpiVal = params.get("dpi");
        if (dpiVal != null) {
            int dpi = Integer.parseInt(String.valueOf(dpiVal));
            if (dpi < 72 || dpi > 600) throw new BusinessException("DPI范围应在72-600之间");
        }
        Object colorVal = params.get("colorScheme");
        if (colorVal != null && !String.valueOf(colorVal).matches("^[a-zA-Z0-9_]+$")) {
            throw new BusinessException("颜色方案名称非法");
        }

        // [DB] sp_quota_check_and_enforce: 从角色元数据JSON提取每日限额, 超额抛异常
        databaseMapper.callQuotaCheck(userId, "ENFORCE");
        log.info("用户[{}]创建图表任务: chartId={}, fileId={}", userId, chartId, fileId);

        // INSERT → [DB] trg_task_before_insert: status=PENDING, render_engine自动推断
        Task task = new Task();
        task.setUserId(userId);
        task.setTaskType("chart");
        task.setChartId(chartId);
        task.setFileId(fileId);
        taskMapper.insert(task);

        // [DB] sp_task_state_transition: PENDING→PROCESSING (行锁+状态机验证+start_time+execution_log)
        databaseMapper.callTaskStateTransition(task.getId(), "PROCESSING", null);

        try {
            FileEntity file = fileMapper.selectById(fileId);
            Map<String, Object> req = new HashMap<>();
            req.put("chart_type", chart.getChartCode());
            req.put("file_path", file != null ? file.getFilePath() : null);
            req.put("params", params != null ? params : new HashMap<>());

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(req, headers);
            log.info("调用Python渲染服务: chart_type={}", chart.getChartCode());
            ResponseEntity<Map> resp = restTemplate.postForEntity(
                    pythonServiceUrl + "/render/chart", entity, Map.class);

            if (resp.getBody() != null && "success".equals(resp.getBody().get("status"))) {
                // 仅更新result_path, 不碰status(LambdaUpdateWrapper精确更新, 不触发状态检查)
                taskMapper.update(null, new LambdaUpdateWrapper<Task>()
                        .eq(Task::getId, task.getId())
                        .set(Task::getResultPath, (String) resp.getBody().get("image_path")));

                // [DB] sp_task_state_transition: PROCESSING→SUCCESS
                // [DB] trg_task_after_update 自动: chart.usage_count+1, is_hot判定, 创建t_history(含snapshot JSON)
                // ★ 此处不需要手动创建History记录 — 完全信任触发器
                databaseMapper.callTaskStateTransition(task.getId(), "SUCCESS", null);
                log.info("图表任务[{}]渲染成功", task.getId());
            } else {
                throw new BusinessException("Python服务渲染失败");
            }
        } catch (Exception e) {
            log.warn("图表任务[{}]渲染失败: {}", task.getId(), e.getMessage());
            // [DB] sp_task_state_transition: PROCESSING→FAILED (finish_time+error_msg+execution_log)
            databaseMapper.callTaskStateTransition(task.getId(), "FAILED", e.getMessage());
        }
        // 重新查询: 获取触发器/生成列填充的字段(duration_seconds, render_engine, total_tasks等)
        return taskMapper.selectById(task.getId());
    }
}
