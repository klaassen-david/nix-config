// Startpage result pages: the tab (and window) title is exactly the search string.
// The query is in the URL for searches from the url bar (GET), and only in the
// page for searches from Startpage's own box (POST): the hidden name="query"
// field carries the submitted string. The visible box (#q) is not read, so
// typing a new search does not retitle the page before it is submitted.
"use strict";

const query = () =>
  new URLSearchParams(location.search).get("query") ||
  document.querySelector('input[type="hidden"][name="query"]:not([value=""])')?.value ||
  null;

const apply = () => {
  const q = query();
  if (q && document.title !== q) {
    document.title = q;
  }
};

apply();
// Startpage's scripts set the title again on later renders (next page, tabs)
new MutationObserver(apply).observe(document.head, {
  childList: true,
  subtree: true,
  characterData: true,
});
