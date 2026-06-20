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

    /** 系统概览 — [DB] v_trend_analysis_weekly + v_hot_items_unified_ranking */
    @GetMapping("/stats")
    public Result<Map<String, Object>> stats() {
        return Result.ok(taskService.getStats());
    }

    /** 用户排行 — [DB] v_user_profile_360视图(窗口函数RANK排名+用户分层) */
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

    /** 周趋势 — [DB] v_trend_analysis_weekly: LAG环比 + SUM OVER累计 */
    @GetMapping("/trend")
    public Result<List<Map<String, Object>>> weeklyTrend(@RequestParam(defaultValue = "12") int weeks) {
        return Result.ok(databaseService.getWeeklyTrend(weeks));
    }

    /** 热门排行 — [DB] v_hot_items_unified_ranking: UNION ALL + DENSE_RANK */
    @GetMapping("/hot-items")
    public Result<List<Map<String, Object>>> hotItems(@RequestParam(defaultValue = "20") int limit) {
        return Result.ok(databaseService.getHotItemsRanking(limit));
    }

    /** 分类树 — [DB] v_category_tree_full: 闭包表JOIN + JSON_ARRAYAGG */
    @GetMapping("/category-tree")
    public Result<List<Map<String, Object>>> categoryTree(@RequestParam(defaultValue = "chart") String type) {
        return Result.ok(databaseService.getCategoryTree(type));
    }

    /** 活动审计 — [DB] v_system_activity_audit: UNION ALL多源 + JSON_OBJECT */
    @GetMapping("/activity")
    public Result<List<Map<String, Object>>> activityAudit(
            @RequestParam Long userId, @RequestParam(defaultValue = "50") int limit) {
        return Result.ok(databaseService.getUserActivityAudit(userId, limit));
    }
}
