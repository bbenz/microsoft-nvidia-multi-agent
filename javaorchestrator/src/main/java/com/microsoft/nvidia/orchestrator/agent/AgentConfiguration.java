package com.microsoft.nvidia.orchestrator.agent;

import com.microsoft.nvidia.orchestrator.config.OrchestratorConfig;
import dev.langchain4j.memory.chat.MessageWindowChatMemory;
import dev.langchain4j.model.openai.OpenAiChatModel;
import dev.langchain4j.service.AiServices;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;

@Configuration
public class AgentConfiguration {

    private static final Logger logger = LoggerFactory.getLogger(AgentConfiguration.class);

    @Bean
    @Lazy
    public OpenAiChatModel openAiChatModel(OrchestratorConfig config) {
        var builder = OpenAiChatModel.builder()
                .apiKey(config.getOpenai().getApiKey())
                .modelName(config.getOpenai().getModel());

        var apiBase = config.getOpenai().getApiBase();
        if (apiBase != null && !apiBase.isBlank()) {
            builder.baseUrl(apiBase);
            logger.info("OpenAI client configured with custom baseUrl: {}", apiBase);
        }

        return builder.build();
    }

    @Bean
    @Lazy
    public InvoiceParsingAgent invoiceParsingAgent(OpenAiChatModel chatModel, InvoiceParsingTools tools) {
        return AiServices.builder(InvoiceParsingAgent.class)
                .chatModel(chatModel)
                .tools(tools)
                .chatMemory(MessageWindowChatMemory.withMaxMessages(10))
                .build();
    }
}
