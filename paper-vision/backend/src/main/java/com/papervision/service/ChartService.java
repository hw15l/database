package com.papervision.service;

import com.papervision.entity.Chart;
import com.papervision.entity.Task;
import java.util.List;
import java.util.Map;

public interface ChartService {
    List<Chart> listCharts();
    List<Chart> listByCategory(Long catId);
    Chart getByCode(String chartCode);
    Task createChartTask(Long userId, Long chartId, Long fileId, Map<String, Object> params);
}
