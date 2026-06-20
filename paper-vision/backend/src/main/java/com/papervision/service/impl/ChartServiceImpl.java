package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.ChartService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class ChartServiceImpl implements ChartService {
    private final ChartMapper chartMapper;
    private final FileMapper fileMapper;
    private final RenderHelper renderHelper;

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

        log.info("用户[{}]创建图表任务: chartId={}, fileId={}", userId, chartId, fileId);

        Task task = new Task();
        task.setUserId(userId);
        task.setTaskType("chart");
        task.setChartId(chartId);
        task.setFileId(fileId);

        FileEntity file = fileMapper.selectById(fileId);
        Map<String, Object> req = new HashMap<>();
        req.put("chart_type", chart.getChartCode());
        req.put("file_path", file != null ? file.getFilePath() : null);
        req.put("params", params);

        return renderHelper.executeRenderTask(userId, task,
                pythonServiceUrl + "/render/chart", req);
    }
}
