//! Supabase access-token validation. Only configured project keys are trusted.
use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Json,
    extract::{Request, State},
    http::{StatusCode, header},
    middleware::Next,
    response::{IntoResponse, Response},
};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header, jwk::JwkSet};
use serde::Deserialize;
use tokio::sync::RwLock;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct AuthUser {
    pub id: Uuid,
    pub email: String,
}

#[derive(Debug, Deserialize, Clone)]
struct Claims {
    sub: String,
    email: String,
    role: String,
}

#[derive(Clone)]
pub struct AuthVerifier {
    issuer: String,
    audience: String,
    jwks_url: String,
    client: reqwest::Client,
    cache: Arc<RwLock<Option<(Instant, JwkSet)>>>,
}

impl AuthVerifier {
    pub fn new(project_url: &str, audience: &str) -> anyhow::Result<Self> {
        let url = reqwest::Url::parse(project_url)?;
        anyhow::ensure!(
            url.scheme() == "https"
                && url.host_str().is_some()
                && url.username().is_empty()
                && url.password().is_none()
                && url.path() == "/"
                && url.query().is_none()
                && url.fragment().is_none(),
            "SUPABASE_URL must be an HTTPS project URL"
        );
        let issuer = format!("{}/auth/v1", project_url.trim_end_matches('/'));
        Ok(Self {
            jwks_url: format!("{issuer}/.well-known/jwks.json"),
            issuer,
            audience: audience.to_owned(),
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
            cache: Arc::default(),
        })
    }

    pub async fn verify(&self, token: &str) -> anyhow::Result<AuthUser> {
        let header = decode_header(token)?;
        // Never allow symmetric keys, 'none', or algorithms selected by arbitrary URLs.
        anyhow::ensure!(
            matches!(header.alg, Algorithm::ES256 | Algorithm::RS256),
            "Unsupported signing algorithm"
        );
        let kid = header
            .kid
            .ok_or_else(|| anyhow::anyhow!("Missing signing key ID"))?;
        let mut cache = self.cache.write().await;
        // Rate-limit unknown-key refreshes: a forged kid must not trigger a
        // new outbound JWKS request on every incoming HTTP request.
        let refresh = cache.as_ref().is_none_or(|(at, keys)| {
            at.elapsed() >= Duration::from_secs(300)
                || (keys.find(&kid).is_none() && at.elapsed() >= Duration::from_secs(30))
        });
        if refresh {
            let keys = self
                .client
                .get(&self.jwks_url)
                .send()
                .await?
                .error_for_status()?
                .json::<JwkSet>()
                .await?;
            *cache = Some((Instant::now(), keys));
        }
        // Refresh once on unknown kids to support key rotation; still fail closed.
        let jwk = cache
            .as_ref()
            .unwrap()
            .1
            .find(&kid)
            .ok_or_else(|| anyhow::anyhow!("Unknown signing key"))?;
        if let Some(alg) = jwk.common.key_algorithm {
            anyhow::ensure!(
                matches!(
                    (alg, header.alg),
                    (jsonwebtoken::jwk::KeyAlgorithm::ES256, Algorithm::ES256)
                        | (jsonwebtoken::jwk::KeyAlgorithm::RS256, Algorithm::RS256)
                ),
                "Signing algorithm mismatch"
            );
        }
        let key = DecodingKey::from_jwk(jwk)?;
        let validation = self.validation(header.alg);
        let claims = decode::<Claims>(token, &key, &validation)?.claims;
        user_from_claims(claims)
    }

    fn validation(&self, algorithm: Algorithm) -> Validation {
        let mut validation = Validation::new(algorithm);
        validation.set_issuer(&[&self.issuer]);
        validation.set_audience(&[&self.audience]);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        validation.validate_nbf = true;
        validation.leeway = 0;
        validation
    }
}

fn user_from_claims(claims: Claims) -> anyhow::Result<AuthUser> {
    anyhow::ensure!(
        claims.role == "authenticated",
        "Not an authenticated user token"
    );
    let id = Uuid::parse_str(&claims.sub)?;
    anyhow::ensure!(!id.is_nil(), "Invalid user UUID");
    Ok(AuthUser {
        id,
        email: claims.email,
    })
}

pub async fn authenticate(
    State(verifier): State<AuthVerifier>,
    mut request: Request,
    next: Next,
) -> Response {
    let token = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .filter(|s| !s.is_empty());
    let user = match token {
        Some(token) => verifier.verify(token).await.ok(),
        None => None,
    };
    match user {
        Some(user) => {
            request.extensions_mut().insert(user);
            next.run(request).await
        }
        None => (
            StatusCode::UNAUTHORIZED,
            [(header::WWW_AUTHENTICATE, "Bearer")],
            Json(serde_json::json!({"error": "Invalid or missing access token", "code": "unauthorized"})),
        )
            .into_response(),
    }
}

