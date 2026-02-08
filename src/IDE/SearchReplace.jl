# IDE/SearchReplace.jl - Sessions.jl IDE Search & Replace
#
# Cross-cell search and replace bar. Opens with Ctrl/Cmd+F.
# Searches across all cell code and highlights matches.
#
# Architecture:
# - SSR renders hidden search bar at top of notebook area
# - JS handles search logic, match highlighting, navigation
# - Replace operations modify CodeMirror editor state directly
# - CodeMirror's built-in search still works within-cell (Ctrl+F inside editor)
# - This component handles the cross-cell overlay search
#
# SESSIONS-3605

import Suite

# =============================================================================
# Search Bar Component
# =============================================================================

"""
    IDESearchBar()

Hidden search/replace bar. Rendered at top of notebook area.
Toggled visible by Ctrl/Cmd+F (from search_replace_script).
"""
function IDESearchBar()
    Div(:id => "search-bar",
        :class => "hidden sticky top-0 z-30 border-b border-warm-200 dark:border-[#252422] bg-warm-50/95 dark:bg-warm-950/95 backdrop-blur-sm px-3 py-2",

        # Search row
        Div(:class => "flex items-center gap-2",
            # Search icon
            Svg(:class => "w-4 h-4 text-warm-400 dark:text-warm-500 flex-shrink-0",
                :fill => "none", :viewBox => "0 0 24 24",
                :stroke => "currentColor", Symbol("stroke-width") => "2",
                Path(:d => "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z")
            ),

            # Search input
            Input(:id => "search-input",
                :type => "text",
                :class => "flex-1 bg-warm-100 dark:bg-warm-900 border border-warm-200 dark:border-warm-700 rounded px-2 py-1 text-[11px] font-mono text-warm-700 dark:text-warm-300 placeholder:text-warm-400 dark:placeholder:text-warm-600 focus:outline-none focus:ring-1 focus:ring-accent-500",
                :placeholder => "Search across cells...",
                :autocomplete => "off",
                :spellcheck => "false"
            ),

            # Match count
            Span(:id => "search-match-count",
                :class => "text-[10px] font-mono text-warm-400 dark:text-warm-500 whitespace-nowrap",
                ""
            ),

            # Regex toggle
            Button(:id => "search-regex-toggle",
                :class => "h-6 w-6 flex items-center justify-center rounded text-[10px] font-mono text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Toggle regex",
                :onclick => "toggleSearchRegex()",
                ".*"
            ),

            # Case toggle
            Button(:id => "search-case-toggle",
                :class => "h-6 w-6 flex items-center justify-center rounded text-[10px] font-mono text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Toggle case sensitivity",
                :onclick => "toggleSearchCase()",
                "Aa"
            ),

            # Navigation: prev/next
            Button(:class => "h-6 w-6 flex items-center justify-center rounded text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Previous match (Shift+Enter)",
                :onclick => "searchPrev()",
                Svg(:class => "w-3.5 h-3.5", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => "M5 15l7-7 7 7")
                )
            ),

            Button(:class => "h-6 w-6 flex items-center justify-center rounded text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Next match (Enter)",
                :onclick => "searchNext()",
                Svg(:class => "w-3.5 h-3.5", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => "M19 9l-7 7-7-7")
                )
            ),

            # Close button
            Button(:class => "h-6 w-6 flex items-center justify-center rounded text-warm-400 hover:text-rose-500 dark:text-warm-500 dark:hover:text-rose-400 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Close (Escape)",
                :onclick => "closeSearch()",
                Svg(:class => "w-3.5 h-3.5", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => "M6 18L18 6M6 6l12 12")
                )
            )
        ),

        # Replace row (toggleable)
        Div(:id => "replace-row",
            :class => "hidden flex items-center gap-2 mt-1.5",

            # Spacer to align with search input
            Div(:class => "w-4 flex-shrink-0"),

            # Replace input
            Input(:id => "replace-input",
                :type => "text",
                :class => "flex-1 bg-warm-100 dark:bg-warm-900 border border-warm-200 dark:border-warm-700 rounded px-2 py-1 text-[11px] font-mono text-warm-700 dark:text-warm-300 placeholder:text-warm-400 dark:placeholder:text-warm-600 focus:outline-none focus:ring-1 focus:ring-accent-500",
                :placeholder => "Replace with...",
                :autocomplete => "off",
                :spellcheck => "false"
            ),

            # Replace current
            Button(:class => "h-6 px-2 flex items-center justify-center rounded text-[10px] font-mono text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Replace current match",
                :onclick => "replaceCurrent()",
                "Replace"
            ),

            # Replace all
            Button(:class => "h-6 px-2 flex items-center justify-center rounded text-[10px] font-mono text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
                :title => "Replace all matches",
                :onclick => "replaceAll()",
                "All"
            ),

            # Toggle replace row
            Button(:id => "replace-toggle",
                :class => "hidden",
            )
        )
    )
