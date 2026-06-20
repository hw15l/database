package com.papervision.controller;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.entity.User;
import com.papervision.mapper.UserMapper;
import com.papervision.service.DatabaseService;
import com.papervision.service.TaskService;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
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
        topN = Math.max(1, Math.min(topN, 100));
        return Result.ok(taskService.getUserRanking(topN));
    }

    @GetMapping("/users")
    public Result<List<User>> listUsers(@RequestParam(defaultValue = "200") int limit) {
        limit = Math.max(1, Math.min(limit, 500));
        List<User> users = userMapper.selectList(
                new LambdaQueryWrapper<User>().orderByDesc(User::getCreateTime).last("LIMIT " + limit));
        users.forEach(u -> u.setPassword(null));
        return Result.ok(users);
    }

    @PutMapping("/users/{id}/status")
    @CacheEvict(value = {"user", "userProfile360", "ranking"}, allEntries = true)
    public Result<Void> toggleUser(@PathVariable Long id, @RequestParam Integer status) {
        User user = userMapper.selectById(id);
        if (user == null) throw new BusinessException("用户不存在");
        if (status != 0 && status != 1) throw new BusinessException("状态值非法");
        user.setStatus(status);
        userMapper.updateById(user);
        return Result.ok();
    }

    @GetMapping("/trend")
    public Result<List<Map<String, Object>>> weeklyTrend(@RequestParam(defaultValue = "12") int weeks) {
        weeks = Math.max(1, Math.min(weeks, 52));
        return Result.ok(databaseService.getWeeklyTrend(weeks));
    }

    @GetMapping("/hot-items")
    public Result<List<Map<String, Object>>> hotItems(@RequestParam(defaultValue = "20") int limit) {
        limit = Math.max(1, Math.min(limit, 100));
        return Result.ok(databaseService.getHotItemsRanking(limit));
    }

    @GetMapping("/category-tree")
    public Result<List<Map<String, Object>>> categoryTree(@RequestParam(defaultValue = "chart") String type) {
        return Result.ok(databaseService.getCategoryTree(type));
    }

    @GetMapping("/activity")
    public Result<List<Map<String, Object>>> activityAudit(
            @RequestParam Long userId, @RequestParam(defaultValue = "50") int limit) {
        if (userId == null || userId <= 0) throw new BusinessException("userId无效");
        limit = Math.max(1, Math.min(limit, 200));
        return Result.ok(databaseService.getUserActivityAudit(userId, limit));
    }

    @PostMapping("/refresh-hot")
    public Result<Void> refreshHotItems() {
        databaseService.refreshHotItems();
        return Result.ok(null, "热门数据已刷新");
    }

    /** 刷新全部统计缓存 — 清除stats/ranking/hotItems/weeklyTrend + 刷新热点 */
    @PostMapping("/refresh-all")
    public Result<Void> refreshAll() {
        databaseService.refreshAllStats();
        return Result.ok(null, "全部统计已刷新");
    }
}
