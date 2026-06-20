package com.papervision.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.papervision.common.BusinessException;
import com.papervision.entity.*;
import com.papervision.mapper.*;
import com.papervision.service.FormulaService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
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

    /**
     * 创建公式渲染任务 — 数据库对象使用同 ChartServiceImpl.createChartTask()
     * <p>存储过程: sp_quota_check_and_enforce, sp_task_state_transition</p>
     * <p>触发器: trg_task_before_insert(PENDING+推断), trg_task_after_update(History+usage_count)</p>
     */
    @Override
    @Transactional
    public Task createFormulaTask(Long userId, Long formulaId, String latex, Map<String, Object> params) {
        Formula formula = formulaMapper.selectById(formulaId);
        if (formula == null) throw new BusinessException("公式不存在");

        // [DB] sp_quota_check_and_enforce
        databaseMapper.callQuotaCheck(userId, "ENFORCE");
        log.info("用户[{}]创建公式任务: formulaId={}", userId, formulaId);

        // INSERT → [DB] trg_task_before_insert: status=PENDING, formula_id一致性校验
        Task task = new Task();
        task.setUserId(userId);
        task.setTaskType("formula");
        task.setFormulaId(formulaId);
        taskMapper.insert(task);

        // [DB] sp_task_state_transition: PENDING→PROCESSING
        databaseMapper.callTaskStateTransition(task.getId(), "PROCESSING", null);

        try {
            Map<String, Object> req = new HashMap<>();
            req.put("formula_type", formula.getFormulaCode());
            req.put("latex", latex != null ? latex : formula.getLatexTemplate());
            req.put("params", params != null ? params : new HashMap<>());
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(req, headers);
            log.info("调用Python渲染服务: formula_type={}", formula.getFormulaCode());
            ResponseEntity<Map> resp = restTemplate.postForEntity(
                    pythonServiceUrl + "/render/formula", entity, Map.class);

            if (resp.getBody() != null && "success".equals(resp.getBody().get("status"))) {
                taskMapper.update(null, new LambdaUpdateWrapper<Task>()
                        .eq(Task::getId, task.getId())
                        .set(Task::getResultPath, (String) resp.getBody().get("image_path")));
                // [DB] sp_task_state_transition: PROCESSING→SUCCESS
                // [DB] trg_task_after_update: 自动创建History + formula.usage_count+1
                databaseMapper.callTaskStateTransition(task.getId(), "SUCCESS", null);
                log.info("公式任务[{}]渲染成功", task.getId());
            } else {
                throw new BusinessException("Python服务渲染失败");
            }
        } catch (Exception e) {
            log.warn("公式任务[{}]渲染失败: {}", task.getId(), e.getMessage());
            // [DB] sp_task_state_transition: PROCESSING→FAILED
            databaseMapper.callTaskStateTransition(task.getId(), "FAILED", e.getMessage());
        }
        return taskMapper.selectById(task.getId());
    }
}
