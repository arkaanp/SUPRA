use std::time::Duration;

use axum::{Extension, Json};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{
    auth::AuthUser,
    error::{AppError, AppResult},
    validation::{Validate, ValidatedJson},
};

const AGENT_TIMEOUT: Duration = Duration::from_secs(15);
const DEFAULT_GEMINI_MODEL: &str = "gemini-1.5-flash";

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ChatMessagePayload {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct ChatContextPayload {
    pub current_location: Option<String>,
    pub aqi: Option<i32>,
    pub weather: Option<String>,
    pub temperature: Option<String>,
    pub frequent_routes: Option<Vec<String>>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AgentChatRequest {
    pub message: String,
    #[serde(default)]
    pub history: Option<Vec<ChatMessagePayload>>,
    #[serde(default)]
    pub context: Option<ChatContextPayload>,
    #[serde(default)]
    pub api_key_override: Option<String>,
}

impl Validate for AgentChatRequest {
    fn validate(&self) -> Result<(), AppError> {
        let trimmed = self.message.trim();
        if trimmed.is_empty() {
            return Err(AppError::bad_request("Message cannot be empty"));
        }
        if trimmed.len() > 4000 {
            return Err(AppError::bad_request(
                "Message exceeds maximum allowed length of 4000 characters",
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentChatResponse {
    pub reply: String,
    pub model: String,
    pub simulated: bool,
}

/// POST /api/agent/chat
/// Handles conversational queries with Google AI Studio Gemini or offline smart fallback.
pub async fn chat(
    Extension(_user): Extension<AuthUser>,
    ValidatedJson(payload): ValidatedJson<AgentChatRequest>,
) -> AppResult<Json<AgentChatResponse>> {
    let response = process_chat(payload).await;
    Ok(Json(response))
}

pub async fn process_chat(payload: AgentChatRequest) -> AgentChatResponse {
    let api_key = payload
        .api_key_override
        .as_deref()
        .filter(|k| !k.trim().is_empty())
        .map(|s| s.trim().to_string())
        .or_else(|| {
            std::env::var("GEMINI_API_KEY")
                .ok()
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
        });

    let model = std::env::var("GEMINI_MODEL")
        .unwrap_or_else(|_| DEFAULT_GEMINI_MODEL.to_string());

    if let Some(key) = api_key {
        match call_gemini(&key, &model, &payload).await {
            Ok(reply) => {
                return AgentChatResponse {
                    reply,
                    model,
                    simulated: false,
                };
            }
            Err(err) => {
                tracing::warn!("Gemini API call failed, falling back to smart agent: {err}");
            }
        }
    }

    // Smart fallback if API key is absent or request failed
    let fallback_reply = generate_smart_fallback(&payload.message, payload.context.as_ref());
    AgentChatResponse {
        reply: fallback_reply,
        model: "supra-commute-agent".to_string(),
        simulated: true,
    }
}

async fn call_gemini(
    api_key: &str,
    model: &str,
    payload: &AgentChatRequest,
) -> Result<String, String> {
    let client = Client::builder()
        .timeout(AGENT_TIMEOUT)
        .build()
        .map_err(|e| e.to_string())?;

    let url = format!(
        "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}",
        model, api_key
    );

    let system_prompt = "You are SUPRA Agent 1, the premier AI Commute & Environmental Assistant \
dedicated to Greater Jakarta (Jabodetabek). You help commuters travel safely, cleanly, and efficiently.\n\
Key capabilities & domain expertise:\n\
1. Environmental conditions: Real-time AQI, PM2.5 levels, weather forecasts (rain, heat waves, storms).\n\
2. Commute advisory: Optimal departure windows to avoid traffic surges, localized flood spots (e.g., Rasuna Said, Daan Mogot, Kemang), and high pollution spikes.\n\
3. Health recommendations: Specific advice on wearing masks (KN95/N95) when AQI exceeds 100 or when traveling by motorcycle.\n\
4. Multi-modal transit: Recommendations for MRT Jakarta (North-South line), LRT Jabodebek, KRL Commuter Line, and TransJakarta busway, including Odd-Even (Ganjil-Genap) rule navigation.\n\
Style: Clear, friendly, actionable, and formatted in clean GitHub-style Markdown with bullet points where appropriate. \
Always reply in the same language as the user (Indonesian or English).";

    // Build context prefix
    let mut context_intro = String::new();
    if let Some(ctx) = &payload.context {
        context_intro.push_str("\n[Current User Environmental Context]:\n");
        if let Some(loc) = &ctx.current_location {
            context_intro.push_str(&format!("- Active Location: {loc}\n"));
        }
        if let Some(aqi) = ctx.aqi {
            context_intro.push_str(&format!("- Current AQI: {aqi}\n"));
        }
        if let Some(w) = &ctx.weather {
            context_intro.push_str(&format!("- Weather: {w}\n"));
        }
        if let Some(t) = &ctx.temperature {
            context_intro.push_str(&format!("- Temperature: {t}\n"));
        }
        if let Some(routes) = &ctx.frequent_routes {
            if !routes.is_empty() {
                context_intro.push_str(&format!("- Saved Commute Routes: {}\n", routes.join(", ")));
            }
        }
        context_intro.push_str("\n");
    }

    let mut contents = Vec::new();

    // Include recent history if provided
    if let Some(history) = &payload.history {
        for msg in history.iter().rev().take(8).rev() {
            let role = match msg.role.as_str() {
                "user" => "user",
                _ => "model",
            };
            contents.push(json!({
                "role": role,
                "parts": [{ "text": msg.content }]
            }));
        }
    }

    // Add current user prompt with context
    let prompt_with_context = if !context_intro.is_empty() {
        format!("{}{}", context_intro, payload.message)
    } else {
        payload.message.clone()
    };

    contents.push(json!({
        "role": "user",
        "parts": [{ "text": prompt_with_context }]
    }));

    let request_body = json!({
        "system_instruction": {
            "parts": [{ "text": system_prompt }]
        },
        "contents": contents,
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 1000
        }
    });

    let resp = client
        .post(&url)
        .header("Content-Type", "application/json")
        .json(&request_body)
        .send()
        .await
        .map_err(|e| format!("HTTP request error: {e}"))?;

    let status = resp.status();
    if !status.is_success() {
        let err_text = resp.text().await.unwrap_or_default();
        return Err(format!("Gemini API error ({status}): {err_text}"));
    }

    let json_val: Value = resp.json().await.map_err(|e| format!("JSON parse error: {e}"))?;

    if let Some(text) = json_val
        .pointer("/candidates/0/content/parts/0/text")
        .and_then(|v| v.as_str())
    {
        Ok(text.trim().to_string())
    } else {
        Err("No candidate text found in Gemini response".to_string())
    }
}

/// Generates a realistic, domain-aware response when Gemini API key is not yet configured.
pub fn generate_smart_fallback(query: &str, context: Option<&ChatContextPayload>) -> String {
    let lower = query.to_lowercase();
    let loc = context
        .and_then(|c| c.current_location.as_deref())
        .unwrap_or("Greater Jakarta");
    let aqi_val = context.and_then(|c| c.aqi).unwrap_or(72);
    let weather_val = context
        .and_then(|c| c.weather.as_deref())
        .unwrap_or("Moderate");

    let aqi_status = match aqi_val {
        0..=50 => "Good (Healthy)",
        51..=100 => "Moderate (Acceptable)",
        101..=150 => "Unhealthy for Sensitive Groups",
        151..=200 => "Unhealthy",
        201..=300 => "Very Unhealthy",
        _ => "Hazardous",
    };

    let reply = if lower.contains("aqi") || lower.contains("air") || lower.contains("udara") || lower.contains("polusi") {
        format!(
            "### 🌬️ Air Quality Outlook for {loc}\n\n\
            - **Current AQI:** {aqi_val} ({aqi_status})\n\
            - **Primary Pollutant:** PM2.5 particles\n\
            - **Health Guidance:** {}\n\n\
            💡 **Commuter Tip:** If traveling on a two-wheeler or walking along major arterials (e.g. Sudirman, Gatot Subroto), wear a well-fitted KN95/KF94 mask to filter fine particulates.",
            if aqi_val > 100 {
                "Sensitive individuals should limit prolonged outdoor exertion. Keep vehicle windows closed during slow traffic."
            } else {
                "Air quality is generally acceptable. Commuters with respiratory conditions should monitor midday changes."
            }
        )
    } else if lower.contains("rain") || lower.contains("hujan") || lower.contains("weather") || lower.contains("cuaca") {
        format!(
            "### 🌧️ Weather & Commute Forecast for {loc}\n\n\
            - **Current Status:** {weather_val}\n\
            - **Precipitation Probability:** 35% - 60% during afternoon hours\n\
            - **Flood-Prone Choke Points to Monitor:**\n\
              • Jl. Rasuna Said & Gatot Subroto corridor\n\
              • Kemang Raya & Bangka underpasses\n\
              • Daan Mogot Westbound\n\n\
            💡 **Commuter Tip:** Rain in Jakarta causes an estimated 25–40% increase in road transit duration. Consider taking MRT or LRT for weather-independent commute times."
        )
    } else if lower.contains("traffic") || lower.contains("macet") || lower.contains("route") || lower.contains("rute") || lower.contains("scbd") {
        "### 🚦 Jakarta Traffic & Routing Recommendation\n\n\
        - **Peak Congestion Windows:** 07:15 – 09:30 WIB and 17:00 – 20:00 WIB\n\
        - **Ganjil-Genap (Odd-Even):** Enforced on 25 main thoroughfares on weekdays (06:00–10:00 & 16:00–21:00 WIB).\n\
        - **Optimal Strategy:**\n\
          1. **Early Departure:** Leaving 20–30 minutes before 17:00 saves approximately 35 minutes in transit.\n\
          2. **Transit Hybrid:** Park & Ride at MRT Lebak Bulus or Fatmawati to reach the CBD without road congestion.\n\
          3. **TransJakarta:** Dedicated busway lanes provide reliable travel times along Corridor 1 (Blok M – Kota)."
            .to_string()
    } else if lower.contains("time") || lower.contains("jam") || lower.contains("berangkat") || lower.contains("leave") {
        format!(
            "### ⏱️ Best Departure Window Recommendation\n\n\
            Based on current environmental factors around {loc} (AQI: {aqi_val}, Weather: {weather_val}):\n\n\
            - **Recommended Departure:** **15:45 – 16:15 WIB** (Before evening rush hour traffic builds up and pollutant concentration rises).\n\
            - **Alternative Window:** **After 19:45 WIB** (Traffic volume decreases, though nighttime surface inversions may trap particulates).\n\n\
            Leaving during the recommended window typically yields the lowest combined air pollution exposure and travel delay."
        )
    } else if lower.contains("mask") || lower.contains("masker") || lower.contains("health") || lower.contains("sehat") {
        format!(
            "### 😷 Commuter Health & Mask Advisory\n\n\
            - **Current Air Quality:** AQI {aqi_val} ({aqi_status})\n\
            - **Mask Recommendation:** {}\n\
            - **Motorcyclists:** Strongly advised to wear protective masks at all times due to proximity to direct vehicle exhaust.\n\
            - **Sensitive Groups:** Children, elderly, and individuals with asthma should minimize outdoor workouts when AQI exceeds 100.",
            if aqi_val > 100 {
                "**KN95 or N95 mask strongly advised** for any outdoor exposure or motorcycle commuting."
            } else {
                "Surgical mask recommended for roadside walking; standard fabric masks do not filter PM2.5."
            }
        )
    } else {
        format!(
            "### 👋 Hello! I'm SUPRA Agent 1, your Jakarta Commute & Eco Advisor.\n\n\
            I'm here to help you navigate {loc} with real-time environmental intelligence:\n\n\
            • 🌬️ **Air Quality Insights:** Real-time AQI ({aqi_val}), PM2.5 readings & mask advice\n\
            • 🌧️ **Weather Impact:** Rain predictions and flood-prone road warnings\n\
            • 🚦 **Smart Commuting:** Peak traffic avoidance, Ganjil-Genap rules, and MRT/LRT/KRL transit advice\n\
            • ⏱️ **Departure Timing:** Optimal departure windows to minimize exposure and travel delay\n\n\
            *Ask me anything, like \"How is the air quality right now?\", \"Will it rain this afternoon?\", or \"What's the best time to leave for SCBD?\"*"
        )
    };

    format!(
        "{reply}\n\n*(Note: Running in SUPRA built-in offline intelligence mode. Set `GEMINI_API_KEY` in `backend/.env` or app settings for live Google AI Studio generation.)*"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_empty_message() {
        let req = AgentChatRequest {
            message: "   ".to_string(),
            history: None,
            context: None,
            api_key_override: None,
        };
        assert!(req.validate().is_err());
    }

    #[test]
    fn validates_reasonable_message() {
        let req = AgentChatRequest {
            message: "What is the best route to SCBD?".to_string(),
            history: None,
            context: None,
            api_key_override: None,
        };
        assert!(req.validate().is_ok());
    }

    #[test]
    fn generates_fallback_for_weather_query() {
        let ctx = ChatContextPayload {
            current_location: Some("Kuningan, Jakarta".to_string()),
            aqi: Some(85),
            weather: Some("Light Rain".to_string()),
            temperature: Some("28°C".to_string()),
            frequent_routes: None,
        };
        let reply = generate_smart_fallback("Will it rain today?", Some(&ctx));
        assert!(reply.contains("Weather & Commute Forecast"));
        assert!(reply.contains("Kuningan, Jakarta"));
        assert!(reply.contains("GEMINI_API_KEY"));
    }

    #[test]
    fn generates_fallback_for_aqi_query() {
        let ctx = ChatContextPayload {
            current_location: Some("Monas".to_string()),
            aqi: Some(135),
            weather: Some("Hazy".to_string()),
            temperature: Some("32°C".to_string()),
            frequent_routes: None,
        };
        let reply = generate_smart_fallback("Bagaimana polusi udara hari ini?", Some(&ctx));
        assert!(reply.contains("Air Quality Outlook"));
        assert!(reply.contains("135"));
        assert!(reply.contains("Sensitive individuals"));
    }
}
