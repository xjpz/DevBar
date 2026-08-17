# Home Assistant 首页视觉对照

- source visual truth path: `/Users/xjpz/.codex/generated_images/019feee1-76e6-7802-af60-46e7a2fb7aef/exec-0955a952-82d3-4125-9525-cf875602e134.png`
- implementation screenshot path: `/private/tmp/devbar-ha-dashboard-after.png`
- side-by-side comparison path: `/private/tmp/devbar-ha-design-comparison.png`
- viewport: source 390 x 844 pt; implementation iPhone 17 Pro 402 x 874 pt at 3x (1206 x 2622 px)
- density normalization: implementation capture was proportionally normalized to the source height for comparison; aspect-ratio difference is under 1%
- state: configured Home Assistant dashboard, default unfiltered home view, live device data loaded

## Full-view comparison evidence

The selected design and the final simulator capture were compared side by side. The implemented screen preserves the intended Apple Home-inspired hierarchy: large white home name, translucent top controls, blue/lavender blurred wallpaper, glass summary pills, white active cards, dark inactive cards, and room-grouped masonry layout.

The full-view comparison is sufficiently readable for the title, summary strip, room headings, compact switch card, standard light/air-conditioner cards, disabled device treatment, spacing rhythm, and wallpaper crop. A separate focused crop was not required.

## Findings

- No P0, P1, or P2 visual differences remain.
- [P3] Live entity values and available room/device rows differ from the static source preview by design.
  - Location: summary strip and lower room list.
  - Evidence: the simulator uses the configured Home Assistant instance and current entity state.
  - Impact: content values differ, while card hierarchy and visual states remain consistent with the source.

## Comparison history

1. Initial source-only pass: blocked because no booted simulator evidence was available.
2. First runtime pass (`/private/tmp/devbar-ha-dashboard-before.png`): found an undersized inline home title and a compact light card that weakened the selected hierarchy.
3. Final runtime pass (`/private/tmp/devbar-ha-dashboard-after.png`): restored the large home title, changed controllable lights to standard cards, and confirmed that sensor-group cards are absent from the default homepage.

## Runtime verification

- Built and launched `cc.xjpz.DevBar` on iPhone 17 Pro simulator (iOS 27.0).
- Navigated from Overview to Tools and opened the configured Home Assistant dashboard.
- Confirmed live Home Assistant data rendered successfully.
- Confirmed presence, illuminance, water-leak, and other sensor-group cards are not shown on the default homepage.
- Confirmed controllable switch, light, air-conditioner, and unavailable-device states remain visible and distinguishable.

## Visual acceptance

- Colors: passed; wallpaper and card state colors follow the selected blue/lavender Apple Home direction.
- Typography: passed; home title, room headings, card labels, and secondary values have clear hierarchy.
- Spacing: passed; summary pills, room sections, and device cards retain a consistent rhythm.
- Image quality: passed; generated wallpaper is sharp at simulator density and remains intentionally blurred by the composition.
- Copy and state semantics: passed; live values are legible and default sensor suppression is observable.

## Follow-up polish

- P3 only: exact wallpaper crop and device ordering naturally vary by viewport and current Home Assistant inventory.

final result: passed
