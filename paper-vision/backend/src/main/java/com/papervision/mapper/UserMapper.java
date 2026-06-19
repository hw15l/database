package com.papervision.mapper;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.papervision.entity.User;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Select;
import java.util.List;
import java.util.Map;

@Mapper
public interface UserMapper extends BaseMapper<User> {
    @Select("SELECT r.role_code FROM t_user_role ur JOIN t_role r ON ur.role_id = r.id WHERE ur.user_id = #{userId}")
    List<Map<String, Object>> selectUserRoles(Long userId);

    @Insert("INSERT INTO t_user_role (user_id, role_id) SELECT #{userId}, id FROM t_role WHERE role_code = 'ROLE_USER'")
    void insertDefaultRole(Long userId);
}
