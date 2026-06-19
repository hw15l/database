package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.FormulaService;
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
public class FormulaServiceImpl implements FormulaService {
    private final FormulaMapper formulaMapper;
    private final TaskMapper taskMapper;
    private final HistoryMapper historyMapper;
    private final RestTemplate restTemplate;

    @Value("${python.service.url}")
    private String pythonServiceUrl;

    @Override
    @Cacheable(value = "formulaList")
    public List<Formula> listFormulas() {
        return formulaMapper.selectList(new LambdaQueryWrapper<Formula>().orderByAsc(Formula::getSortOrder));
    }

    @Override
    public List<Formula> listByCategory(Long catId) {
        return formulaMapper.selectList(new LambdaQueryWrapper<Formula>().eq(Formula::getCatId, catId));
    }

    @Override
    @Cacheable(value = "formula", key = "#formulaCode")
    public Formula getByCode(String formulaCode) {
        return formulaMapper.selectOne(new LambdaQueryWrapper<Formula>().eq(Formula::getFormulaCode, formulaCode));
    }

    @Override
    public Task createFormulaTask(Long userId, Long formulaId, String latex, Map<String, Object> params) {
        Formula formula = formulaMapper.selectById(formulaId);
        if (formula == null) throw new RuntimeException("公式不存在");

        Task task = new Task();
        task.setUserId(userId); task.setTaskType("formula");
        task.setFormulaId(formulaId); task.setStatus("PROCESSING");
        task.setStartTime(LocalDateTime.now());
        taskMapper.insert(task);

        try {
            Map<String, Object> req = new HashMap<>();
            req.put("formula_type", formula.getFormulaCode());
            req.put("latex", latex != null ? latex : formula.getLatexTemplate());
            req.put("params", params != null ? params : new HashMap<>());
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(req, headers);
            ResponseEntity<Map> resp = restTemplate.postForEntity(
                    pythonServiceUrl + "/render/formula", entity, Map.class);

            if (resp.getBody() != null && "success".equals(resp.getBody().get("status"))) {
                task.setResultPath((String) resp.getBody().get("image_path"));
                task.setStatus("SUCCESS"); task.setFinishTime(LocalDateTime.now());
                taskMapper.updateById(task);

                History history = new History();
                history.setUserId(userId); history.setTaskId(task.getId());
                history.setTaskType("formula"); history.setFormulaName(formula.getFormulaName());
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
