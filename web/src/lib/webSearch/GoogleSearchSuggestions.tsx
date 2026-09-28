"use client";

// This is Google's search_entry_point.rendered_content, which Google requires
// displayed alongside grounded results. Never parse it as a source snippet or
// render it in the application's origin: it is third-party HTML/CSS.
export function GoogleSearchSuggestions({ html }: { html: string }) {
  const srcDoc = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; form-action 'none'"><base target="_blank">${html}`;

  return (
    <div className="w-full" aria-label="Google Search Suggestions">
      <iframe
        title="Google Search Suggestions"
        srcDoc={srcDoc}
        sandbox="allow-popups allow-popups-to-escape-sandbox"
        referrerPolicy="no-referrer"
        className="w-full h-28 border-0"
      />
    </div>
  );
}
