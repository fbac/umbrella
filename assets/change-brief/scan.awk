# scan.awk — minimal block scanner for change-brief payloads.
#
# SCOPE DISCIPLINE: this file does NOT try to reimplement CommonMark. Four
# review rounds established that it cannot. Every attempt to make a source-side
# heading count agree with marked's parse produced a new divergence — nested
# fences, indented code, HTML blocks, backtick info strings — and each
# divergence is either a false truncation alarm or silent content loss.
#
# Truncation is now detected by the PAGE, structurally: render.sh always
# appends a sentinel Plan heading, and the page asserts it survived the parse.
# That check uses the same parser the reader sees, so it cannot drift, and it
# catches every cause of content loss rather than the ones awk can model.
#
# What remains here is only what the page cannot do, because it happens before
# parsing: neutralising a dangling HTML comment, and flattening stray H1s —
# both ATX ("# Title") and setext ("Title\n=====").
#
# Two things the setext path must also get right, both verified against the
# vendored marked v12.0.2 (the sole authority for what counts as a heading
# here, not this file's reading of the CommonMark spec):
#
#   - CRLF line endings. A setext underline or blank line ending in "\r" used
#     to fall outside the end-anchored [ \t]* character classes below, so a
#     "=======\r" was never recognised as an underline and the H1 it should
#     have demoted reached the DOM intact. Fixed by admitting \r into those
#     classes; ATX flattening and the fence-close marker check needed no such
#     fix because they anchor only at line start.
#
#   - List-item lazy continuation. CommonMark lets a list item's first line
#     be promoted to a heading by a bare "===" right after it — "- text\n==="
#     renders <li><h1>text</h1>...</li> — because the marker prefix does not
#     stop the setext underline from lazily continuing the item's paragraph.
#     Blockquotes were checked and do NOT get this treatment ("> text\n==="
#     stays a paragraph), so "#" and ">" remain excluded from holding
#     entirely. A list-item line IS held, but split into its marker prefix
#     and text so demotion can keep the prefix and rewrite only the text —
#     "- text" + "===" becomes "- #### text", never "#### - text", which
#     would destroy the list structure.
#
# Modes:
#   -v mode=escape  emit the payload: demote stray H1s, and if -v unbalanced=1
#                   escape line-start "<!--" outside code
#   -v mode=diag    emit one warning line per structural defect found
#   -v mode=dangle  print 1 if a "<!--" is left unclosed outside code, else 0

function emit(l) { if (mode == "escape") print l }