pub fn require_self(user: &AuthUser, id: Uuid) -> crate::error::AppResult<()> {
    if user.id != id {
        return Err(crate::error::AppError::NotFound);
    }
    Ok(())
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::*;
    use axum::{Router, routing::get};
    use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
    use jsonwebtoken::{EncodingKey, Header, encode};
    use ring::{
        rand::SystemRandom,
        signature::{ECDSA_P256_SHA256_ASN1_SIGNING, EcdsaKeyPair, KeyPair},
    };
    use serde_json::json;

    pub struct Fixture {
        pub verifier: AuthVerifier,
        signing_key: EncodingKey,
        server: tokio::task::JoinHandle<()>,
    }

    impl Fixture {
        pub async fn new() -> Self {
            let rng = SystemRandom::new();
            let private =
                EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng).unwrap();
            let pair =
                EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, private.as_ref(), &rng)
                    .unwrap();
            let public = pair.public_key().as_ref();
            let keys = json!({"keys": [{"kty": "EC", "crv": "P-256", "alg": "ES256", "kid": "test-key",
                "x": URL_SAFE_NO_PAD.encode(&public[1..33]), "y": URL_SAFE_NO_PAD.encode(&public[33..65])}]});
            let app = Router::new().route("/jwks", get(move || async move { Json(keys) }));
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
            let mut verifier =
                AuthVerifier::new("https://test.supabase.co", "authenticated").unwrap();
            verifier.jwks_url = format!("http://{address}/jwks");
            Self {
                verifier,
                signing_key: EncodingKey::from_ec_der(private.as_ref()),
                server,
            }
        }

        pub fn token(&self, id: Uuid, email: &str) -> String {
            let mut header = Header::new(Algorithm::ES256);
            header.kid = Some("test-key".into());
            encode(
                &header,
                &json!({"iss": "https://test.supabase.co/auth/v1", "aud": "authenticated",
                "exp": chrono::Utc::now().timestamp() + 600, "sub": id, "email": email,
                "role": "authenticated"}),
                &self.signing_key,
            )
            .unwrap()
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            self.server.abort();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Router, body::Body, routing::get};
    use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
    use jsonwebtoken::{EncodingKey, Header, encode};
    use ring::{
        rand::SystemRandom,
        signature::{ECDSA_P256_SHA256_ASN1_SIGNING, EcdsaKeyPair, KeyPair},
    };
    use serde_json::{Value, json};
    use tower::ServiceExt;

    async fn fixture() -> (AuthVerifier, EncodingKey, tokio::task::JoinHandle<()>) {
        let rng = SystemRandom::new();
        let private = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng).unwrap();
        let pair =
            EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, private.as_ref(), &rng)
                .unwrap();
        let public = pair.public_key().as_ref();
        let jwks = json!({"keys": [{"kty": "EC", "crv": "P-256", "alg": "ES256", "use": "sig", "kid": "test-key",
            "x": URL_SAFE_NO_PAD.encode(&public[1..33]), "y": URL_SAFE_NO_PAD.encode(&public[33..65])}]});
        let app = Router::new().route("/jwks", get(move || async move { Json(jwks) }));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let mut verifier = AuthVerifier::new("https://test.supabase.co", "authenticated").unwrap();
        verifier.jwks_url = format!("http://{address}/jwks");
        (verifier, EncodingKey::from_ec_der(private.as_ref()), task)
    }

    fn claims() -> Value {
        json!({"iss": "https://test.supabase.co/auth/v1", "aud": "authenticated",
            "exp": chrono::Utc::now().timestamp() + 600,
            "sub": "a1b2c3d4-0000-4000-8000-000000000001", "email": "test@example.com", "role": "authenticated"})
    }

    fn token(claims: &Value, key: &EncodingKey, kid: &str) -> String {
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(kid.into());
        encode(&header, claims, key).unwrap()
    }

    #[tokio::test]
    async fn verifies_signature_and_required_claims_against_jwks() {
        let (verifier, key, server) = fixture().await;
        let valid = claims();
        assert_eq!(
            verifier
                .verify(&token(&valid, &key, "test-key"))
                .await
                .unwrap()
                .id
                .to_string(),
            valid["sub"].as_str().unwrap()
        );
        for (field, value) in [
            ("iss", json!("https://attacker.example/auth/v1")),
            ("aud", json!("other-audience")),
            ("exp", json!(chrono::Utc::now().timestamp() - 10)),
            ("sub", json!("not-a-uuid")),
            ("sub", json!(Uuid::nil().to_string())),
            ("role", json!("service_role")),
            ("nbf", json!(chrono::Utc::now().timestamp() + 600)),
        ] {
            let mut invalid = valid.clone();
            invalid[field] = value;
            assert!(
                verifier
                    .verify(&token(&invalid, &key, "test-key"))
                    .await
                    .is_err(),
                "accepted invalid {field}"
            );
        }
        for field in ["iss", "aud", "exp", "sub"] {
            let mut invalid = valid.clone();
            invalid.as_object_mut().unwrap().remove(field);
            assert!(
                verifier
                    .verify(&token(&invalid, &key, "test-key"))
                    .await
                    .is_err(),
                "accepted missing {field}"
            );
        }
        assert!(
            verifier
                .verify(&token(&valid, &key, "unknown-key"))
                .await
                .is_err()
        );
        let (_, attacker_key, attacker_server) = fixture().await;
        assert!(
            verifier
                .verify(&token(&valid, &attacker_key, "test-key"))
                .await
                .is_err()
        );
        let mut header = Header::new(Algorithm::HS256);
        header.kid = Some("test-key".into());
        let symmetric = encode(
            &header,
            &valid,
            &EncodingKey::from_secret(b"not-a-trusted-secret"),
        )
        .unwrap();
        assert!(verifier.verify(&symmetric).await.is_err());
        attacker_server.abort();
        server.abort();
    }

    #[tokio::test]
    async fn middleware_rejects_missing_invalid_tokens_and_injects_verified_subject() {
        let (verifier, key, server) = fixture().await;
        let app = Router::new()
            .route(
                "/",
                get(
                    |axum::Extension(user): axum::Extension<AuthUser>| async move {
                        user.id.to_string()
                    },
                ),
            )
            .layer(axum::middleware::from_fn_with_state(verifier, authenticate));
        for value in [None, Some("Bearer invalid"), Some("Basic invalid")] {
            let mut request = Request::builder().uri("/");
            if let Some(value) = value {
                request = request.header(header::AUTHORIZATION, value);
            }
            assert_eq!(
                app.clone()
                    .oneshot(request.body(Body::empty()).unwrap())
                    .await
                    .unwrap()
                    .status(),
                StatusCode::UNAUTHORIZED
            );
        }
        let request = Request::builder()
            .uri("/")
            .header(
                header::AUTHORIZATION,
                format!("Bearer {}", token(&claims(), &key, "test-key")),
            )
            .body(Body::empty())
            .unwrap();
        assert_eq!(app.oneshot(request).await.unwrap().status(), StatusCode::OK);
        server.abort();
    }

    #[test]
    fn path_id_cannot_impersonate_another_user() {
        let user = AuthUser {
            id: Uuid::new_v4(),
            email: "a@example.com".into(),
        };
        assert!(require_self(&user, user.id).is_ok());
        assert!(require_self(&user, Uuid::new_v4()).is_err());
    }

    #[tokio::test]
    async fn api_rejects_unauthed_and_spoofed_user_paths_without_database() {
        let fixture = test_support::Fixture::new().await;
        let state = crate::db::AppState {
            pool: sqlx::postgres::PgPoolOptions::new()
                .connect_lazy("postgres://localhost/unused_test_database")
                .unwrap(),
        };
        let app = crate::routes::create_router(state, fixture.verifier.clone());
        let owner = Uuid::new_v4();
        let other = Uuid::new_v4();
        let bearer = format!("Bearer {}", fixture.token(owner, "owner@example.com"));
        for path in [
            "/api/users",
            "/api/trips",
            "/api/routes",
            "/api/predictions",
            "/api/notifications",
        ] {
            let req = Request::builder().uri(path).body(Body::empty()).unwrap();
            assert_eq!(
                app.clone().oneshot(req).await.unwrap().status(),
                StatusCode::UNAUTHORIZED
            );
        }
        for path in [
            format!("/api/users/{other}"),
            format!("/api/users/{other}/trips"),
            format!("/api/users/{other}/preferences"),
            format!("/api/users/{other}/notifications"),
            format!("/api/trips?user_id={other}"),
        ] {
            let req = Request::builder()
                .uri(&path)
                .header(header::AUTHORIZATION, &bearer)
                .body(Body::empty())
                .unwrap();
            assert_eq!(
                app.clone().oneshot(req).await.unwrap().status(),
                StatusCode::NOT_FOUND,
                "{path}"
            );
        }
    }
}
