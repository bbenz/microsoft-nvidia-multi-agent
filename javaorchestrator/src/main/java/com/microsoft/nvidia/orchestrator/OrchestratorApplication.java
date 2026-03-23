package com.microsoft.nvidia.orchestrator;

import io.github.cdimascio.dotenv.Dotenv;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class OrchestratorApplication {

    public static void main(String[] args) {
        // Load .env from repo root (parent directory) before Spring starts
        loadDotenv();
        SpringApplication.run(OrchestratorApplication.class, args);
    }

    private static void loadDotenv() {
        try {
            var dotenv = Dotenv.configure()
                    .directory("../")
                    .ignoreIfMissing()
                    .load();

            dotenv.entries().forEach(entry -> {
                if (System.getenv(entry.getKey()) == null && System.getProperty(entry.getKey()) == null) {
                    System.setProperty(entry.getKey(), entry.getValue());
                }
            });
        } catch (Exception e) {
            // .env not found — that's fine, rely on real environment variables
        }
    }
}
