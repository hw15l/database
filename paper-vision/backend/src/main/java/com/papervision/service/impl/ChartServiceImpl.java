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
import org.springframework.cache.annotation.Cacheable;
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

    @Override
    @Transactional
    public Task createChartTask(Long userId, Long chartId, Long fileId, Map<String, Object> params) {
        Chart chart = chartMapper.selectById(chartId);
        if (chart == null) throw new BusinessException("图表不存在");

        databaseMapper.callQuotaCheck(userId, "ENFORCE");
        log.info("用户[{}]创建图表任务: chartId={}, fileId={}", userId, chartId, fileId);

        Task task = new Task();
        task.setUserId(userId);
        task.setTaskType("chart");
        task.setChartId(chartId);
        task.setFileId(fileId);
        taskMapper.insert(task);

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
                taskMapper.update(null, new LambdaUpdateWrapper<Task>()
                        .eq(Task::getId, task.getId())
                        .set(Task::getResultPath, (String) resp.getBody().get("image_path")));
                databaseMapper.callTaskStateTransition(task.getId(), "SUCCESS", null);
                log.info("图表任务[{}]渲染成功", task.getId());
            } else {
                throw new BusinessException("Python服务渲染失败");
            }
        } catch (Exception e) {
            log.warn("图表任务[{}]渲染失败: {}", task.getId(), e.getMessage());
            databaseMapper.callTaskStateTransition(task.getId(), "FAILED", e.getMessage());
        }
        return taskMapper.selectById(task.getId());
    }
}
