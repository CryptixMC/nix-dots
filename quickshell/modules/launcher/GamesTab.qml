import QtQuick
import Quickshell
import "../../theme"

// Recommended row (most-recently-played — the only honest "recommended"
// signal available without a real usage-scoring system) + full library
// grid + one grid per launcher. Search (shared searchInput, threaded in via
// searchQuery) filters entries by name within each section rather than
// collapsing the section layout.
Item {
    id: root
    width: parent.width
    // `height` and `implicitHeight` are both bound to the SAME independent
    // expression rather than one deriving from the other — binding
    // `implicitHeight: root.height` (tried first) created a genuine
    // binding loop and silently froze at the first-computed value instead
    // of reacting to inner.implicitHeight changing later (confirmed live:
    // stuck at ~18px — just the "no games found" fallback text's height —
    // even once 36 real games had loaded and inner.implicitHeight had
    // correctly grown to 1736). Item.height's *implicit* default binding
    // is implicitHeight, so anything that makes implicitHeight depend on
    // height, even indirectly, risks exactly this loop.
    readonly property real computedHeight: Math.min(inner.implicitHeight, Theme.spacing.launcherTabBodyMaxHeight)
    height: root.computedHeight
    implicitHeight: root.computedHeight

    property string searchQuery: ""

    function matchesSearch(entry) {
        const q = root.searchQuery.trim().toLowerCase();
        return q.length === 0 || entry.name.toLowerCase().includes(q);
    }

    // Card subtitle: "last played" reads for every entry (both launchers
    // stamp lastPlayed), playtime only where a source for it actually
    // exists (Prism's instance.cfg; Steam's .acf manifests don't carry it
    // -- see GamesLibrary.qml's totalPlayedSecs comment).
    function relativeTime(epochSecs) {
        if (!epochSecs)
            return "Never played";
        const diff = Math.max(0, Date.now() / 1000 - epochSecs);
        if (diff < 60)
            return "Just now";
        if (diff < 3600)
            return `${Math.floor(diff / 60)}m ago`;
        if (diff < 86400)
            return `${Math.floor(diff / 3600)}h ago`;
        if (diff < 2592000)
            return `${Math.floor(diff / 86400)}d ago`;
        if (diff < 31536000)
            return `${Math.floor(diff / 2592000)}mo ago`;
        return `${Math.floor(diff / 31536000)}y ago`;
    }

    function formatPlaytime(secs) {
        if (!secs)
            return "";
        const hours = secs / 3600;
        return hours >= 1 ? `${hours.toFixed(hours < 10 ? 1 : 0)}h played` : `${Math.max(1, Math.floor(secs / 60))}m played`;
    }

    function cardSubtitle(entry) {
        const playtime = root.formatPlaytime(entry.totalPlayedSecs);
        const played = root.relativeTime(entry.lastPlayed);
        return playtime.length > 0 ? `${played} \u{00B7} ${playtime}` : played;
    }

    // Brand mark badge, not a themed UI icon -- no outline/filled pairing
    // (these are fixed logo glyphs, same reasoning a Steam/Minecraft logo
    // never gets "restyled" elsewhere). \u{} escapes, not literal glyph
    // bytes, per this session's established Nerd-Font-PUA corruption fix.
    function launcherGlyph(launcherName) {
        return launcherName === "Steam" ? "\u{F04D3}" : "\u{F0373}"; // md-steam / md-minecraft
    }

    readonly property var recommended: GamesLibrary.entries.slice().sort((a, b) => b.lastPlayed - a.lastPlayed).slice(0, 10)
    readonly property var filteredAll: GamesLibrary.entries.filter(root.matchesSearch)
    readonly property var launchers: [...new Set(GamesLibrary.entries.map(e => e.launcher))]

    // Columns for the Library/per-launcher grids, derived the same way
    // GridView itself lays them out (floor(width / cellWidth)) — used only
    // to drive Up/Down row-stepping through the flattened nav index below,
    // not to size anything.
    readonly property int gridColumns: Math.max(1, Math.floor(root.width / (Theme.spacing.gameCardWidth + Theme.spacing.gameCardGap)))

    // Every visible section in top-to-bottom render order. Recommended's
    // "columns" is its own length (one horizontal row), so Up/Down always
    // falls straight through it into Library — there's no row above it to
    // step to.
    readonly property var sections: {
        const secs = [];
        if (root.recommended.length > 0)
            secs.push({
                key: "recommended",
                items: root.recommended,
                columns: root.recommended.length
            });
        if (root.filteredAll.length > 0)
            secs.push({
                key: "library",
                items: root.filteredAll,
                columns: root.gridColumns
            });
        for (const l of root.launchers) {
            const entries = root.filteredAll.filter(e => e.launcher === l);
            if (entries.length > 0)
                secs.push({
                    key: `launcher:${l}`,
                    items: entries,
                    columns: root.gridColumns
                });
        }
        return secs;
    }

    // Flattened keyboard-nav index spanning every section in visual order
    // — the whole point being that holding Right walks Recommended, then
    // Library, then every per-launcher grid in turn, and only falls off
    // the end (returning false, so Launcher.qml switches tabs) once
    // there's genuinely nothing left, matching Liam's own explicit ask:
    // "if there is nothing to move forward or backwards for I should be
    // able to use the arrow keys to switch tabs as well" (real quote,
    // sessions.db transcript). Each entry carries its own section's
    // start/length/columns so Up/Down can step by row and cross section
    // boundaries without a second lookup pass.
    readonly property var navItems: {
        const flat = [];
        for (const sec of root.sections) {
            const sectionStart = flat.length;
            for (let i = 0; i < sec.items.length; i++) {
                flat.push({
                    entry: sec.items[i],
                    sectionKey: sec.key,
                    indexInSection: i,
                    sectionColumns: sec.columns,
                    sectionStart: sectionStart,
                    sectionLength: sec.items.length
                });
            }
        }
        return flat;
    }

    property int currentIndex: 0

    readonly property var currentNavEntry: root.navItems[root.currentIndex] ?? null

    // Local (within-section) index of whatever's currently selected, or -1
    // if the selection isn't in that section — feeds each ListView/
    // GridView's own `currentIndex` so exactly one delegate across the
    // whole tab shows the keyboard-highlight border at a time.
    function localIndexFor(sectionKey) {
        const cur = root.currentNavEntry;
        if (!cur || cur.sectionKey !== sectionKey)
            return -1;
        return cur.indexInSection;
    }

    // Hover sets the flattened index from a section-local one — the
    // inverse of localIndexFor, used by every delegate's MouseArea.
    function setCurrentFromSection(sectionKey, localIndex) {
        const items = root.navItems;
        for (let i = 0; i < items.length; i++) {
            if (items[i].sectionKey === sectionKey && items[i].indexInSection === localIndex) {
                root.currentIndex = i;
                return;
            }
        }
    }

    // Row-major offset of a section's own last row (its only row that can
    // be short, since GridView fills left-to-right/top-to-bottom).
    function lastRowOffset(sectionDescriptor) {
        const rows = Math.ceil(sectionDescriptor.sectionLength / sectionDescriptor.sectionColumns);
        return (rows - 1) * sectionDescriptor.sectionColumns;
    }

    function stepVertical(dir) {
        const items = root.navItems;
        const cur = items[root.currentIndex];
        if (!cur)
            return false;
        const col = cur.indexInSection % cur.sectionColumns;
        const withinTarget = root.currentIndex + dir * cur.sectionColumns;
        if (withinTarget >= cur.sectionStart && withinTarget < cur.sectionStart + cur.sectionLength) {
            root.currentIndex = withinTarget;
            return true;
        }
        if (dir > 0) {
            const nextStart = cur.sectionStart + cur.sectionLength;
            if (nextStart >= items.length)
                return false;
            const next = items[nextStart];
            const firstRowLen = Math.min(next.sectionColumns, next.sectionLength);
            root.currentIndex = nextStart + Math.min(col, firstRowLen - 1);
            return true;
        } else {
            if (cur.sectionStart === 0)
                return false;
            const prev = items[cur.sectionStart - 1];
            const rowOffset = root.lastRowOffset(prev);
            const itemsInRow = prev.sectionLength - rowOffset;
            root.currentIndex = prev.sectionStart + rowOffset + Math.min(col, itemsInRow - 1);
            return true;
        }
    }

    function moveLeft() {
        if (root.currentIndex > 0) {
            root.currentIndex--;
            return true;
        }
        return false;
    }

    function moveRight() {
        if (root.currentIndex < root.navItems.length - 1) {
            root.currentIndex++;
            return true;
        }
        return false;
    }

    // Up/Down never switch tabs (Launcher.qml ignores their return value),
    // so these just clamp at the true top/bottom of the flattened index
    // rather than reporting false the way moveLeft/moveRight do.
    function moveUp() {
        return root.stepVertical(-1);
    }

    function moveDown() {
        return root.stepVertical(1);
    }

    function activate() {
        const item = root.currentNavEntry;
        if (item && item.entry) {
            item.entry.launch();
            LauncherState.hide();
        }
    }

    // GamesLibrary.entries can populate asynchronously after this tab is
    // already active (real Steam/Prism scans, not instant) -- without this,
    // an in-flight currentIndex from a longer previous list could point
    // past the end of a freshly-shrunk one.
    onNavItemsChanged: {
        if (root.currentIndex >= root.navItems.length)
            root.currentIndex = Math.max(0, root.navItems.length - 1);
    }

    // Shared card visual, parameterized over `current`/`hovered` rather than
    // duplicated per-view -- cardDelegate and recommendedCardDelegate below
    // are now thin wrappers picking that state up from GridView.isCurrentItem
    // vs ListView.isCurrentItem (the one real difference between a grid card
    // and a recommended-row card) and forwarding it in.
    component GameCard: Rectangle {
        id: cardRoot
        required property var modelData
        required property bool current
        signal hovered
        signal activated

        readonly property bool isHovered: mouse.containsMouse
        width: Theme.spacing.gameCardWidth
        height: Theme.spacing.gameCardImageHeight
        radius: Theme.radius.input
        // Slightly transparent base — only visible through the no-cover-art
        // fallback glyph, since real box art (2:3, matching Steam's native
        // 600x900 library images) fills the frame completely now that the
        // card itself IS the art frame, not a square crop of a taller image.
        color: ThemeDefaults.alpha(Theme.base16.base02, 0.5)
        border.width: (cardRoot.isHovered || cardRoot.current) ? 2 : 0
        border.color: Theme.color.accentPurple
        clip: true
        scale: (cardRoot.isHovered || cardRoot.current) ? 1.035 : 1.0
        transformOrigin: Item.Center

        Behavior on border.width {
            NumberAnimation { duration: Theme.motion.hoverColor.duration }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
        }

        Image {
            anchors.fill: parent
            visible: cardRoot.modelData.iconSource.length > 0
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: cardRoot.modelData.iconSource
        }

        Text {
            anchors.centerIn: parent
            visible: cardRoot.modelData.iconSource.length === 0
            // Launcher-appropriate default rather than one generic glyph
            // for everything -- a Prism/Minecraft instance with no
            // resolvable art (GamesLibrary.qml's three icon tiers all
            // missed, which only happens for a never-launched instance on
            // one of Prism's built-in icon names) reads better as the
            // Minecraft mark than a gamepad that says nothing about which
            // launcher it's even from.
            text: cardRoot.modelData.launcher === "Prism Launcher" ? "\u{F0373}" : "\u{F0EB5}" // md-minecraft / md-gamepad_square
            renderType: Text.NativeRendering
            font.family: Theme.font.family
            font.pixelSize: 32
            color: Theme.color.accentPurple
        }

        // Launcher badge -- a small brand mark rather than relying solely
        // on which section a card sits in, since a search result flattens
        // straight into "Library" and loses that context.
        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
                margins: 6
            }
            width: badgeIcon.implicitWidth + 8
            height: badgeIcon.implicitHeight + 6
            radius: Theme.radius.input
            color: ThemeDefaults.alpha(Theme.base16.base00, 0.72)

            Text {
                id: badgeIcon
                anchors.centerIn: parent
                text: root.launcherGlyph(cardRoot.modelData.launcher)
                renderType: Text.NativeRendering
                font.family: Theme.font.family
                font.pixelSize: 11
                color: Theme.color.fg
            }
        }

        // Bottom scrim + overlaid title/subtitle, Steam/GOG-storefront style
        // — replaces the old separate label row below the art, which both
        // wasted vertical space and couldn't fit a second line for
        // last-played/playtime.
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: parent.height * 0.42
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: ThemeDefaults.alpha(Theme.base16.base00, 0.92) }
            }

            Column {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    margins: 8
                }
                spacing: 1

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: cardRoot.modelData.name
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.cardSubtitle(cardRoot.modelData)
                    color: ThemeDefaults.alpha(Theme.base16.base05, 0.7)
                    font.family: Theme.font.family
                    font.pixelSize: 10
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: cardRoot.hovered()
            onClicked: cardRoot.activated()
        }
    }

    Component {
        id: cardDelegate

        GameCard {
            id: card
            required property int index
            current: GridView.isCurrentItem
            // GridView.view can be null for a hover event that lands
            // mid-teardown (confirmed live: switching away from Games
            // tab while the cursor is still over a card threw "Cannot
            // read property 'navSectionKey' of null" here) -- the
            // delegate's own view reference isn't guaranteed once its
            // GridView starts unmounting.
            onHovered: {
                if (GridView.view)
                    root.setCurrentFromSection(GridView.view.navSectionKey, card.index);
            }
            onActivated: {
                card.modelData.launch();
                LauncherState.hide();
            }
        }
    }

    // Recommended row only -- the one section that's a horizontal ListView
    // rather than a GridView, so it needs ListView.isCurrentItem instead of
    // GridView.isCurrentItem and setCurrentFromSection's fixed "recommended"
    // key instead of reading it off the view. Otherwise identical to
    // cardDelegate, both riding on the same GameCard visual above.
    Component {
        id: recommendedCardDelegate

        GameCard {
            id: rcard
            required property int index
            current: ListView.isCurrentItem
            onHovered: root.setCurrentFromSection("recommended", rcard.index)
            onActivated: {
                rcard.modelData.launch();
                LauncherState.hide();
            }
        }
    }

    component SectionLabel: Row {
        id: sectionLabel
        property string glyph: ""
        property string label: ""
        property int count: 0
        spacing: 6

        Text {
            visible: sectionLabel.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: sectionLabel.glyph
            renderType: Text.NativeRendering
            color: Theme.color.accentPurple
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sectionLabel.count > 0 ? `${sectionLabel.label} \u{00B7} ${sectionLabel.count}` : sectionLabel.label
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            font.bold: true
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: inner.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: inner
            width: parent.width
            spacing: Theme.spacing.gameSectionGap

            Column {
                width: parent.width
                spacing: Theme.spacing.gameSectionHeaderGap
                visible: root.recommended.length > 0

                SectionLabel {
                    // "Recommended" overstated what this actually is --
                    // there's no real scoring behind it, just lastPlayed
                    // sorted descending (see the `recommended` property
                    // above). Naming it what it honestly is.
                    glyph: "\u{F02DA}" // md-history
                    label: "Recently Played"
                }

                ListView {
                    id: recommendedList
                    width: parent.width
                    height: Theme.spacing.gameRecommendedRowHeight
                    orientation: ListView.Horizontal
                    spacing: Theme.spacing.gameCardGap
                    clip: true
                    model: root.recommended
                    delegate: recommendedCardDelegate
                    // Keeps the keyboard-highlighted card scrolled into
                    // view as currentIndex changes via Launcher.qml's
                    // arrow-key handling, routed through root.localIndexFor
                    // so this only lights up while the flattened selection
                    // is actually inside this section.
                    currentIndex: root.localIndexFor("recommended")
                    highlightMoveDuration: Theme.motion.hoverColor.duration
                    onCurrentIndexChanged: if (currentIndex >= 0)
                        positionViewAtIndex(currentIndex, ListView.Contain)
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacing.gameSectionHeaderGap
                visible: root.filteredAll.length > 0

                SectionLabel {
                    glyph: "\u{F11D9}" // md-view_grid_outline
                    label: "Library"
                    count: root.filteredAll.length
                }

                GridView {
                    id: libraryGrid
                    property string navSectionKey: "library"
                    width: parent.width
                    height: Math.min(contentHeight, Theme.spacing.gameGridRowHeight * 2)
                    clip: true
                    interactive: false
                    cellWidth: Theme.spacing.gameCardWidth + Theme.spacing.gameCardGap
                    cellHeight: Theme.spacing.gameGridRowHeight
                    model: root.filteredAll
                    delegate: cardDelegate
                    currentIndex: root.localIndexFor(navSectionKey)
                    onCurrentIndexChanged: if (currentIndex >= 0)
                        positionViewAtIndex(currentIndex, GridView.Contain)
                }
            }

            Repeater {
                model: root.launchers

                delegate: Column {
                    id: section
                    required property string modelData
                    width: inner.width
                    spacing: Theme.spacing.gameSectionHeaderGap

                    readonly property var sectionEntries: root.filteredAll.filter(e => e.launcher === section.modelData)
                    visible: sectionEntries.length > 0

                    SectionLabel {
                        glyph: root.launcherGlyph(section.modelData)
                        label: section.modelData
                        count: section.sectionEntries.length
                    }

                    GridView {
                        property string navSectionKey: `launcher:${section.modelData}`
                        width: section.width
                        height: Math.min(contentHeight, Theme.spacing.gameGridRowHeight * 2)
                        clip: true
                        interactive: false
                        cellWidth: Theme.spacing.gameCardWidth + Theme.spacing.gameCardGap
                        cellHeight: Theme.spacing.gameGridRowHeight
                        model: section.sectionEntries
                        delegate: cardDelegate
                        currentIndex: root.localIndexFor(navSectionKey)
                        onCurrentIndexChanged: if (currentIndex >= 0)
                            positionViewAtIndex(currentIndex, GridView.Contain)
                    }
                }
            }

            Text {
                visible: GamesLibrary.entries.length === 0
                text: "No games found (Steam/Prism Launcher libraries empty or not installed)."
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
            }

            // Distinct from the "nothing installed at all" state above --
            // a search that matches nothing used to just render every
            // section as empty with no explanation why.
            Text {
                visible: GamesLibrary.entries.length > 0 && root.filteredAll.length === 0
                text: `No games match "${root.searchQuery.trim()}".`
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
            }
        }
    }
}
