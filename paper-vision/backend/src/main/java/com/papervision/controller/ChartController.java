package com.papervision.controller;

import com.papervision.common.Result;
import com.papervision.dto.BatchChartTaskDTO;
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
    public Result<List<Task>> generateBatch(@Valid @RequestBody BatchChartTaskDTO dto) {
        Long userId = uid();
        List<Task> tasks = new ArrayList<>();
        for (Long chartId : dto.getChartIds()) {
            tasks.add(chartService.createChartTask(userId, chartId, dto.getFileId(), dto.getParams()));
        }
        return Result.ok(tasks);
    }
}