end

# =============================================================================
# Search & Replace Script
# =============================================================================

"""
    search_replace_script()

Client-side JS for cross-cell search and replace.
"""
function search_replace_script()
    """
    <script>
    (function() {
        if (window._searchReplaceInitialized) return;
        window._searchReplaceInitialized = true;

        var _searchState = {
            query: '',
            regex: false,
            caseSensitive: false,
            matches: [],      // {cellId, index, length, text}
            currentMatch: -1,
            replaceVisible: false
        };

        // =====================================================================
        // Toggle Helpers
        // =====================================================================

        window.toggleSearchRegex = function() {
            _searchState.regex = !_searchState.regex;
            var btn = document.getElementById('search-regex-toggle');
            if (btn) {
                btn.classList.toggle('bg-accent-500/20', _searchState.regex);
                btn.classList.toggle('text-accent-600', _searchState.regex);
            }
            doSearch();
        };

        window.toggleSearchCase = function() {
            _searchState.caseSensitive = !_searchState.caseSensitive;
            var btn = document.getElementById('search-case-toggle');
            if (btn) {
                btn.classList.toggle('bg-accent-500/20', _searchState.caseSensitive);
                btn.classList.toggle('text-accent-600', _searchState.caseSensitive);
            }
            doSearch();
        };

        // =====================================================================
        // Open / Close
        // =====================================================================

        window.openSearch = function() {
            var bar = document.getElementById('search-bar');
            if (!bar) return;
            bar.classList.remove('hidden');
            var input = document.getElementById('search-input');
            if (input) {
                input.focus();
                input.select();
            }
        };

        window.closeSearch = function() {
            var bar = document.getElementById('search-bar');
            if (bar) bar.classList.add('hidden');
            clearHighlights();
            _searchState.matches = [];
            _searchState.currentMatch = -1;
            updateMatchCount();
        };

        window.toggleReplace = function() {
            _searchState.replaceVisible = !_searchState.replaceVisible;
            var row = document.getElementById('replace-row');
            if (row) row.classList.toggle('hidden', !_searchState.replaceVisible);
        };

        // =====================================================================
        // Search Logic
        // =====================================================================

        function doSearch() {
            var input = document.getElementById('search-input');
            if (!input) return;
            var query = input.value;
            _searchState.query = query;

            clearHighlights();
            _searchState.matches = [];
            _searchState.currentMatch = -1;

            if (!query) {
                updateMatchCount();
                return;
            }

            var cells = document.querySelectorAll('[data-cell-id]');
            cells.forEach(function(cell) {
                var cellId = cell.getAttribute('data-cell-id');
                var code = '';

                // Get code from CodeMirror or fallback
                var container = cell.querySelector('[data-codemirror]');
                if (container && container._cmView) {
                    code = container._cmView.state.doc.toString();
                } else {
                    var pre = cell.querySelector('.cell-code');
                    if (pre) code = pre.textContent;
                }

                if (!code) return;

                // Find matches
                var flags = _searchState.caseSensitive ? 'g' : 'gi';
                var pattern;
                try {
                    if (_searchState.regex) {
                        pattern = new RegExp(query, flags);
                    } else {
                        pattern = new RegExp(query.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\\$&'), flags);
                    }
                } catch (e) {
                    return; // Invalid regex
                }

                var match;
                while ((match = pattern.exec(code)) !== null) {
                    _searchState.matches.push({
                        cellId: cellId,
                        index: match.index,
                        length: match[0].length,
                        text: match[0]
                    });
                    if (match[0].length === 0) break; // Prevent infinite loop
                }
            });

            updateMatchCount();

            if (_searchState.matches.length > 0) {
                _searchState.currentMatch = 0;
                highlightCurrentMatch();
            }
        }

        function updateMatchCount() {
            var el = document.getElementById('search-match-count');
            if (!el) return;
            if (_searchState.matches.length === 0 && _searchState.query) {
                el.textContent = 'No results';
            } else if (_searchState.matches.length > 0) {
                el.textContent = (_searchState.currentMatch + 1) + '/' + _searchState.matches.length;
            } else {
                el.textContent = '';
            }
        }

        // =====================================================================
        // Navigation
        // =====================================================================

        window.searchNext = function() {
            if (_searchState.matches.length === 0) return;
            _searchState.currentMatch = (_searchState.currentMatch + 1) % _searchState.matches.length;
            highlightCurrentMatch();
            updateMatchCount();
        };

        window.searchPrev = function() {
            if (_searchState.matches.length === 0) return;
            _searchState.currentMatch = (_searchState.currentMatch - 1 + _searchState.matches.length) % _searchState.matches.length;
            highlightCurrentMatch();
            updateMatchCount();
        };

        // =====================================================================
        // Highlighting
        // =====================================================================

        function highlightCurrentMatch() {
            clearHighlights();
            if (_searchState.currentMatch < 0 || _searchState.currentMatch >= _searchState.matches.length) return;

            var match = _searchState.matches[_searchState.currentMatch];
            var cell = document.querySelector('[data-cell-id="' + match.cellId + '"]');
            if (!cell) return;

            // Scroll cell into view
            cell.scrollIntoView({ behavior: 'smooth', block: 'center' });

            // Add highlight class to the cell
            cell.classList.add('search-match-active');
        }

        function clearHighlights() {
            document.querySelectorAll('.search-match-active').forEach(function(el) {
                el.classList.remove('search-match-active');
            });
        }

        // =====================================================================
        // Replace
        // =====================================================================

        window.replaceCurrent = function() {
            if (_searchState.currentMatch < 0) return;
            var match = _searchState.matches[_searchState.currentMatch];
            replaceInCell(match.cellId, match.index, match.length);
            doSearch();
        };

        window.replaceAll = function() {
            // Replace from last to first to maintain indices
            var matches = _searchState.matches.slice().reverse();
            var cellGroups = {};
            matches.forEach(function(m) {
                if (!cellGroups[m.cellId]) cellGroups[m.cellId] = [];
                cellGroups[m.cellId].push(m);
            });

            Object.keys(cellGroups).forEach(function(cellId) {
                var cellMatches = cellGroups[cellId];
                // Already reversed, so indices go from high to low
                cellMatches.forEach(function(m) {
                    replaceInCell(m.cellId, m.index, m.length);
                });
            });

            doSearch();
        };

        function replaceInCell(cellId, index, length) {
            var replaceInput = document.getElementById('replace-input');
            var replacement = replaceInput ? replaceInput.value : '';

            var cell = document.querySelector('[data-cell-id="' + cellId + '"]');
            if (!cell) return;

            var container = cell.querySelector('[data-codemirror]');
            if (container && container._cmView) {
                var view = container._cmView;
                view.dispatch({
                    changes: { from: index, to: index + length, insert: replacement }
                });
            }
        }

        // =====================================================================
        // Event Handlers
        // =====================================================================

        // Search on input
        var searchInput = null;
        function attachEvents() {
            searchInput = document.getElementById('search-input');
            if (searchInput) {
                searchInput.addEventListener('input', doSearch);
                searchInput.addEventListener('keydown', function(e) {
                    if (e.key === 'Enter') {
                        e.preventDefault();
                        if (e.shiftKey) {
                            searchPrev();
                        } else {
                            searchNext();
                        }
                    }
                    if (e.key === 'Escape') {
                        e.preventDefault();
                        closeSearch();
                    }
                });
            }

            var replaceInput = document.getElementById('replace-input');
            if (replaceInput) {
                replaceInput.addEventListener('keydown', function(e) {
                    if (e.key === 'Enter') {
                        e.preventDefault();
                        replaceCurrent();
                    }
                    if (e.key === 'Escape') {
                        e.preventDefault();
                        closeSearch();
                    }
                });
            }
        }

        // Ctrl/Cmd+F to open search (at document level, outside CodeMirror)
        document.addEventListener('keydown', function(e) {
            var isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
            var mod = isMac ? e.metaKey : e.ctrlKey;

            if (mod && !e.shiftKey && e.key === 'f') {
                // Only intercept if not inside a CodeMirror editor
                var active = document.activeElement;
                if (active && active.closest('.cm-editor')) return;

                e.preventDefault();
                openSearch();
            }

            // Ctrl/Cmd+H for search + replace
            if (mod && !e.shiftKey && e.key === 'h') {
                var active2 = document.activeElement;
                if (active2 && active2.closest('.cm-editor')) return;

                e.preventDefault();
                openSearch();
                _searchState.replaceVisible = true;
                var row = document.getElementById('replace-row');
                if (row) row.classList.remove('hidden');
            }
        });

        // Attach after DOM ready
        setTimeout(attachEvents, 200);
    })();
    </script>
    """
end

# =============================================================================
# Search Highlight Styles
# =============================================================================

"""
    search_styles()

CSS for search match highlighting.
"""
function search_styles()
    """
    <style>
    .search-match-active {
        outline: 2px solid rgb(var(--accent-500));
        outline-offset: 2px;
        border-radius: 0.5rem;
    }
    </style>
    """
end
