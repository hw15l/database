package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("t_formula")
public class Formula {
    @TableId(type = IdType.AUTO)
    private Long id;
    private String formulaName;
    private String formulaCode;
    private Long catId;
    private String latexTemplate;
    private String description;
    private Long usageCount;
    private Integer isHot;
    private Integer sortOrder;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;
}
