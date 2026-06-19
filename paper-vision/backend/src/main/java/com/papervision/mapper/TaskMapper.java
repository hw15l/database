package com.papervision.mapper;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.papervision.entity.Task;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Select;
import java.util.List;
import java.util.Map;

@Mapper
public interface TaskMapper extends BaseMapper<Task> {
    @Select("SELECT u.id, u.username, u.nickname, COUNT(t.id) AS total_tasks, " +
            "SUM(CASE WHEN t.status='SUCCESS' THEN 1 ELSE 0 END) AS success_count " +
            "FROM t_user u LEFT JOIN t_task t ON u.id = t.user_id " +
            "GROUP BY u.id, u.username, u.nickname ORDER BY total_tasks DESC LIMIT #{topN}")
    List<Map<String, Object>> getUserRanking(int topN);
}
