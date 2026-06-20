package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.dto.CreateFormulaTaskDTO;
import com.papervision.entity.Formula;
import com.papervision.entity.Task;
import com.papervision.entity.User;
import com.papervision.service.FormulaService;
import com.papervision.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/formula")
@RequiredArgsConstructor
public class FormulaController {
    private final FormulaService formulaService;
    private final UserService userService;
    private Long uid() {
        User u = userService.getCurrentUser(SecurityContextHolder.getContext().getAuthentication().getName());
        if (u == null) throw new BusinessException(401, "用户未登录或不存在");
        return u.getId();
    }

    @GetMapping("/list")
    public Result<List<Formula>> list() {
        return Result.ok(formulaService.listFormulas());
    }

    @GetMapping("/category/{catId}")
    public Result<List<Formula>> listByCategory(@PathVariable Long catId) {
        return Result.ok(formulaService.listByCategory(catId));
    }

    @PostMapping("/generate")
    public Result<Task> generate(@Valid @RequestBody CreateFormulaTaskDTO dto) {
        return Result.ok(formulaService.createFormulaTask(uid(), dto.getFormulaId(), dto.getLatex(), dto.getParams()));
    }
}
