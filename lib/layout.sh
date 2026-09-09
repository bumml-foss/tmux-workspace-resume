# shellcheck shell=bash
# ai-revive — layout strings. tmux's #{window_layout} is "csum,WxH,X,Y<tree>" where a leaf is
# "WxH,X,Y,paneid" and containers are "WxH,X,Y{...}" (side by side) or "WxH,X,Y[...]" (stacked).
# select-layout accepts a string of a different size, but it does not scale it: every pane is
# shrunk (or grown) by the same absolute amount, so a 67:25 split saved at 93 rows becomes 43:1
# at 45 rows. layout_scale rescales every cell proportionally and recomputes the checksum.
# SPDX-License-Identifier: GPL-3.0-or-later

AI_REVIVE_LAYOUT_AWK='
function fail(msg) { print "layout_scale: " msg > "/dev/stderr"; exit 1 }
# --- parser over the global string S, position P (1-based) ---
function peek() { return substr(S, P, 1) }
function num(   n) {
	n = ""
	while (peek() ~ /[0-9]/) { n = n peek(); P++ }
	if (n == "") fail("number expected at " P)
	return n + 0
}
function expect(c) { if (peek() != c) fail("expected " c " at " P " got " peek()); P++ }
# parse a cell, return its index
function cell(   i, kids) {
	i = ++N
	W[i] = num(); expect("x"); H[i] = num(); expect(","); X[i] = num(); expect(","); Y[i] = num()
	if (peek() == ",") { P++; T[i] = "leaf"; ID[i] = num(); return i }
	if (peek() == "{") T[i] = "lr"; else if (peek() == "[") T[i] = "tb"; else fail("bad cell at " P)
	P++
	kids = ""
	while (1) {
		kids = kids (kids == "" ? "" : " ") cell()
		if (peek() == ",") { P++; continue }
		break
	}
	expect(T[i] == "lr" ? "}" : "]")
	KIDS[i] = kids
	return i
}
# --- scaler: give cell i the box w x h at x,y and distribute among its children ---
# Children get floor(share); the rounding remainder is handed out one row/column at a time to
# the currently largest child (taken from it when negative, never below 1). A box that cannot
# hold n children plus their n-1 separators is an error: the caller falls back to "tiled".
function biggest(k, n, min,   j, b) {
	b = 0
	for (j = 1; j <= n; j++) if (NS[k[j]] > min && (b == 0 || NS[k[j]] > NS[b])) b = k[j]
	return b
}
function scale(i, w, h, x, y,   n, k, j, total, avail, sum, sz, pos, b) {
	W[i] = w; H[i] = h; X[i] = x; Y[i] = y
	if (T[i] == "leaf") return
	n = split(KIDS[i], k, " ")
	total = 0
	for (j = 1; j <= n; j++) total += (T[i] == "lr" ? OW[k[j]] : OH[k[j]])
	avail = (T[i] == "lr" ? w : h) - (n - 1)          # one separator between children
	if (avail < n) fail("window too small: " n " panes do not fit in " (T[i] == "lr" ? w " columns" : h " rows"))
	sum = 0
	for (j = 1; j <= n; j++) {
		sz = int((T[i] == "lr" ? OW[k[j]] : OH[k[j]]) * avail / total)
		if (sz < 1) sz = 1
		NS[k[j]] = sz; sum += sz
	}
	while (sum < avail) { b = biggest(k, n, 0); NS[b]++; sum++ }
	while (sum > avail) { b = biggest(k, n, 1); if (b == 0) fail("cannot shrink"); NS[b]--; sum-- }
	pos = (T[i] == "lr" ? x : y)
	for (j = 1; j <= n; j++) {
		if (T[i] == "lr") scale(k[j], NS[k[j]], h, pos, y); else scale(k[j], w, NS[k[j]], x, pos)
		pos += NS[k[j]] + 1
	}
}
function render(i,   n, k, j, s) {
	s = W[i] "x" H[i] "," X[i] "," Y[i]
	if (T[i] == "leaf") return s "," ID[i]
	n = split(KIDS[i], k, " ")
	s = s (T[i] == "lr" ? "{" : "[")
	for (j = 1; j <= n; j++) s = s (j > 1 ? "," : "") render(k[j])
	return s (T[i] == "lr" ? "}" : "]")
}
function checksum(s,   i, c, len) {
	c = 0; len = length(s)
	for (i = 1; i <= len; i++) {
		c = int(c / 2) + (c % 2) * 32768
		c = (c + ORD[substr(s, i, 1)]) % 65536
	}
	return sprintf("%04x", c)
}
BEGIN {
	for (i = 0; i < 256; i++) ORD[sprintf("%c", i)] = i
	S = layout; sub(/^[0-9a-fA-F]{4},/, "", S); P = 1; N = 0
	root = cell()
	if (P <= length(S)) fail("trailing garbage at " P)
	for (i = 1; i <= N; i++) { OW[i] = W[i]; OH[i] = H[i] }
	scale(root, w + 0, h + 0, 0, 0)
	out = render(root)
	print checksum(out) "," out
}'

# layout_scale LAYOUT WIDTH HEIGHT -> the layout rescaled to WIDTHxHEIGHT (with a valid checksum)
layout_scale() {
	awk -v layout="$1" -v w="$2" -v h="$3" "$AI_REVIVE_LAYOUT_AWK"
}
