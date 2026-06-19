package com.papervision.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class UserUpdateDTO {
    @Email(message = "邮箱格式不正确")
    private String email;
    @Size(max = 50, message = "昵称最长50位")
    private String nickname;
    private String avatar;
}
