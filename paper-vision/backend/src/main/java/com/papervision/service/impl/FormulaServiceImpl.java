package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.FormulaService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class FormulaServiceImpl implements FormulaService {
    private final FormulaMapper formulaMapper;
    private final TaskMapper taskMapper;
    private final DatabaseMapper databaseMapper;
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

        databaseMapper.callQuotaCheck(userId, "ENFORCE");

        Task task = new Task();
        task.setUserId(userId);
        task.setTaskType("formula");
        task.setFormulaId(formulaId);
        taskMapper.insert(task);

        databaseMapper.callTaskStateTransition(task.getId(), "PROCESSING", null);

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
                taskMapper.update(null, new LambdaUpdateWrapper<Task>()
                        .eq(Task::getId, task.getId())
                        .set(Task::getResultPath, (String) resp.getBody().get("image_path")));

                databaseMapper.callTaskStateTransition(task.getId(), "SUCCESS", null);
            } else {
                throw new RuntimeException("Python服务渲染失败");
            }
        } catch (Exception e) {
            databaseMapper.callTaskStateTransition(task.getId(), "FAILED", e.getMessage());
        }
        return taskMapper.selectById(task.getId());
    }
}
