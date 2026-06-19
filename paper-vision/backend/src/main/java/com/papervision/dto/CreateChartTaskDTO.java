package com.papervision.dto;

import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.util.Map;

@Data
public class CreateChartTaskDTO {
    @NotNull(message = "chartId不能为空")
    private Long chartId;
    private Long fileId;
    private Map<String, Object> params;
}
