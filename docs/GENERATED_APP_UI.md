# Generated app UI contract

Pocket-generated apps are compact task surfaces inside an iPhone shell. They are not websites, landing pages, dashboards, or miniature marketing pages.

## Required structure

1. Use one compact title bar, one primary data view, and one primary action.
2. Keep the shell within `100dvh` and the available width. The data region may scroll internally; the document must not scroll horizontally.
3. Keep the main action reachable near the bottom of the screen. Use a bottom sheet for entry forms that cannot fit without crowding the data view.
4. Use a single-column compact layout. Wider windows may center the same app surface; they must not turn it into a desktop dashboard.
5. Respect safe areas and keep interactive targets at least 44 by 44 points.

## Visual rules

- Use solid colors only. No gradients, glows, meshes, glass effects, decorative grids, background illustrations, or heavy shadows.
- Use one accent color and the system typeface.
- Do not place cards inside cards or containers inside containers. Prefer flat rows separated by spacing or a divider.
- A container must express a real boundary: the app shell, a modal sheet, an alert, or a selected state. It must not exist only to decorate content.
- Never wrap passive text in a rounded rectangle. Do not turn every status or control into a pill. The main screen may have at most one bordered content surface.
- Do not add giant metrics, hero areas, navigation bars, tab bars, footers, promotional sections, or browser-like chrome.
- Use familiar controls and consistent alignment. Put controls next to the content they affect.

## Copy rules

- App name: short noun phrase, at most 32 characters.
- Summary: one functional line, at most 72 characters.
- Field labels: one to three words, at most 24 characters.
- Primary action: direct verb phrase, at most 20 characters.
- Placeholder: example input, not instructions, at most 48 characters.
- Empty and error states: one short title and one actionable sentence.
- No eyebrow labels, slogans, welcome copy, repeated explanations, redundant subheadings, section descriptions, possessive filler such as “your,” or marketing claims.
- Do not repeat counts or add a list heading when the app title already explains the list.
- If text does not change the next action or explain the current state, remove it.

## Hierarchy and behavior

- Put the primary task and current data first. Hide secondary actions until requested.
- Use progressive disclosure for forms and secondary details rather than showing every control at once.
- Use rows for repeated records and keep every row structurally consistent.
- Show real loading, success, empty, and error states. Never invent progress or capabilities.
- Preserve keyboard focus, readable contrast, reduced-motion behavior, and concise accessible names.

## Basis

This contract applies the product's stricter visual direction on top of platform guidance:

- Apple says layouts should fit the device screen, avoid horizontal scrolling, keep controls near the content they modify, and use at least 44-point touch targets: https://developer.apple.com/design/tips/
- Apple recommends limiting onscreen controls, prioritizing the primary task, using progressive disclosure, and respecting safe areas: https://developer.apple.com/design/human-interface-guidelines/designing-for-ios/ and https://developer.apple.com/design/human-interface-guidelines/layout
- Apple recommends checking whether every word is necessary and using brief, direct, action-oriented labels: https://developer.apple.com/design/human-interface-guidelines/writing
- Material's list guidance favors short, scannable, structurally consistent rows: https://m3.material.io/components/lists/overview
- Carbon warns against list content nested more than one level deep and recommends short list titles and concise row content: https://www.carbondesignsystem.com/building-blocks/core/components/contained-list/guidelines
# iPhone safe areas and live data

- Respect system safe areas and add 24 CSS pixels of breathing room below the top inset. Reserve room for Pocket's close control.
- Keep the primary action full width, 16 pixels above the bottom safe area. Minimum touch targets are 44 by 44.
- Remove redundant title subtitles and decorative app marks from the working screen.
- Render saved records as content-sized rows. Never stretch a row or an empty state into a blank card.
- Background refreshes must preserve visible content. Never replace saved rows with a skeleton on a polling timer. Allow only one refresh in flight.
- A tracker emphasizes its actual count; supporting records remain readable beneath it.

Source: [Apple layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout).

