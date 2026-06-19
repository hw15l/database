package com.papervision.controller;

import com.papervision.entity.Formula;
import com.papervision.entity.Task;
import com.papervision.service.FormulaService;
import com.papervision.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/formula")
@RequiredArgsConstructor
public class FormulaController {
    private final FormulaService formulaService;
    private final UserService userService;
    private Long uid() { return userService.getCurrentUser(
        SecurityContextHolder.getContext().getAuthentication().getName()).getId(); }

    @GetMapping("/list")
    public ResponseEntity<List<Formula>> list() { return ResponseEntity.ok(formulaService.listFormulas()); }

    @GetMapping("/category/{catId}")
    public ResponseEntity<List<Formula>> listByCategory(@PathVariable Long catId) {
        return ResponseEntity.ok(formulaService.listByCategory(catId));
    }

    @PostMapping("/generate")
    public ResponseEntity<Task> generate(@RequestBody Map<String, Object> req) {
        Long formulaId = req.get("formulaId") != null ? Long.valueOf(req.get("formulaId").toString()) : null;
        if (formulaId == null) throw new RuntimeException("formulaId is required");
        String latex = (String) req.get("latex");
        Map<String, Object> params = (Map<String, Object>) req.get("params");
        return ResponseEntity.ok(formulaService.createFormulaTask(uid(), formulaId, latex, params));
    }
}
