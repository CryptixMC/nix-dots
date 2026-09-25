pragma Singleton
import QtQml

// fzf-style subsequence fuzzy matcher — replaces the old FolderListModel
// substring-glob filtering (FilesTab.qml's previous `*query*` approach),
// which also happened to be silently case-sensitive by default
// (FolderListModel.caseSensitive defaults to true and was never set,
// which is the actual reason "doc" could never match "Documents"). Shared
// across the Files tab's in-place filter and its cross-directory
// "Elsewhere" search rather than duplicated, and deliberately a plain
// singleton rather than tab-local state since nothing here depends on
// FilesState -- Applications/Games' own substring-only matching
// (Launcher.qml's filteredEntries, GamesTab's matchesSearch) are
// candidates to move onto this same scorer in a later pass.
QtObject {
    id: root

    // Returns -1 when `needle` isn't a subsequence of `haystack`
    // (case-insensitive); otherwise a higher-is-better score built from a
    // start-of-string bonus, a match-after-separator bonus (so
    // "de" scores much higher on "in-progress/design" than the same two
    // letters buried mid-word), a consecutive-run bonus, and a small exact-
    // case bonus. Not calibrated against real fzf, just good enough to
    // rank "the obviously right answer" first for filenames/paths.
    function score(needle, haystack) {
        if (needle.length === 0)
            return 0;
        const n = needle.toLowerCase();
        const h = haystack.toLowerCase();

        let hi = 0;
        let total = 0;
        let consecutive = 0;
        let firstMatch = -1;

        for (let ni = 0; ni < n.length; ni++) {
            const c = n[ni];
            let found = -1;
            for (let scan = hi; scan < h.length; scan++) {
                if (h[scan] === c) {
                    found = scan;
                    break;
                }
            }
            if (found === -1)
                return -1;
            if (firstMatch === -1)
                firstMatch = found;

            let bonus = 1;
            if (found === 0) {
                bonus += 8;
            } else {
                const prev = h[found - 1];
                if (prev === "/" || prev === "_" || prev === "-" || prev === "." || prev === " ")
                    bonus += 6;
            }
            if (found === hi && ni > 0) {
                consecutive++;
                bonus += consecutive * 3;
            } else {
                consecutive = 0;
            }
            if (haystack[found] === needle[ni])
                bonus += 1;

            total += bonus;
            hi = found + 1;
        }

        // Tie-breakers so, among equally-good subsequence matches, an
        // earlier and shorter haystack ranks first -- "doc" should put
        // "Documents" ahead of "some/very/long/path/to/a/doc-ish/file".
        total -= firstMatch * 0.5;
        total -= Math.max(0, haystack.length - needle.length) * 0.05;
        return total;
    }

    // Filters + ranks `items` by `keyFn(item)` (defaults to the item
    // itself when it's already a string). Passing an empty/whitespace
    // needle returns `items` unchanged and unranked -- the empty-query
    // case is "show everything in its normal order", not "everything
    // scores 0".
    function filterSort(needle, items, keyFn) {
        const q = needle.trim();
        if (q.length === 0)
            return items;
        const scored = [];
        for (const it of items) {
            const key = keyFn ? keyFn(it) : it;
            const s = root.score(q, key);
            if (s >= 0)
                scored.push({
                    item: it,
                    score: s
                });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.map(s => s.item);
    }
}
