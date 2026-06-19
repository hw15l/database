package com.papervision.dto;

import lombok.Data;

@Data
public class UserUpdateDTO {
    private String email;
    private String nickname;
    private String avatar;
}
