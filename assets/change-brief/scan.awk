# scan.awk — minimal block scanner for change-brief payloads.
#
# SCOPE DISCIPLINE: this file does NOT try to reimplement CommonMark. Four
# review rounds established that it cannot. Every attempt to make a source-side
# heading count agree with marked's parse produced a new divergence — nested
# fences, indented code, HTML blocks, backtick info strings — and each
# divergence is either a false truncation alarm or silent content loss.
#
# A fifth attempt tried to also flatten a setext heading formed by a list
# item's own first line ("- text" immediately followed by "===", which
# CommonMark promotes via lazy continuation). Four further rounds each closed
# one content-loss edge in that split/reassemble logic and opened another in
# the same few lines — CRLF, "> quoted" content, tab markers, bare markers —
# with no sign of convergence, so it was reverted. The residual gap: a list
# item's first line, immediately followed with no blank line by a bare setext
# underline, still reaches the DOM as an unflattened stray H1. Unlike the
# truncation this file defers to the page below, the page's structural
# sentinel does NOT backstop this — it only catches its own synthesized
# heading going missing, not a localized substitution mid-document. Accepted
# anyway: neither real document in this repo has ever needed it.
#
# A second, different failure predates all four rounds, inherited unchanged
# from the original design rather than caused by the revert: the exclusion
# above requires a literal space right after the marker, so a marker followed
# by only whitespace or nothing at all ("-\t\t", bare "-") falls through into
# the generic hold instead. This is not the under-flattening gap above — it
# is over-eager fabrication. When a bare "===" follows with no blank line,
# the underline's own text is discarded and a heading is invented where
# marked forms none (verified: marked treats the "===" as literal list
# content). Same reason the page's sentinel doesn't catch it either. Left
# alone for the same standing reason: patching it reopens the cycle the
# revert just closed.
#
# Truncation is detected by the PAGE, structurally: render.sh always appends
# a sentinel Plan heading, and the page asserts it survived the parse. That
# check uses the same parser the reader sees, so it cannot drift, and it
# catches every cause of content loss rather than the ones awk can model.
#
# What remains here is only what the page cannot do, because it happens before
# parsing: neutralising a dangling HTML comment, and flattening stray H1s —
# both ATX ("# Title") and setext ("Title\n====="), including a setext
# underline or blank line ending in CRLF, verified against the vendored
# marked v12.0.2.
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

# Flush the one-line lookback buffer used for setext detection.
function flush(   p) {
  if (held != "") { p = held; held = ""; emit(p) }
}

BEGIN { fchar = ""; flen = 0; prevblank = 1; incode = 0; incomment = 0; held = "" }

{
  line = $0

  # ---- setext H1: a run of "=" under a non-blank line ----------------------
  # Demoted like ATX H1s. The ATX regex cannot see these, so a setext H1
  # reaches the DOM as a real <h1>, opening an index group the h2/h3 builder
  # never renders — leaving that whole section unreachable. \r is admitted
  # alongside space/tab so a CRLF underline ("=======\r") is still recognised.
  if (fchar == "" && !incode && held != "" && line ~ /^ {0,3}=+[ \t\r]*$/) {
    emit("#### " held)
    held = ""
    next
  }

  m = marker_of(line)

  if (m != "") {
    flush()
    ch = substr(m, 1, 1); len = length(m)
    if (fchar == "") { fchar = ch; flen = len; prevblank = 0; incode = 0; emit(line); next }
    # Closing fence, transcribed from the vendored marked 12.0.2, whose fences
    # rule ends with:  (?: {0,3}\1[~`]* *(?=\n|$)|$)
    # -- the opener's own run (\1), then any further ` or ~, then SPACES only.
    # marker_of has already checked the run's character and length, so all that
    # is left is that nothing but fence characters and spaces follows.
    #
    # A tab is not a space, and both known divergences were this one class
    # being wrong in each direction. Measured, end to end, before the fix:
    # a closer ending in a tab closed the fence here and not in marked, so the
    # diagnostic (which is made of "is a fence still open?") never fired and
    # every later section rendered inside a <pre> with exit 0 and an empty
    # stderr. A closer written "```~~~" closes for marked and did not here, so
    # a dangling line-start "<!--" after it was taken for code, left unescaped,
    # and swallowed the tail under a warning that named the fence instead.
    #
    # \r still reaches this line even though render.sh rejects CRLF sources:
    # that guard is `grep -q $'\r$'`, which only sees a \r at END of line, and
    # the suite also runs this file directly on CRLF fixtures. It is admitted
    # as a line terminator, not as trailing whitespace -- marked's lexer
    # rewrites every \r, lone or paired, to a newline before any rule runs, so
    # marked's line ENDS at the first \r and whatever follows is a separate
    # line that cannot keep this one from closing. Hence (\r.*)?, which leaves
    # "```\t\rx" open (marked sees "```\t") while closing "```\r".
    if (ch == fchar && len >= flen && line ~ /^ {0,3}[`~]+ *(\r.*)?$/) {
      fchar = ""; flen = 0; prevblank = 0; emit(line); next
    }
    prevblank = 0; emit(line); next
  }

  if (fchar != "") { flush(); emit(line); next }

  # \r admitted here too: a CRLF blank line's record is "\r", not "", and
  # without it the line read as ordinary (setext-eligible) text instead.
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
  # setext heading. Only text lines can be setext content.
  if (mode == "escape" && line !~ /^ {0,3}(#|>|[-*+] |[0-9]+[.)] )/) { held = line; next }
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
