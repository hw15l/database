package com.papervision.service;

import com.papervision.dto.*;
import com.papervision.entity.User;
import java.util.Map;

/**
 * 用户服务接口 — 认证、注册、个人资料管理
 */
public interface UserService {

    /**
     * 用户登录
     * @return 包含token、user、roles的Map
     */
    Map<String, Object> login(LoginDTO dto);

    /**
     * 用户注册(自动分配ROLE_USER角色)
     * @return 包含token、user、roles的Map
     */
    Map<String, Object> register(RegisterDTO dto);

    /** 根据用户名查询当前用户(带缓存) */
    User getCurrentUser(String username);

    /** 更新用户资料(邮箱/昵称/头像) */
    void updateProfile(String username, UserUpdateDTO dto);

    /** 修改密码(需验证原密码) */
    void changePassword(String username, PasswordDTO dto);
}
