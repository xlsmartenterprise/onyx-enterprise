from types import SimpleNamespace
from unittest.mock import patch

import pytest

from onyx.tools.tool_implementations.web_search.clients.vertex_ai_client import (
    VertexAISearchClient,
)


REDIRECT = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/"


def _grounded_response(suggestion_url: str) -> SimpleNamespace:
    return SimpleNamespace(
        candidates=[
            SimpleNamespace(
                grounding_metadata=SimpleNamespace(
                    grounding_chunks=[
                        SimpleNamespace(
                            web=SimpleNamespace(
                                title="unrelated.example", uri=REDIRECT + "first"
                            )
                        ),
                        SimpleNamespace(
                            web=SimpleNamespace(
                                title="docs.python.org",
                                uri=REDIRECT + "second?token=keep-me",
                            )
                        ),
                    ],
                    grounding_supports=[
                        SimpleNamespace(
                            segment=SimpleNamespace(text="Python 3.13 release notes"),
                            grounding_chunk_indices=[1],
                        )
                    ],
                    search_entry_point=SimpleNamespace(
                        rendered_content=(
                            '<style>.chip { color: blue; }</style>'
                            f'<a class="chip" href="{suggestion_url}">Search Google</a>'
                        )
                    ),
                )
            )
        ]
    )


def test_vertex_grounded_search_attributes_only_matching_chunks_and_preserves_redirect() -> None:
    with (
        patch(
            "onyx.tools.tool_implementations.web_search.clients.vertex_ai_client.VERTEXAI_DEFAULT_PROJECT",
            "test-project",
        ),
        patch(
            "onyx.tools.tool_implementations.web_search.clients.vertex_ai_client.VERTEXAI_DEFAULT_LOCATION",
            "global",
        ),
        patch(
            "onyx.tools.tool_implementations.web_search.clients.vertex_ai_client.genai.Client"
        ) as client_factory,
    ):
        client_factory.return_value.__enter__.return_value.models.generate_content.return_value = (
            _grounded_response(REDIRECT + "suggestion")
        )
        results = VertexAISearchClient().search("Python 3.13 release notes")

    assert results[0].snippet == ""
    assert results[1].title == "docs.python.org"
    assert results[1].link == REDIRECT + "second?token=keep-me"
    assert results[1].snippet == "Google-grounded summary: Python 3.13 release notes"
    assert "Search Google" in (results[0].search_suggestions_html or "")
    assert results[1].search_suggestions_html is None


def test_vertex_grounded_search_rejects_foreign_suggestion_destination() -> None:
    with (
        patch(
            "onyx.tools.tool_implementations.web_search.clients.vertex_ai_client.VERTEXAI_DEFAULT_PROJECT",
            "test-project",
        ),
        patch(
            "onyx.tools.tool_implementations.web_search.clients.vertex_ai_client.VERTEXAI_DEFAULT_LOCATION",
            "global",
        ),
        patch(
            "onyx.tools.tool_implementations.web_search.clients.vertex_ai_client.genai.Client"
        ) as client_factory,
    ):
        client_factory.return_value.__enter__.return_value.models.generate_content.return_value = (
            _grounded_response("https://evil.example/redirect")
        )
        with pytest.raises(ValueError, match="Unexpected link"):
            VertexAISearchClient().search("Python 3.13 release notes")
