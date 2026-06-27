"""Application settings, loaded from environment variables (pydantic-settings).

Secrets are NEVER hardcoded (steering: stack.md / conventions.md). Copy `.env.example`
to `.env` for local development.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="", extra="ignore")

    # App
    zexo_env: str = "development"
    zexo_debug: bool = True
    zexo_port: int = 8000

    # Database
    database_url: str = "postgresql://postgres:postgres@localhost:5432/zexo"

    # Supabase Auth
    supabase_url: str = ""
    supabase_jwt_secret: str = ""
    supabase_service_role_key: str = ""

    # Redis (Upstash)
    redis_url: str = ""

    # Google OAuth
    google_oauth_client_id: str = ""

    # FCM
    fcm_project_id: str = ""
    fcm_credentials_json: str = ""

    # Sentry
    sentry_dsn: str = ""

    # Discovery tuning
    discover_weight_distance: float = 0.6
    discover_weight_tag: float = 0.4
    location_fuzz_meters: float = 150.0
    radius_min_m: float = 500.0
    radius_max_m: float = 50_000.0
    radius_default_m: float = 5_000.0
    message_ttl_hours: int = 24

    @property
    def is_production(self) -> bool:
        return self.zexo_env.lower() in {"production", "prod"}


@lru_cache
def get_settings() -> Settings:
    """Cached settings singleton."""
    return Settings()
