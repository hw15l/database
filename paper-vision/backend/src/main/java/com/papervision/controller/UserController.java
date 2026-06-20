package com.papervision.controller;

import com.papervision.common.BusinessException;
import com.papervision.common.Result;
import com.papervision.dto.*;
import com.papervision.entity.User;
import com.papervision.service.DatabaseService;
import com.papervision.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/user")
@RequiredArgsConstructor
public class UserController {
    private final UserService userService;
    private final DatabaseService databaseService;
    private String username() { return SecurityContextHolder.getContext().getAuthentication().getName(); }
    private Long uid() {
        User u = userService.getCurrentUser(username());
        if (u == null) throw new BusinessException(401, "用户未登录或不存在");
        return u.getId();
    }

    @GetMapping("/me")
    public Result<User> me() {
        User user = userService.getCurrentUser(username());
        if (user == null) throw new BusinessException(401, "用户未登录或不存在");
        user.setPassword(null);
        return Result.ok(user);
    }

    /** 用户360画像 — [DB] v_user_profile_360: 6表JOIN + RANK/PERCENT_RANK + JSON_ARRAYAGG */
    @GetMapping("/profile360")
    public Result<Map<String, Object>> profile360() {
        return Result.ok(databaseService.getUserProfile360(uid()));
    }

    /** 配额查询 — [DB] sp_quota_check_and_enforce: JSON_EXTRACT角色元数据 */
    @GetMapping("/quota")
    public Result<Map<String, Object>> quota() {
        return Result.ok(databaseService.checkQuota(uid()));
    }

    /** 智能推荐 — [DB] sp_smart_recommend: 协同过滤(相似用户) + 热门兜底 */
    @GetMapping("/recommend")
    public Result<List<Map<String, Object>>> recommend(
            @RequestParam(defaultValue = "5") int limit) {
        return Result.ok(databaseService.getSmartRecommendations(uid(), limit));
    }

    /** 偏好矩阵 — [DB] v_user_preference_matrix: 条件聚合 + JSON_OBJECTAGG分类分布 */
    @GetMapping("/preference")
    public Result<Map<String, Object>> preference() {
        return Result.ok(databaseService.getUserPreference(uid()));
    }

    @PutMapping("/profile")
    public Result<Void> updateProfile(@Valid @RequestBody UserUpdateDTO dto) {
        userService.updateProfile(username(), dto);
        return Result.ok();
    }

    @PutMapping("/password")
    public Result<Void> changePassword(@Valid @RequestBody PasswordDTO dto) {
        userService.changePassword(username(), dto);
        return Result.ok();
    }
}
