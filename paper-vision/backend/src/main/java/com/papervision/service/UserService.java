package com.papervision.service;

import com.papervision.dto.*;
import com.papervision.entity.User;
import java.util.Map;

public interface UserService {
    Map<String, Object> login(LoginDTO dto);
    Map<String, Object> register(RegisterDTO dto);
    User getCurrentUser(String username);
    void updateProfile(String username, UserUpdateDTO dto);
    void changePassword(String username, PasswordDTO dto);
}
