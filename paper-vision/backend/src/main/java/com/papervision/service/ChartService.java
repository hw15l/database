package com.papervision.service;

import com.papervision.entity.Chart;
import com.papervision.entity.Task;
import java.util.List;
import java.util.Map;

/**
 * 图表服务接口 — 图表查询与图表渲染任务创建
 */
public interface ChartService {

    /** 获取所有图表列表(带缓存) */
    List<Chart> listCharts();

    /** 按分类ID查询图表 */
    List<Chart> listByCategory(Long catId);

    /** 按图表编码查询单个图表(带缓存) */
    Chart getByCode(String chartCode);

    /**
     * 创建图表渲染任务
     * <p>流程: 配额检查 → INSERT(触发器设PENDING) → 状态机推进PROCESSING → 调用Python渲染 → SUCCESS/FAILED</p>
     *
     * @param userId  用户ID
     * @param chartId 图表ID
     * @param fileId  数据文件ID(可选)
     * @param params  自定义参数(颜色/样式等)
     * @return 创建后的任务(含触发器填充的字段)
     */
    Task createChartTask(Long userId, Long chartId, Long fileId, Map<String, Object> params);
}
