import React from "react";
import { useTranslations } from "next-intl";
import { SvgSearch, SvgGlobe } from "@opal/icons";
import { SearchToolPacket } from "@/app/app/services/streamingModels";
import {
  MessageRenderer,
  RenderType,
} from "@/app/app/message/messageComponents/interfaces";
import { BlinkingBar } from "@/app/app/message/BlinkingBar";
import { ValidSources } from "@/lib/types";
import { SearchChipList, SourceInfo } from "./SearchChipList";
import {
  constructCurrentSearchState,
  INITIAL_QUERIES_TO_SHOW,
  QUERIES_PER_EXPANSION,
} from "./searchStateUtils";
import Text from "@/refresh-components/texts/Text";
import { GoogleSearchSuggestions } from "@/lib/webSearch/GoogleSearchSuggestions";

const queryToSourceInfo = (query: string, index: number): SourceInfo => ({
  id: `query-${index}`,
  title: query,
  sourceType: ValidSources.Web,
  icon: SvgSearch,
});

/**
 * WebSearchToolRenderer - Renders web search tool execution steps
 *
 * Only shows queries - results are handled by the fetch tool.
 *
 * RenderType modes:
 * - FULL: Shows queries timeline step. Used when step is expanded in timeline.
 * - HIGHLIGHT: Shows queries with header embedded directly in content.
 *              No StepContainer wrapper. Used for parallel streaming preview.
 * - INLINE: Shows queries for collapsed streaming view.
 */
export const WebSearchToolRenderer: MessageRenderer<SearchToolPacket, {}> = ({
  packets,
  onComplete,
  animate,
  stopPacketSeen,
  renderType,
  children,
}) => {
  const t = useTranslations("chat.messages.timeline");
  const searchState = constructCurrentSearchState(packets);
  const { queries } = searchState;
  const suggestions = searchState.results
    .map((doc) => doc.metadata?.google_search_suggestions_html)
    .filter((html): html is string => Boolean(html));
  const suggestionsDisplay = suggestions.map((html, index) => (
    <GoogleSearchSuggestions key={index} html={html} />
  ));

  const isHighlight = renderType === RenderType.HIGHLIGHT;
  const isInline = renderType === RenderType.INLINE;

  const queriesHeader = t("webSearch.searching.status");

  if (queries.length === 0) {
    return children([
      {
        icon: SvgGlobe,
        status: queriesHeader,
        content: <div />,
        supportsCollapsible: false,
        timelineLayout: "timeline",
      },
    ]);
  }

  // HIGHLIGHT mode: header embedded in content, no StepContainer
  if (isHighlight) {
    return children([
      {
        icon: null,
        status: null,
        supportsCollapsible: false,
        timelineLayout: "content",
        content: (
          <div className="flex flex-col">
            <Text as="p" text04 mainUiMuted className="mb-1">
              {queriesHeader}
            </Text>
            <SearchChipList
              items={queries}
              initialCount={INITIAL_QUERIES_TO_SHOW}
              expansionCount={QUERIES_PER_EXPANSION}
              getKey={(_, index) => index}
              toSourceInfo={queryToSourceInfo}
              emptyState={!stopPacketSeen ? <BlinkingBar /> : undefined}
              showDetailsCard={false}
              isQuery={true}
            />
            {suggestionsDisplay}
          </div>
        ),
      },
    ]);
  }

  // INLINE mode: show queries for collapsed streaming view
  if (isInline) {
    return children([
      {
        icon: null,
        status: queriesHeader,
        supportsCollapsible: false,
        timelineLayout: "content",
        content: (
          <div className="flex flex-col">
            <SearchChipList
              items={queries}
              initialCount={INITIAL_QUERIES_TO_SHOW}
              expansionCount={QUERIES_PER_EXPANSION}
              getKey={(_, index) => index}
              toSourceInfo={queryToSourceInfo}
              emptyState={!stopPacketSeen ? <BlinkingBar /> : undefined}
              showDetailsCard={false}
              isQuery={true}
            />
            {suggestionsDisplay}
          </div>
        ),
      },
    ]);
  }

  // FULL mode: return queries timeline step
  return children([
    {
      icon: SvgGlobe,
      status: queriesHeader,
      content: (
        <div className="flex flex-col">
          <SearchChipList
            items={queries}
            initialCount={INITIAL_QUERIES_TO_SHOW}
            expansionCount={QUERIES_PER_EXPANSION}
            getKey={(_, index) => index}
            toSourceInfo={queryToSourceInfo}
            emptyState={!stopPacketSeen ? <BlinkingBar /> : undefined}
            showDetailsCard={false}
            isQuery={true}
          />
          {suggestionsDisplay}
        </div>
      ),
      supportsCollapsible: false,
      timelineLayout: "timeline",
    },
  ]);
};
