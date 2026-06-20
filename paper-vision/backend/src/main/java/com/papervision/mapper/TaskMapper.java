package com.papervision.mapper;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.papervision.entity.Task;
import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface TaskMapper extends BaseMapper<Task> {
}
