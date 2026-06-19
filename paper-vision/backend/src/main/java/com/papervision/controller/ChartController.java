package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.dto.CreateChartTaskDTO;
import com.papervision.entity.Chart;
import com.papervision.entity.Task;
import com.papervision.service.ChartService;
import com.papervision.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/chart")
@RequiredArgsConstructor
public class ChartController {
    private final ChartService chartService;
    private final UserService userService;
    private Long uid() { return userService.getCurrentUser(
        SecurityContextHolder.getContext().getAuthentication().getName()).getId(); }

    @GetMapping("/list")
    public Result<List<Chart>> list() {
        return Result.ok(chartService.listCharts());
    }

    @GetMapping("/category/{catId}")
    public Result<List<Chart>> listByCategory(@PathVariable Long catId) {
        return Result.ok(chartService.listByCategory(catId));
    }

    @PostMapping("/generate")
    public Result<Task> generate(@Valid @RequestBody CreateChartTaskDTO dto) {
        return Result.ok(chartService.createChartTask(uid(), dto.getChartId(), dto.getFileId(), dto.getParams()));
    }

    @PostMapping("/generate-batch")
    public Result<List<Task>> generateBatch(@RequestBody Map<String, Object> req) {
        Object idsObj = req.get("chartIds");
        if (!(idsObj instanceof List)) throw new BusinessException("chartIds (array) is required");
        List<?> rawIds = (List<?>) idsObj;
        if (rawIds.isEmpty()) throw new BusinessException("请至少选择一种图表");
        Long fileId = req.get("fileId") != null ? Long.valueOf(req.get("fileId").toString()) : null;
        Map<String, Object> params = (Map<String, Object>) req.get("params");
        Long userId = uid();
        List<Task> tasks = new ArrayList<>();
        for (Object idObj : rawIds) {
            Long chartId = Long.valueOf(idObj.toString());
            tasks.add(chartService.createChartTask(userId, chartId, fileId, params));
        }
        return Result.ok(tasks);
    }
}
