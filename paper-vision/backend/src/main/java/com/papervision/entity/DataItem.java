package com.papervision.entity;

import com.baomidou.mybatisplus.annotation.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@TableName("t_data_item")
public class DataItem {
    @TableId(type = IdType.AUTO)
    private Long id;
    private Long fileId;
    private Integer rowIndex;
    private String colName;
    private String colValue;
    private String dataType;
    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createTime;
    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private Integer valueLength;
    @TableField(insertStrategy = FieldStrategy.NEVER, updateStrategy = FieldStrategy.NEVER)
    private Integer isNullVal;
}
