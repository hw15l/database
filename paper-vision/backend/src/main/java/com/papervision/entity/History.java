package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("t_history")
public class History {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long userId;
    private Long taskId;
    private String taskType;
    private String chartName;
    private String formulaName;
    private String resultImage;
    private Integer isDeleted;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;

    private Integer rating;
    private String tags;
    private String snapshot;
    private Integer isFavorite;
    private LocalDateTime deletedAt;
    private Integer viewCount;
}
