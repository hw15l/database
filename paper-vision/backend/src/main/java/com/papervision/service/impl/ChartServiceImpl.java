package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.ChartService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
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

    @Override
    public Task createChartTask(Long userId, Long chartId, Long fileId, Map<String, Object> params) {
        Chart chart = chartMapper.selectById(chartId);
        if (chart == null) throw new RuntimeException("图表不存在");

        // [阶段四] 配额检查 — 超额时存储过程抛出异常, 自动阻止任务创建
        databaseMapper.callQuotaCheck(userId, "ENFORCE");

        // [阶段二] INSERT不设status — trg_task_before_insert自动:
        //   ① status=PENDING  ② render_engine推断  ③ chart_id一致性校验
        // trg_task_before_insert_seq自动: total_tasks计数
        Task task = new Task();
        task.setUserId(userId);
        task.setTaskType("chart");
        task.setChartId(chartId);
        task.setFileId(fileId);
        taskMapper.insert(task);

        // [阶段二] 状态流转PENDING→PROCESSING — sp_task_state_transition:
        //   ① 状态机验证  ② start_time自动填充  ③ execution_log追加
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
            ResponseEntity<Map> resp = restTemplate.postForEntity(
                    pythonServiceUrl + "/render/chart", entity, Map.class);

            if (resp.getBody() != null && "success".equals(resp.getBody().get("status"))) {
                // 先保存渲染结果(LambdaUpdateWrapper只改result_path, 不碰status, 不触发状态检查)
                taskMapper.update(null, new LambdaUpdateWrapper<Task>()
                        .eq(Task::getId, task.getId())
                        .set(Task::getResultPath, (String) resp.getBody().get("image_path")));

                // [阶段二+三] PROCESSING→SUCCESS — 触发器trg_task_after_update自动:
                //   ① finish_time填充  ② chart.usage_count+1  ③ is_hot判定
                //   ④ 创建t_history记录(含snapshot JSON)  ← 原来手动创建的代码已删除
                databaseMapper.callTaskStateTransition(task.getId(), "SUCCESS", null);
            } else {
                throw new RuntimeException("Python服务渲染失败");
            }
        } catch (Exception e) {
            // PROCESSING→FAILED — 触发器自动填充finish_time, 存储过程记录error_msg+execution_log
            databaseMapper.callTaskStateTransition(task.getId(), "FAILED", e.getMessage());
        }
        // 重新查询以获取所有触发器/生成列填充的字段(duration_seconds, render_engine等)
        return taskMapper.selectById(task.getId());
    }
}
