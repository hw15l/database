package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("t_user")
public class User {
    @TableId(type = IdType.AUTO)
    private Long id;
    private String username;
    private String password;
    private String email;
    private String nickname;
    private String avatar;
    private Integer status;
    private LocalDateTime lastLoginTime;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;
    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updateTime;

    private String profile;
    private Integer loginCount;
    private String lastLoginIp;
    private Integer accountAgeDays;
    private Integer isActive;
}
