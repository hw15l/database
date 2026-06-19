package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("t_chart")
public class Chart {
    @TableId(type = IdType.AUTO)
    private Long id;
    private String chartName;
    private String chartCode;
    private Long catId;
    private String description;
    private String defaultParams;
    private Long usageCount;
    private Integer isHot;
    private Integer sortOrder;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;

    private Integer complexityLevel;
    private String tags;
    private String version;
    private String previewImage;
    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private String popularityRank;
}
