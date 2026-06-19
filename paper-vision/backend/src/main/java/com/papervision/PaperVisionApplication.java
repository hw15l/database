package com.papervision;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@MapperScan("com.papervision.mapper")
public class PaperVisionApplication {
    public static void main(String[] args) {
        SpringApplication.run(PaperVisionApplication.class, args);
    }
}
