package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.entity.User;
import com.papervision.mapper.UserMapper;
import com.papervision.service.DatabaseService;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {
    private final TaskService taskService;
    private final UserMapper userMapper;
    private final DatabaseService databaseService;

    @GetMapping("/stats")
    public Result<Map<String, Object>> stats() {
        return Result.ok(taskService.getStats());
    }

    @GetMapping("/ranking")
    public Result<Map<String, Object>> ranking(@RequestParam(defaultValue = "10") int topN) {
        return Result.ok(taskService.getUserRanking(topN));
    }

    @GetMapping("/users")
    public Result<List<User>> listUsers() {
        List<User> users = userMapper.selectList(null);
        users.forEach(u -> u.setPassword(null));
        return Result.ok(users);
    }

    @PutMapping("/users/{id}/status")
    public Result<Void> toggleUser(@PathVariable Long id, @RequestParam Integer status) {
        User user = userMapper.selectById(id);
        if (user == null) throw new BusinessException("用户不存在");
        user.setStatus(status);
        userMapper.updateById(user);
        return Result.ok();
    }

    @GetMapping("/trend")
    public Result<List<Map<String, Object>>> weeklyTrend(@RequestParam(defaultValue = "12") int weeks) {
        return Result.ok(databaseService.getWeeklyTrend(weeks));
    }

    @GetMapping("/hot-items")
    public Result<List<Map<String, Object>>> hotItems(@RequestParam(defaultValue = "20") int limit) {
        return Result.ok(databaseService.getHotItemsRanking(limit));
    }
}
