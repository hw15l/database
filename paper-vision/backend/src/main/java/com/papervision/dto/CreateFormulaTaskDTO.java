package com.papervision.dto;

import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.util.Map;

@Data
public class CreateFormulaTaskDTO {
    @NotNull(message = "formulaId不能为空")
    private Long formulaId;
    private String latex;
    private Map<String, Object> params;
}
