package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.ChartService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.time.LocalDateTime;
import java.util.*;

@Service
@RequiredArgsConstructor
public class ChartServiceImpl implements ChartService {
    private final ChartMapper chartMapper;
    private final TaskMapper taskMapper;
    private final HistoryMapper historyMapper;
    private final FileMapper fileMapper;
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

        Task task = new Task();
        task.setUserId(userId); task.setTaskType("chart");
        task.setChartId(chartId); task.setFileId(fileId);
        task.setStatus("PROCESSING");
        task.setStartTime(LocalDateTime.now());
        taskMapper.insert(task);

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
                task.setResultPath((String) resp.getBody().get("image_path"));
                task.setStatus("SUCCESS");
                task.setFinishTime(LocalDateTime.now());
                taskMapper.updateById(task);

                History history = new History();
                history.setUserId(userId); history.setTaskId(task.getId());
                history.setTaskType("chart"); history.setChartName(chart.getChartName());
                history.setResultImage(task.getResultPath());
                historyMapper.insert(history);
            } else {
                throw new RuntimeException("Python服务渲染失败");
            }
        } catch (Exception e) {
            task.setStatus("FAILED"); task.setErrorMsg(e.getMessage());
            taskMapper.updateById(task);
        }
        return task;
    }
}
