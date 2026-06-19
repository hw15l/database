package com.papervision.service;

import com.papervision.entity.Formula;
import com.papervision.entity.Task;
import java.util.List;
import java.util.Map;

public interface FormulaService {
    List<Formula> listFormulas();
    List<Formula> listByCategory(Long catId);
    Formula getByCode(String formulaCode);
    Task createFormulaTask(Long userId, Long formulaId, String latex, Map<String, Object> params);
}
