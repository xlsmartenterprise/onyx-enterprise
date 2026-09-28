"""Google Search grounding via Vertex AI and workload identity (no API key)."""

from collections.abc import Sequence
from html.parser import HTMLParser
from urllib.parse import urlparse

from google import genai
from google.genai import types

from onyx.configs.app_configs import (
    VERTEXAI_DEFAULT_LOCATION,
    VERTEXAI_DEFAULT_PROJECT,
)
from onyx.tools.tool_implementations.web_search.models import (
    DEFAULT_MAX_RESULTS,
    WebSearchProvider,
    WebSearchResult,
)


class _GoogleSuggestionLinkValidator(HTMLParser):
    """Reject clickable destinations outside Google's grounding redirects."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links = 0

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if tag in {"base", "iframe", "script", "object", "embed", "form", "meta"}:
            raise ValueError("Unexpected element in Google Search Suggestions.")
        if tag != "a":
            return
        hrefs = [value for key, value in attrs if key == "href"]
        target = next((value for key, value in attrs if key == "target"), None)
        if (
            len(hrefs) != 1
            or target not in (None, "_blank")
            or any(key in {"ping", "download"} for key, _ in attrs)
        ):
            raise ValueError("Unexpected anchor in Google Search Suggestions.")
        url = urlparse(hrefs[0] or "")
        if (
            url.scheme != "https"
            or url.hostname != "vertexaisearch.cloud.google.com"
            or not url.path.startswith("/grounding-api-redirect/")
            or url.username
            or url.password
            or url.port is not None
        ):
            raise ValueError("Unexpected link in Google Search Suggestions.")
        self.links += 1


def _validate_search_suggestions(html: str | None) -> str | None:
    if not html:
        return None
    validator = _GoogleSuggestionLinkValidator()
    validator.feed(html)
    if not validator.links:
        raise ValueError("Google Search Suggestions did not include a search link.")
    return html


class VertexAISearchClient(WebSearchProvider):
    """Use Gemini Flash's grounding metadata, never model-generated URLs or titles."""

    MODEL = "gemini-3.8-flash"

    def __init__(self, num_results: int = DEFAULT_MAX_RESULTS) -> None:
        if not VERTEXAI_DEFAULT_PROJECT:
            raise ValueError("VERTEXAI_DEFAULT_PROJECT is required for Vertex AI search.")
        if VERTEXAI_DEFAULT_LOCATION != "global":
            raise ValueError(
                "Vertex AI Google Search grounding requires the global location."
            )
        self._project = VERTEXAI_DEFAULT_PROJECT
        self._num_results = num_results

    @property
    def supports_site_filter(self) -> bool:
        # Google grounding chooses search queries internally; site: is not guaranteed.
        return False

    def search(self, query: str) -> Sequence[WebSearchResult]:
        with genai.Client(
            vertexai=True, project=self._project, location="global"
        ) as client:
            response = client.models.generate_content(
                model=self.MODEL,
                contents=(
                    "Use Google Search to find current information for this search query. "
                    "Give a concise factual summary of the results, grounded in the "
                    f"sources returned by Google Search. Query: {query}"
                ),
                config=types.GenerateContentConfig(
                    tools=[types.Tool(google_search=types.GoogleSearch())],
                ),
            )

        candidates = response.candidates or []
        grounding = candidates[0].grounding_metadata if candidates else None
        if grounding is None:
            # Do not turn the model's ungrounded answer into web search results.
            return []

        chunks = grounding.grounding_chunks or []
        supports = grounding.grounding_supports or []
        snippets: dict[int, list[str]] = {}
        for support in supports:
            text = (support.segment.text if support.segment else None) or ""
            text = text.strip()
            if not text:
                continue
            for index in support.grounding_chunk_indices or []:
                if 0 <= index < len(chunks):
                    snippets.setdefault(index, []).append(text)

        suggestions = _validate_search_suggestions(
            grounding.search_entry_point.rendered_content
            if grounding.search_entry_point
            else None
        )
        results: list[WebSearchResult] = []
        for index, chunk in enumerate(chunks):
            web = chunk.web
            if web is None or not web.uri:
                continue
            url = urlparse(web.uri)
            if (
                url.scheme != "https"
                or not url.hostname
                or url.username
                or url.password
            ):
                continue
            title = (web.title or "").strip()
            # A segment is Gemini's grounded summary, NOT an excerpt of the linked page.
            snippet = " ".join(dict.fromkeys(snippets.get(index, [])))
            if not title and not snippet:
                continue
            results.append(
                WebSearchResult(
                    title=title,
                    link=web.uri,
                    snippet=f"Google-grounded summary: {snippet}" if snippet else "",
                    # Show the exact Google Search Suggestions alongside these results.
                    search_suggestions_html=suggestions if not results else None,
                )
            )
            if len(results) >= self._num_results:
                break
        return results

    def test_connection(self) -> dict[str, str]:
        results = self.search("latest Google Search results today")
        if not results:
            raise ValueError(
                "Vertex AI returned no grounded web sources; "
                "check Google Search grounding access."
            )
        return {"status": "ok"}