# Fence marker, if this line opens or closes a fenced block. Approximate by
# design: a misread here only affects escaping and warnings, both of which the
# page's structural check backstops.
function marker_of(line,   m) {
  if (match(line, /^ {0,3}(`{3,}|~{3,})/)) {
    m = substr(line, RSTART, RLENGTH)
    sub(/^ +/, "", m)
    return m
  }
  return ""
}

# Flush the one-line lookback buffer used for setext detection. held_set (not
# "held != ''") is the sentinel: a list-item line whose text-after-marker is
# itself empty (e.g. a bare "- ") legitimately holds an empty string, and
# testing held != "" would treat that as "nothing held" and drop the line.
function flush(   p) {
  if (held_set) { p = heldprefix held; held_set = 0; heldprefix = ""; held = ""; emit(p) }
}

BEGIN { fchar = ""; flen = 0; prevblank = 1; incode = 0; incomment = 0; held = ""; heldprefix = ""; held_set = 0 }

{
  line = $0

  # ---- setext H1: a run of "=" under a non-blank line ----------------------
  # Demoted like ATX H1s. The ATX regex cannot see these, so a setext H1
  # reaches the DOM as a real <h1>, opening an index group the h2/h3 builder
  # never renders — leaving that whole section unreachable. The trailing
  # [ \t\r]* (not [ \t]*) admits a CRLF underline: without \r in the class, an
  # "=======\r" line was never recognised as an underline and the H1 above it
  # reached the DOM unflattened. heldprefix carries a list marker through the
  # demotion (see below); it is "" for a plain held text line, so this is a
  # no-op change for the non-list case.
  if (fchar == "" && !incode && held_set && line ~ /^ {0,3}=+[ \t\r]*$/) {
    emit(heldprefix "#### " held)
    held = ""; heldprefix = ""; held_set = 0
    next
  }

  m = marker_of(line)

  if (m != "") {
    flush()
    ch = substr(m, 1, 1); len = length(m)
    if (fchar == "") { fchar = ch; flen = len; prevblank = 0; incode = 0; emit(line); next }
    if (ch == fchar && len >= flen && line ~ /^ {0,3}(`+|~+)[ \t\r]*$/) {
      fchar = ""; flen = 0; prevblank = 0; emit(line); next
    }
    prevblank = 0; emit(line); next
  }

  if (fchar != "") { flush(); emit(line); next }

  # \r admitted here too: a CRLF blank line's record is "\r", not "", and
  # without \r in the class it read as ordinary text — eligible to be held as
  # setext content — rather than as the blank line it actually is.
  if (line ~ /^[ \t\r]*$/) { flush(); prevblank = 1; incode = 0; emit(line); next }

  if ((prevblank || incode) && line ~ /^(    |\t)/) {
    flush(); incode = 1; prevblank = 0; emit(line); next
  }
  incode = 0; prevblank = 0

  # ---- dangling block-comment detection ------------------------------------
  # Only a comment that OPENS AT LINE START can form a CommonMark HTML block
  # and swallow the document. A "<!--" mid-paragraph is inline HTML and is
  # harmless, so tracking those produces false alarms on any document that
  # merely discusses comments in prose or inline code — this spec does.
  #
  # Order matters, not totals: a stray "-->" earlier in the text (prose about
  # mermaid arrows, say) would balance a count and disable escaping while a
  # real dangling opener still swallowed the tail.
  if (!incomment && line ~ /^ {0,3}<!--/) incomment = 1
  if (incomment) {
    t = line
    while (incomment && match(t, /-->/)) { incomment = 0; t = substr(t, RSTART + 3) }
  }

  flush()

  # ---- H1 flattening --------------------------------------------------------
  # To h4, not h2. A demoted H2 opens an index group and steals the following
  # H3s exactly as the H1 did — the defect renamed rather than removed. h4 is
  # below the index's h2/h3 range, so it can neither open nor capture a group.
  if (line ~ /^ {0,3}# /) sub(/#/, "####", line)

  if (unbalanced && line ~ /^ {0,3}<!--/) sub(/<!--/, "\\&lt;!--", line)

  # Hold non-blank lines one line back so the next line can turn them into a
  # setext heading. An ATX line ("#") or blockquote line (">") is never
  # setext content and is excluded from holding entirely — confirmed against
  # the vendored parser: "> text\n===" stays a quoted paragraph, not a
  # heading. A list-item line ("- text", "1. text") IS eligible (CommonMark
  # lazy continuation), but is split into heldprefix (the marker, verbatim,
  # including its 0-3 leading spaces) and held (the text after it), so a
  # later setext underline demotes only the text — "- text" becomes
  # "- #### text", keeping the list structure — while a flush() with no
  # heading reassembles heldprefix held back into the original line.
  if (mode == "escape") {
    if (line ~ /^ {0,3}(#|>)/) { emit(line); next }
    if (match(line, /^ {0,3}([-*+] |[0-9]+[.)] )/)) {
      heldprefix = substr(line, RSTART, RLENGTH)
      held = substr(line, RSTART + RLENGTH)
      held_set = 1
      next
    }
    heldprefix = ""; held = line; held_set = 1
    next
  }
  emit(line)
}

END {
  flush()
  if (mode == "dangle") print (incomment ? 1 : 0)
  if (mode == "diag") {
    if (fchar != "")
      print "Unterminated code fence: a ``` or ~~~ block was opened and never closed, so everything after it is being shown as code."
    if (incomment)
      print "Unterminated HTML comment: a <!-- was opened and never closed. It has been neutralised so the rest of the document still renders."
  }
}
