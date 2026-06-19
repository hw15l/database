package com.papervision.service;

import com.papervision.entity.Formula;
import com.papervision.entity.Task;
import java.util.List;
import java.util.Map;

/**
 * 公式服务接口 — 公式查询与公式渲染任务创建
 */
public interface FormulaService {

    /** 获取所有公式列表(带缓存) */
    List<Formula> listFormulas();

    /** 按分类ID查询公式 */
    List<Formula> listByCategory(Long catId);

    /** 按公式编码查询单个公式(带缓存) */
    Formula getByCode(String formulaCode);

    /**
     * 创建公式渲染任务
     *
     * @param userId    用户ID
     * @param formulaId 公式ID
     * @param latex     自定义LaTeX(为null则使用模板)
     * @param params    自定义参数
     * @return 创建后的任务
     */
    Task createFormulaTask(Long userId, Long formulaId, String latex, Map<String, Object> params);
}
