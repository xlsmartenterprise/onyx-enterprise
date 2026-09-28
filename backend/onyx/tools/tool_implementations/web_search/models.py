from abc import abstractmethod
from collections.abc import Sequence
from datetime import datetime
from enum import Enum
from urllib.parse import urlparse

from pydantic import BaseModel, field_validator

from onyx.utils.url import normalize_url

# Fairly loose number but assuming LLMs can easily handle this amount of context
# Approximately 2 pages of google search results
# This is the cap for both when the tool is running a single search and when running multiple queries in parallel
DEFAULT_MAX_RESULTS = 20

WEB_SEARCH_PREFIX = "WEB_SEARCH_DOC_"


class ProviderType(Enum):
    """Enum for internet search provider types"""

    GOOGLE = "google"
    EXA = "exa"


class WebSearchResult(BaseModel):
    title: str
    link: str
    snippet: str
    # Google Search Suggestions markup accompanies a grounded response.
    search_suggestions_html: str | None = None
    author: str | None = None
    published_date: datetime | None = None

    @field_validator("link")
    @classmethod
    def normalize_link(cls, v: str) -> str:
        # Vertex grounding links are signed Google redirects; stripping their query
        # parameters can make source citations point to an invalid redirect.
        parsed = urlparse(v)
        if (
            parsed.scheme == "https"
            and parsed.hostname == "vertexaisearch.cloud.google.com"
            and parsed.path.startswith("/grounding-api-redirect/")
        ):
            return v
        return normalize_url(v)


class WebSearchProvider:
    @property
    def supports_site_filter(self) -> bool:
        """Whether this provider supports the site: operator in queries.
        Override in subclasses that don't support it.
        """
        return True

    @abstractmethod
    def search(self, query: str) -> Sequence[WebSearchResult]:
        pass

    @abstractmethod
    def test_connection(self) -> dict[str, str]:
        pass


class WebContentProviderConfig(BaseModel):
    timeout_seconds: int | None = None
    base_url: str | None = None
