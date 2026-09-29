pragma Singleton
import QtQml

// fzf-style case-insensitive subsequence matcher shared by the Files tab's
// filter and its cross-directory search.
QtObject {
    id: root

    // Returns -1 when `needle` isn't a case-insensitive subsequence of `haystack`,
    // otherwise a higher-is-better score (start, after-separator, consecutive-run
    // and exact-case bonuses).
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

        // Tie-breakers: earlier and shorter matches rank first.
        total -= firstMatch * 0.5;
        total -= Math.max(0, haystack.length - needle.length) * 0.05;
        return total;
    }

    // Filters and ranks `items` by `keyFn(item)` (defaults to the item itself).
    // An empty needle returns `items` unchanged, in their normal order.
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
