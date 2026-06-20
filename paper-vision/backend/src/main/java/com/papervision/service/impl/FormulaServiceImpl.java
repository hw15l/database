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

    private static Map<String, Object> field(String key, String label, String type, Object... opts) {
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("key", key);
        f.put("label", label);
        f.put("type", type);
        if (opts.length > 0 && opts[0] != null) f.put("default", opts[0]);
        if (opts.length > 1 && opts[1] != null) f.put("step", opts[1]);
        if (opts.length > 2 && opts[2] != null) f.put("min", opts[2]);
        if (opts.length > 3 && opts[3] != null) f.put("max", opts[3]);
        if (opts.length > 4 && opts[4] != null) f.put("placeholder", opts[4]);
        return f;
    }

    private static final Map<String, List<Map<String, Object>>> PARAM_SCHEMAS = new LinkedHashMap<>();
    static {
        PARAM_SCHEMAS.put("integral", List.of(
                field("lower_limit", "下限 a", "number", 0, 0.5),
                field("upper_limit", "上限 b", "number", 1, 0.5),
                field("function_expr", "被积函数", "text", null, null, null, null, "sin / cos / exp / poly / f(x)")
        ));
        PARAM_SCHEMAS.put("double_integral", List.of(
                field("function_expr", "被积函数", "text", null, null, null, null, "f(x,y)")
        ));
        PARAM_SCHEMAS.put("sum", List.of(
                field("n", "上限 n", "number", 10, 1, 1, 1000),
                field("function_expr", "求和表达式", "text", null, null, null, null, "i^2")
        ));
        PARAM_SCHEMAS.put("multi_sum", List.of(
                field("n", "外层上限 n", "number", 4, 1, 1, 100),
                field("m", "内层上限 m", "number", 3, 1, 1, 100)
        ));
        PARAM_SCHEMAS.put("matrix", List.of(
                field("row1", "第一行", "text", null, null, null, null, "1 2 3"),
                field("row2", "第二行", "text", null, null, null, null, "4 5 6"),
                field("row3", "第三行", "text", null, null, null, null, "7 8 9")
        ));
        PARAM_SCHEMAS.put("determinant", List.of(
                field("a", "a (左上)", "number", 2, 1),
                field("b", "b (右上)", "number", 3, 1),
                field("c", "c (左下)", "number", 5, 1),
                field("d", "d (右下)", "number", 7, 1)
        ));
        PARAM_SCHEMAS.put("partial_diff", List.of(
                field("func", "函数名", "text", null, null, null, null, "f"),
                field("var", "变量", "text", null, null, null, null, "x"),
                field("order", "阶数", "number", 1, 1, 1, 5)
        ));
        PARAM_SCHEMAS.put("gradient", List.of(
                field("func", "函数名", "text", null, null, null, null, "f"),
                field("vars", "变量列表", "text", null, null, null, null, "x,y,z")
        ));
        PARAM_SCHEMAS.put("normal_dist", List.of(
                field("mu", "均值 μ", "number", 0, 1),
                field("sigma", "标准差 σ", "number", 1, 0.1, 0.1)
        ));
        PARAM_SCHEMAS.put("bayes", List.of(
                field("p_a", "P(A)", "number", 0.01, 0.01, 0, 1),
                field("p_b_given_a", "P(B|A)", "number", 0.95, 0.01, 0, 1),
                field("p_b", "P(B)", "number", 0.05, 0.01, 0, 1)
        ));
        PARAM_SCHEMAS.put("fourier", List.of());
        PARAM_SCHEMAS.put("matrix_mul", List.of());
        PARAM_SCHEMAS.put("polynomial", List.of(
                field("coeff_a", "二次系数 a", "number", 2, 0.5),
                field("coeff_b", "一次系数 b", "number", -3, 0.5),
                field("coeff_c", "常数项 c", "number", -5, 0.5)
        ));
        PARAM_SCHEMAS.put("exponential", List.of(
                field("exponent", "指数系数", "number", 2, 0.5)
        ));
        PARAM_SCHEMAS.put("logarithm", List.of(
                field("base", "底数", "text", null, null, null, null, "e 或数字")
        ));
        PARAM_SCHEMAS.put("sine_wave", List.of(
                field("amplitude", "振幅 A", "number", 2, 0.5, 0),
                field("frequency", "频率 ω", "number", 1, 0.5, 0),
                field("phase", "相位 φ", "number", 0, 0.1)
        ));
    }

    private void fillParamSchema(List<Formula> formulas) {
        for (Formula f : formulas) {
            f.setParamSchema(PARAM_SCHEMAS.getOrDefault(f.getFormulaCode(), List.of()));
        }
    }

    @Override
    @Cacheable(value = "formulaList")
    public List<Formula> listFormulas() {
        List<Formula> list = formulaMapper.selectList(
                new LambdaQueryWrapper<Formula>().orderByAsc(Formula::getSortOrder));
        fillParamSchema(list);
        return list;
    }

    @Override
    public List<Formula> listByCategory(Long catId) {
        List<Formula> list = formulaMapper.selectList(
                new LambdaQueryWrapper<Formula>().eq(Formula::getCatId, catId));
        fillParamSchema(list);
        return list;
    }

    @Override
    @Cacheable(value = "formula", key = "#formulaCode")
    public Formula getByCode(String formulaCode) {
        Formula f = formulaMapper.selectOne(
                new LambdaQueryWrapper<Formula>().eq(Formula::getFormulaCode, formulaCode));
        if (f != null) f.setParamSchema(PARAM_SCHEMAS.getOrDefault(f.getFormulaCode(), List.of()));
        return f;
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
