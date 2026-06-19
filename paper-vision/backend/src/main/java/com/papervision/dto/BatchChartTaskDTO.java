package com.papervision.dto;

import jakarta.validation.constraints.NotEmpty;
import lombok.Data;
import java.util.List;
import java.util.Map;

/**
 * 批量图表任务创建请求体
 */
@Data
public class BatchChartTaskDTO {
    @NotEmpty(message = "请至少选择一种图表")
    private List<Long> chartIds;
    private Long fileId;
    private Map<String, Object> params;
}
