// CodeMirror 6 + Julia bundle for Sessions.jl Web UI
// Built with esbuild → window.C global (IIFE)
// Usage: new C.EditorView({ doc, extensions: [...], parent })

import { EditorView, keymap, lineNumbers, highlightActiveLineGutter,
         highlightSpecialChars, drawSelection, rectangularSelection,
         highlightActiveLine } from "@codemirror/view";
import { highlightSelectionMatches } from "@codemirror/search";
import { EditorState } from "@codemirror/state";
import { syntaxHighlighting, HighlightStyle, bracketMatching, indentOnInput } from "@codemirror/language";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { closeBrackets, closeBracketsKeymap, completionKeymap } from "@codemirror/autocomplete";
import { searchKeymap } from "@codemirror/search";
import { tags } from "@lezer/highlight";
import { julia } from "@plutojl/lang-julia";

window.C = {
  EditorView, EditorState,
  keymap, lineNumbers, highlightActiveLineGutter, highlightActiveLine,
  highlightSpecialChars, drawSelection, rectangularSelection,
  highlightSelectionMatches,
  syntaxHighlighting, HighlightStyle, bracketMatching, indentOnInput,
  defaultKeymap, history, historyKeymap, indentWithTab,
  closeBrackets, closeBracketsKeymap, completionKeymap,
  searchKeymap,
  tags, julia,
  // Alias for convenience
  t: tags,
};
